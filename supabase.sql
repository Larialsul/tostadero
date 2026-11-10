-- EL GRAN MAESTRO TOSTADERO — Supabase schema
-- Ejecuta este script en Supabase > SQL Editor.
-- Requiere Authentication > Providers > Anonymous Sign-ins habilitado.
create extension if not exists pgcrypto;

create table if not exists public.toast_rooms (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  invite_hash bytea not null unique,
  director_id uuid not null references auth.users(id) on delete cascade,
  status text not null default 'lobby' check (status in ('lobby','submissions','voting','finished')),
  challenge text,
  created_at timestamptz not null default now()
);

create table if not exists public.toast_room_members (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references public.toast_rooms(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  display_name text not null check (char_length(display_name) between 1 and 35),
  role text not null default 'player' check (role in ('director','player')),
  created_at timestamptz not null default now(),
  unique(room_id,user_id),
  unique(room_id,id)
);

create table if not exists public.toast_entries (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references public.toast_rooms(id) on delete cascade,
  member_id uuid not null,
  title text not null check (char_length(title) between 1 and 50),
  base text not null,
  ingredients text[] not null check (cardinality(ingredients) between 1 and 5),
  recipe text not null default '',
  pitch text not null default '',
  created_at timestamptz not null default now(),
  unique(member_id),
  foreign key(room_id,member_id) references public.toast_room_members(room_id,id) on delete cascade
);

create table if not exists public.toast_votes (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references public.toast_rooms(id) on delete cascade,
  toast_id uuid not null references public.toast_entries(id) on delete cascade,
  voter_id uuid not null references auth.users(id) on delete cascade,
  rating int not null check (rating between 1 and 5),
  created_at timestamptz not null default now(),
  unique(toast_id,voter_id)
);

create table if not exists public.toast_judge_scores (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references public.toast_rooms(id) on delete cascade,
  toast_id uuid not null unique references public.toast_entries(id) on delete cascade,
  judge_id uuid not null references auth.users(id) on delete cascade,
  taste int not null check (taste between 0 and 5),
  originality int not null check (originality between 0 and 5),
  presentation int not null check (presentation between 0 and 3),
  explanation int not null check (explanation between 0 and 2),
  total_score int generated always as (taste + originality + presentation + explanation) stored,
  updated_at timestamptz not null default now()
);

create index if not exists toast_entries_room_idx on public.toast_entries(room_id);
create index if not exists toast_votes_room_idx on public.toast_votes(room_id);
create index if not exists toast_scores_room_idx on public.toast_judge_scores(room_id);

create or replace function public.is_toast_room_member(p_room_id uuid)
returns boolean language sql stable security definer set search_path=public
as $$ select exists(select 1 from public.toast_room_members m where m.room_id=p_room_id and m.user_id=auth.uid()); $$;

create or replace function public.is_toast_room_director(p_room_id uuid)
returns boolean language sql stable security definer set search_path=public
as $$ select exists(select 1 from public.toast_rooms r where r.id=p_room_id and r.director_id=auth.uid()); $$;

alter table public.toast_rooms enable row level security;
alter table public.toast_room_members enable row level security;
alter table public.toast_entries enable row level security;
alter table public.toast_votes enable row level security;
alter table public.toast_judge_scores enable row level security;

drop policy if exists "room members can read room" on public.toast_rooms;
create policy "room members can read room" on public.toast_rooms for select to authenticated using (public.is_toast_room_member(id));

drop policy if exists "members can read members" on public.toast_room_members;
create policy "members can read members" on public.toast_room_members for select to authenticated using (public.is_toast_room_member(room_id));

drop policy if exists "members can read entries" on public.toast_entries;
create policy "members can read entries" on public.toast_entries for select to authenticated using (public.is_toast_room_member(room_id));

drop policy if exists "members can read votes" on public.toast_votes;
create policy "members can read votes" on public.toast_votes for select to authenticated using (public.is_toast_room_member(room_id));

drop policy if exists "members can read scores" on public.toast_judge_scores;
create policy "members can read scores" on public.toast_judge_scores for select to authenticated using (public.is_toast_room_member(room_id));

-- No direct table writes from the browser: writes go through checked RPC functions.

create or replace function public.create_toast_room(p_room_name text, p_display_name text)
returns table(room_id uuid, invite_token text)
language plpgsql security definer set search_path=public,extensions
as $$
declare v_room_id uuid; v_token text;
begin
 if auth.uid() is null then raise exception 'Debes iniciar sesión.'; end if;
 if length(trim(p_display_name)) not between 1 and 35 then raise exception 'Nombre no válido.'; end if;
 v_token := encode(gen_random_bytes(24),'hex');
 insert into public.toast_rooms(name,invite_hash,director_id)
 values(coalesce(nullif(trim(p_room_name),''),'El Gran Maestro Tostadero'),digest(v_token,'sha256'),auth.uid())
 returning id into v_room_id;
 insert into public.toast_room_members(room_id,user_id,display_name,role)
 values(v_room_id,auth.uid(),trim(p_display_name),'director');
 return query select v_room_id,v_token;
end; $$;

create or replace function public.join_toast_room(p_invite_token text, p_display_name text)
returns table(room_id uuid)
language plpgsql security definer set search_path=public
as $$
declare v_room_id uuid;
begin
 if auth.uid() is null then raise exception 'Debes iniciar sesión.'; end if;
 if length(trim(p_display_name)) not between 1 and 35 then raise exception 'Nombre no válido.'; end if;
 select r.id into v_room_id from public.toast_rooms r
 where r.invite_hash=digest(p_invite_token,'sha256') and r.status <> 'finished';
 if v_room_id is null then raise exception 'El enlace no es válido o el concurso ha terminado.'; end if;
 insert into public.toast_room_members(room_id,user_id,display_name,role)
 values(v_room_id,auth.uid(),trim(p_display_name),'player')
 on conflict(room_id,user_id) do update set display_name=excluded.display_name;
 return query select v_room_id;
end; $$;

create or replace function public.submit_toast_entry(
 p_room_id uuid,p_title text,p_base text,p_ingredients text[],p_recipe text default '',p_pitch text default ''
) returns uuid language plpgsql security definer set search_path=public
as $$
declare v_member_id uuid; v_id uuid;
begin
 if not public.is_toast_room_member(p_room_id) then raise exception 'No perteneces a esta sala.'; end if;
 if not exists(select 1 from public.toast_rooms where id=p_room_id and status='submissions') then raise exception 'La presentación de tostadas no está abierta.'; end if;
 select id into v_member_id from public.toast_room_members where room_id=p_room_id and user_id=auth.uid();
 if cardinality(p_ingredients) not between 1 and 5 then raise exception 'Elige entre 1 y 5 ingredientes.'; end if;
 insert into public.toast_entries(room_id,member_id,title,base,ingredients,recipe,pitch)
 values(p_room_id,v_member_id,trim(p_title),trim(p_base),p_ingredients,coalesce(p_recipe,''),coalesce(p_pitch,''))
 returning id into v_id;
 return v_id;
end; $$;

create or replace function public.cast_toast_vote(p_toast_id uuid,p_rating int)
returns void language plpgsql security definer set search_path=public
as $$
declare v_room_id uuid; v_owner uuid;
begin
 select t.room_id,m.user_id into v_room_id,v_owner
 from public.toast_entries t join public.toast_room_members m on m.id=t.member_id
 where t.id=p_toast_id;
 if v_room_id is null then raise exception 'Tostada no encontrada.'; end if;
 if not public.is_toast_room_member(v_room_id) then raise exception 'No perteneces a esta sala.'; end if;
 if not exists(select 1 from public.toast_rooms where id=v_room_id and status='voting') then raise exception 'La votación no está abierta.'; end if;
 if v_owner=auth.uid() then raise exception 'No puedes votar tu propia tostada.'; end if;
 if p_rating not between 1 and 5 then raise exception 'La valoración debe estar entre 1 y 5.'; end if;
 insert into public.toast_votes(room_id,toast_id,voter_id,rating) values(v_room_id,p_toast_id,auth.uid(),p_rating);
end; $$;

create or replace function public.score_toast_entry(
 p_toast_id uuid,p_taste int,p_originality int,p_presentation int,p_explanation int
) returns void language plpgsql security definer set search_path=public
as $$
declare v_room_id uuid;
begin
 select room_id into v_room_id from public.toast_entries where id=p_toast_id;
 if v_room_id is null or not public.is_toast_room_director(v_room_id) then raise exception 'Solo el director puede puntuar.'; end if;
 if p_taste not between 0 and 5 or p_originality not between 0 and 5 or p_presentation not between 0 and 3 or p_explanation not between 0 and 2 then
  raise exception 'Puntuación fuera de rango.';
 end if;
 insert into public.toast_judge_scores(room_id,toast_id,judge_id,taste,originality,presentation,explanation)
 values(v_room_id,p_toast_id,auth.uid(),p_taste,p_originality,p_presentation,p_explanation)
 on conflict(toast_id) do update set taste=excluded.taste,originality=excluded.originality,presentation=excluded.presentation,explanation=excluded.explanation,judge_id=auth.uid(),updated_at=now();
end; $$;

create or replace function public.set_toast_room_status(p_room_id uuid,p_status text)
returns void language plpgsql security definer set search_path=public
as $$
begin
 if p_status not in ('submissions','voting','finished') then raise exception 'Estado no válido.'; end if;
 update public.toast_rooms set status=p_status
 where id=p_room_id and director_id=auth.uid();
 if not found then raise exception 'No eres director de esta sala.'; end if;
end; $$;

create or replace function public.set_toast_room_challenge(p_room_id uuid,p_challenge text)
returns void language plpgsql security definer set search_path=public
as $$
begin
 update public.toast_rooms set challenge=nullif(trim(p_challenge),'')
 where id=p_room_id and director_id=auth.uid();
 if not found then raise exception 'No eres director de esta sala.'; end if;
end; $$;

revoke all on function public.is_toast_room_member(uuid) from public, anon;
revoke all on function public.is_toast_room_director(uuid) from public, anon;
revoke all on function public.create_toast_room(text,text) from public, anon;
revoke all on function public.join_toast_room(text,text) from public, anon;
revoke all on function public.submit_toast_entry(uuid,text,text,text[],text,text) from public, anon;
revoke all on function public.cast_toast_vote(uuid,int) from public, anon;
revoke all on function public.score_toast_entry(uuid,int,int,int,int) from public, anon;
revoke all on function public.set_toast_room_status(uuid,text) from public, anon;
revoke all on function public.set_toast_room_challenge(uuid,text) from public, anon;

grant execute on function public.is_toast_room_member(uuid) to authenticated;
grant execute on function public.is_toast_room_director(uuid) to authenticated;

grant usage on schema public to authenticated;
grant select on public.toast_rooms,public.toast_room_members,public.toast_entries,public.toast_votes,public.toast_judge_scores to authenticated;
grant execute on function public.create_toast_room(text,text) to authenticated;
grant execute on function public.join_toast_room(text,text) to authenticated;
grant execute on function public.submit_toast_entry(uuid,text,text,text[],text,text) to authenticated;
grant execute on function public.cast_toast_vote(uuid,int) to authenticated;
grant execute on function public.score_toast_entry(uuid,int,int,int,int) to authenticated;
grant execute on function public.set_toast_room_status(uuid,text) to authenticated;
grant execute on function public.set_toast_room_challenge(uuid,text) to authenticated;

-- Para actualizaciones en directo:
-- En Supabase > Database > Replication, activa Realtime para:
-- toast_rooms, toast_room_members, toast_entries, toast_votes, toast_judge_scores.
