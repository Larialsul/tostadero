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

create or replace function public.set_toast_room_status(p_status text)
returns void language plpgsql security definer set search_path=public
as $$
declare v_room_id uuid;
begin
 if p_status not in ('submissions','voting','finished') then raise exception 'Estado no válido.'; end if;
 update public.toast_rooms set status=p_status where director_id=auth.uid()
 returning id into v_room_id;
 if v_room_id is null then raise exception 'No eres director de una sala.'; end if;
end; $$;

create or replace function public.set_toast_room_challenge(p_challenge text)
returns void language plpgsql security definer set search_path=public
as $$
declare v_room_id uuid;
begin
 update public.toast_rooms set challenge=nullif(trim(p_challenge),'')
 where director_id=auth.uid() returning id into v_room_id;
 if v_room_id is null then raise exception 'No eres director de una sala.'; end if;
end; $$;

grant usage on schema public to authenticated;
grant select on public.toast_rooms,public.toast_room_members,public.toast_entries,public.toast_votes,public.toast_judge_scores to authenticated;
grant execute on function public.create_toast_room(text,text) to authenticated;
grant execute on function public.join_toast_room(text,text) to authenticated;
grant execute on function public.submit_toast_entry(uuid,text,text,text[],text,text) to authenticated;
grant execute on function public.cast_toast_vote(uuid,int) to authenticated;
grant execute on function public.score_toast_entry(uuid,int,int,int,int) to authenticated;
grant execute on function public.set_toast_room_status(text) to authenticated;
grant execute on function public.set_toast_room_challenge(text) to authenticated;

-- Para actualizaciones en directo:
-- En Supabase > Database > Replication, activa Realtime para:
-- toast_rooms, toast_room_members, toast_entries, toast_votes, toast_judge_scores.


-- ===== ACTUALIZACIÓN DE REGLAS V2 (también disponible en supabase_update.sql) =====
-- ACTUALIZACIÓN: presentación libre, reto aleatorio y votación simple.
-- Ejecutar UNA VEZ en Supabase > SQL Editor, sobre el proyecto ya existente.

-- 1) Asignar un reto aleatorio a salas antiguas que aún no tengan ninguno.
DO $$
DECLARE
  v_challenges text[] := ARRAY[
    '🌋 En algún punto de la preparación debes mencionar un volcán y relacionarlo con tu tostada.',
    '🐉 En la preparación debe aparecer un dragón que tenga una opinión muy firme sobre uno de los ingredientes.',
    '📺 Describe al menos un paso como si estuvieras vendiendo la tostada en un anuncio de teletienda.',
    '👽 Uno de los ingredientes debe ser presentado como un misterioso descubrimiento extraterrestre.',
    '💥 Incluye un efecto de sonido escrito (¡PLOF!, ¡CHOF!, ¡BOING!) dentro de la preparación.',
    '⚠️ Añade una advertencia absurda sobre los posibles efectos secundarios de comer tu tostada.',
    '🏴‍☠️ En algún momento, explica un paso de la receta como lo haría un pirata.',
    '🗡️ Presenta uno de los ingredientes como si fuera un arma legendaria con nombre propio.',
    '👑 La preparación debe incluir una frase de un rey o una reina que pruebe tu tostada.',
    '🎵 Incluye una pequeña rima de dos versos dentro de la descripción de la preparación.'
  ];
BEGIN
  UPDATE public.toast_rooms
  SET challenge = v_challenges[1 + floor(random() * cardinality(v_challenges))::int];
END $$;

-- 2) Las salas nuevas reciben su reto al crearse. El director no interviene.
CREATE OR REPLACE FUNCTION public.create_toast_room(p_room_name text, p_display_name text)
RETURNS TABLE(room_id uuid, invite_token text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_room_id uuid;
  v_token text;
  v_challenges text[] := ARRAY[
    '🌋 En algún punto de la preparación debes mencionar un volcán y relacionarlo con tu tostada.',
    '🐉 En la preparación debe aparecer un dragón que tenga una opinión muy firme sobre uno de los ingredientes.',
    '📺 Describe al menos un paso como si estuvieras vendiendo la tostada en un anuncio de teletienda.',
    '👽 Uno de los ingredientes debe ser presentado como un misterioso descubrimiento extraterrestre.',
    '💥 Incluye un efecto de sonido escrito (¡PLOF!, ¡CHOF!, ¡BOING!) dentro de la preparación.',
    '⚠️ Añade una advertencia absurda sobre los posibles efectos secundarios de comer tu tostada.',
    '🏴‍☠️ En algún momento, explica un paso de la receta como lo haría un pirata.',
    '🗡️ Presenta uno de los ingredientes como si fuera un arma legendaria con nombre propio.',
    '👑 La preparación debe incluir una frase de un rey o una reina que pruebe tu tostada.',
    '🎵 Incluye una pequeña rima de dos versos dentro de la descripción de la preparación.'
  ];
  v_challenge text;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Debes iniciar sesión.'; END IF;
  IF length(trim(p_display_name)) NOT BETWEEN 1 AND 35 THEN RAISE EXCEPTION 'Nombre no válido.'; END IF;

  v_token := encode(extensions.gen_random_bytes(24), 'hex');
  v_challenge := v_challenges[1 + floor(random() * cardinality(v_challenges))::int];

  INSERT INTO public.toast_rooms(name, invite_hash, director_id, challenge)
  VALUES (
    coalesce(nullif(trim(p_room_name), ''), 'El Gran Maestro Tostadero'),
    extensions.digest(v_token, 'sha256'),
    auth.uid(),
    v_challenge
  )
  RETURNING id INTO v_room_id;

  INSERT INTO public.toast_room_members(room_id, user_id, display_name, role)
  VALUES (v_room_id, auth.uid(), trim(p_display_name), 'director');

  RETURN QUERY SELECT v_room_id, v_token;
END;
$function$;

-- La función de entrada usa explícitamente extensions.digest para evitar errores de search_path.
CREATE OR REPLACE FUNCTION public.join_toast_room(p_invite_token text, p_display_name text)
RETURNS TABLE(room_id uuid)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
#variable_conflict use_column
DECLARE
  v_room_id uuid;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Debes iniciar sesión.'; END IF;
  IF length(trim(p_display_name)) NOT BETWEEN 1 AND 35 THEN RAISE EXCEPTION 'Nombre no válido.'; END IF;

  SELECT r.id INTO v_room_id
  FROM public.toast_rooms AS r
  WHERE r.invite_hash = extensions.digest(p_invite_token, 'sha256')
    AND r.status <> 'finished';

  IF v_room_id IS NULL THEN
    RAISE EXCEPTION 'El enlace no es válido o el concurso ha terminado.';
  END IF;

  INSERT INTO public.toast_room_members(room_id, user_id, display_name, role)
  VALUES (v_room_id, auth.uid(), trim(p_display_name), 'player')
  ON CONFLICT (room_id, user_id)
  DO UPDATE SET display_name = EXCLUDED.display_name;

  RETURN QUERY SELECT v_room_id;
END;
$function$;

-- 3) Presentar tostadas en cualquier momento, sin fases ni desbloqueos.
CREATE OR REPLACE FUNCTION public.submit_toast_entry(
  p_room_id uuid,
  p_title text,
  p_base text,
  p_ingredients text[],
  p_recipe text DEFAULT '',
  p_pitch text DEFAULT ''
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_member_id uuid;
  v_id uuid;
BEGIN
  IF NOT public.is_toast_room_member(p_room_id) THEN
    RAISE EXCEPTION 'No perteneces a esta sala.';
  END IF;
  IF length(trim(p_title)) NOT BETWEEN 1 AND 50 THEN
    RAISE EXCEPTION 'El nombre debe tener entre 1 y 50 caracteres.';
  END IF;
  IF cardinality(p_ingredients) NOT BETWEEN 1 AND 5 THEN
    RAISE EXCEPTION 'Elige entre 1 y 5 ingredientes.';
  END IF;

  SELECT id INTO v_member_id
  FROM public.toast_room_members
  WHERE room_id = p_room_id AND user_id = auth.uid();

  INSERT INTO public.toast_entries(room_id, member_id, title, base, ingredients, recipe, pitch)
  VALUES (p_room_id, v_member_id, trim(p_title), trim(p_base), p_ingredients, coalesce(p_recipe, ''), '')
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$function$;

-- 4) Votar en cualquier momento. Se mantiene: 1-5, no votar la propia y un voto por tostada.
CREATE OR REPLACE FUNCTION public.cast_toast_vote(p_toast_id uuid, p_rating int)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_room_id uuid;
  v_owner uuid;
BEGIN
  SELECT t.room_id, m.user_id
  INTO v_room_id, v_owner
  FROM public.toast_entries AS t
  JOIN public.toast_room_members AS m ON m.id = t.member_id
  WHERE t.id = p_toast_id;

  IF v_room_id IS NULL THEN RAISE EXCEPTION 'Tostada no encontrada.'; END IF;
  IF NOT public.is_toast_room_member(v_room_id) THEN RAISE EXCEPTION 'No perteneces a esta sala.'; END IF;
  IF v_owner = auth.uid() THEN RAISE EXCEPTION 'No puedes votar tu propia tostada.'; END IF;
  IF p_rating NOT BETWEEN 1 AND 5 THEN RAISE EXCEPTION 'La valoración debe estar entre 1 y 5.'; END IF;

  INSERT INTO public.toast_votes(room_id, toast_id, voter_id, rating)
  VALUES (v_room_id, p_toast_id, auth.uid(), p_rating);
END;
$function$;

-- Permisos RPC para usuarios autenticados (incluidos los anónimos autenticados).
GRANT EXECUTE ON FUNCTION public.create_toast_room(text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.join_toast_room(text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.submit_toast_entry(uuid, text, text, text[], text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.cast_toast_vote(uuid, int) TO authenticated;

-- v3: eventos individuales por participante (incluido el creador).
-- Este bloque también está disponible por separado en supabase_update.sql.
ALTER TABLE public.toast_room_members ADD COLUMN IF NOT EXISTS challenge text;

CREATE OR REPLACE FUNCTION public.random_toast_challenge()
RETURNS text LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  v_challenges text[] := ARRAY[
    '🌋 En algún punto de la preparación debes mencionar un volcán y relacionarlo con tu tostada.',
    '🐉 En la preparación debe aparecer un dragón que tenga una opinión muy firme sobre uno de los ingredientes.',
    '📺 Describe al menos un paso como si estuvieras vendiendo la tostada en un anuncio de teletienda.',
    '👽 Uno de los ingredientes debe ser presentado como un misterioso descubrimiento extraterrestre.',
    '💥 Incluye un efecto de sonido escrito (¡PLOF!, ¡CHOF!, ¡BOING!) dentro de la preparación.',
    '⚠️ Añade una advertencia absurda sobre los posibles efectos secundarios de comer tu tostada.',
    '🏴‍☠️ En algún momento, explica un paso de la receta como lo haría un pirata.',
    '🗡️ Presenta uno de los ingredientes como si fuera un arma legendaria con nombre propio.',
    '👑 La preparación debe incluir una frase de un rey o una reina que pruebe tu tostada.',
    '🎵 Incluye una pequeña rima de dos versos dentro de la descripción de la preparación.'
  ];
BEGIN
  RETURN v_challenges[1 + floor(random() * cardinality(v_challenges))::int];
END;
$function$;
UPDATE public.toast_room_members SET challenge=public.random_toast_challenge() WHERE challenge IS NULL;

CREATE OR REPLACE FUNCTION public.create_toast_room(p_room_name text, p_display_name text)
RETURNS TABLE(room_id uuid, invite_token text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public','extensions'
AS $function$
DECLARE v_room_id uuid; v_token text;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Debes iniciar sesión.'; END IF;
  IF length(trim(p_display_name)) NOT BETWEEN 1 AND 35 THEN RAISE EXCEPTION 'Nombre no válido.'; END IF;
  v_token := encode(extensions.gen_random_bytes(24),'hex');
  INSERT INTO public.toast_rooms(name,invite_hash,director_id,challenge)
  VALUES(coalesce(nullif(trim(p_room_name),''),'El Gran Maestro Tostadero'),extensions.digest(v_token,'sha256'),auth.uid(),NULL)
  RETURNING id INTO v_room_id;
  INSERT INTO public.toast_room_members(room_id,user_id,display_name,role,challenge)
  VALUES(v_room_id,auth.uid(),trim(p_display_name),'director',public.random_toast_challenge());
  RETURN QUERY SELECT v_room_id,v_token;
END;
$function$;

CREATE OR REPLACE FUNCTION public.join_toast_room(p_invite_token text,p_display_name text)
RETURNS TABLE(room_id uuid)
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
#variable_conflict use_column
DECLARE v_room_id uuid;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Debes iniciar sesión.'; END IF;
  IF length(trim(p_display_name)) NOT BETWEEN 1 AND 35 THEN RAISE EXCEPTION 'Nombre no válido.'; END IF;
  SELECT r.id INTO v_room_id FROM public.toast_rooms AS r
  WHERE r.invite_hash=extensions.digest(p_invite_token,'sha256') AND r.status<>'finished';
  IF v_room_id IS NULL THEN RAISE EXCEPTION 'El enlace no es válido o el concurso ha terminado.'; END IF;
  INSERT INTO public.toast_room_members(room_id,user_id,display_name,role,challenge)
  VALUES(v_room_id,auth.uid(),trim(p_display_name),'player',public.random_toast_challenge())
  ON CONFLICT(room_id,user_id) DO UPDATE SET display_name=EXCLUDED.display_name;
  RETURN QUERY SELECT v_room_id;
END;
$function$;
GRANT EXECUTE ON FUNCTION public.create_toast_room(text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.join_toast_room(text,text) TO authenticated;
REVOKE ALL ON FUNCTION public.random_toast_challenge() FROM PUBLIC,anon,authenticated;
