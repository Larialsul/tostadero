-- ACTUALIZACIÓN v3: cada participante recibe su propio reto aleatorio.
-- Ejecutar UNA VEZ en Supabase > SQL Editor.

ALTER TABLE public.toast_room_members
  ADD COLUMN IF NOT EXISTS challenge text;

CREATE OR REPLACE FUNCTION public.random_toast_challenge()
RETURNS text
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path TO 'public'
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

-- Asignar un reto propio a cada miembro que ya esté en una sala.
UPDATE public.toast_room_members
SET challenge = public.random_toast_challenge()
WHERE challenge IS NULL;

-- Las salas nuevas: el creador recibe su propio reto.
CREATE OR REPLACE FUNCTION public.create_toast_room(p_room_name text, p_display_name text)
RETURNS TABLE(room_id uuid, invite_token text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_room_id uuid;
  v_token text;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Debes iniciar sesión.'; END IF;
  IF length(trim(p_display_name)) NOT BETWEEN 1 AND 35 THEN RAISE EXCEPTION 'Nombre no válido.'; END IF;

  v_token := encode(extensions.gen_random_bytes(24), 'hex');

  INSERT INTO public.toast_rooms(name, invite_hash, director_id, challenge)
  VALUES (
    coalesce(nullif(trim(p_room_name), ''), 'El Gran Maestro Tostadero'),
    extensions.digest(v_token, 'sha256'),
    auth.uid(),
    NULL
  )
  RETURNING id INTO v_room_id;

  INSERT INTO public.toast_room_members(room_id, user_id, display_name, role, challenge)
  VALUES (v_room_id, auth.uid(), trim(p_display_name), 'director', public.random_toast_challenge());

  RETURN QUERY SELECT v_room_id, v_token;
END;
$function$;

-- Cada nuevo participante recibe un reto al entrar. Si ya estaba en la sala,
-- se conserva su reto original y no se vuelve a sortear.
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

  INSERT INTO public.toast_room_members(room_id, user_id, display_name, role, challenge)
  VALUES (v_room_id, auth.uid(), trim(p_display_name), 'player', public.random_toast_challenge())
  ON CONFLICT (room_id, user_id)
  DO UPDATE SET display_name = EXCLUDED.display_name;

  RETURN QUERY SELECT v_room_id;
END;
$function$;

-- Permisos: los usuarios autenticados pueden ejecutar las RPC públicas.
GRANT EXECUTE ON FUNCTION public.create_toast_room(text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.join_toast_room(text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.submit_toast_entry(uuid, text, text, text[], text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.cast_toast_vote(uuid, int) TO authenticated;

-- La función auxiliar solo se usa desde las funciones SECURITY DEFINER.
REVOKE ALL ON FUNCTION public.random_toast_challenge() FROM PUBLIC, anon, authenticated;
