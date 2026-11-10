# El Gran Maestro Tostadero — versión multijugador

## Arquitectura
- **GitHub Pages** sirve `index.html`, `styles.css`, `app.js` y `config.js`.
- **Supabase Auth anónimo** identifica a cada navegador sin registro tradicional.
- **Supabase Postgres + RLS** guarda salas, participantes, tostadas, votos y notas del director.
- **Supabase Realtime** actualiza concurso y clasificación en los demás dispositivos.
- El enlace de invitación lleva un token aleatorio. En la base de datos solo se guarda su hash.

## Puesta en marcha

### 1. Configurar Supabase
1. Crea un proyecto Supabase.
2. En Authentication > Providers, habilita **Anonymous Sign-Ins**.
3. Abre SQL Editor y ejecuta `supabase.sql` completo.
4. En Database > Replication (o Publications), habilita Realtime para:
   - `toast_rooms`
   - `toast_room_members`
   - `toast_entries`
   - `toast_votes`
   - `toast_judge_scores`
5. En Project Settings > API, copia Project URL y la clave **anon/public**.

### 2. Configurar la web
1. Edita `config.js`.
2. Sustituye `https://TU-PROYECTO.supabase.co` y `TU_SUPABASE_ANON_PUBLIC_KEY`.
3. No pongas nunca la clave `service_role` en el frontend.

### 3. Publicar en GitHub Pages
1. Sube los cinco archivos (`index.html`, `styles.css`, `app.js`, `config.js`, `supabase.sql`) a tu repositorio.
2. En GitHub: Settings > Pages > Deploy from a branch.
3. Selecciona `main` y `/ (root)`.
4. Abre la URL de GitHub Pages.

## Cómo se juega
1. El director abre la web, escribe su nombre y pulsa Crear concurso.
2. Comparte el enlace generado.
3. Los jugadores abren el enlace, escriben su nombre y entran.
4. El director abre la fase de presentación.
5. Cada jugador presenta una tostada (una por participante).
6. El director abre votaciones.
7. Cada jugador puede votar una vez las tostadas ajenas (1 a 5).
8. El director asigna su puntuación (máximo 15).
9. La clasificación combina nota del director (0–15) + media de votos (0–5), máximo 20.
10. El director finaliza el concurso.

## Seguridad y límites
- El frontend utiliza solo la clave anon/public; RLS protege los datos.
- Las escrituras se realizan mediante funciones RPC con comprobación de identidad, sala y fase.
- Un jugador no puede votar su propia tostada ni votar dos veces la misma tostada.
- El rol de director se asigna al usuario anónimo que crea la sala.
- El enlace es una invitación: cualquiera que lo tenga puede entrar mientras la sala no esté finalizada. No lo publiques en abierto.
- El director debe conservar el navegador/sesión donde creó la sala. Si borra los datos del navegador, perderá esa identidad de director; esta primera versión no incorpora recuperación de director.
- Para pruebas, limita el acceso compartiendo el enlace solo con el grupo.

## Decisiones funcionales
- Participación: cada jugador desde su propio dispositivo.
- Jurado mixto: director (15 puntos) + media de votos de jugadores (5 puntos).
- Acceso: enlace privado con token aleatorio.
- Una tostada por usuario y sala.
- Los votos son visibles en la sala; las puntuaciones del director también.
