# El Gran Maestro Tostadero — versión multijugador

## Arquitectura
- **GitHub Pages** sirve `index.html`, `styles.css`, `app.js` y `config.js`.
- **Supabase Auth anónimo** identifica a cada navegador sin registro tradicional.
- **Supabase Postgres + RLS** guarda salas, participantes, tostadas y votos.
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
1. Una persona crea el concurso y comparte el enlace. Esa persona figura como creador, pero no tiene que gestionar nada.
2. Al crear la sala se asigna automáticamente uno de 10 retos divertidos. Todos ven el mismo reto.
3. Los jugadores entran con el enlace y presentan su tostada cuando quieran.
4. Cada participante puede presentar una tostada por sala.
5. En cualquier momento, cada participante puede votar de 1 a 5 las tostadas de los demás. No puede votar la suya y solo puede votar una vez cada tostada.
6. La clasificación se ordena por la media de votos recibidos (1–5). No hay jurado ni puntuación del director.

### Actualizar una instalación existente
Si ya ejecutaste la versión anterior de `supabase.sql`, **no hace falta borrar tablas ni recrear el proyecto**. Ejecuta una sola vez el archivo `supabase_update.sql` en Supabase > SQL Editor. Esto asigna retos a salas antiguas que no tuvieran uno y actualiza las funciones para permitir presentación y votación libres.

## Seguridad y límites
- El frontend utiliza solo la clave anon/public; RLS protege los datos.
- Las escrituras se realizan mediante funciones RPC con comprobación de identidad y pertenencia a la sala.
- Un jugador no puede votar su propia tostada ni votar dos veces la misma tostada.
- El rol de director se asigna al usuario anónimo que crea la sala.
- El enlace es una invitación: cualquiera que lo tenga puede entrar. No lo publiques en abierto.
- El director debe conservar el navegador/sesión donde creó la sala. Si borra los datos del navegador, perderá esa identidad de director; esta primera versión no incorpora recuperación de director.
- Para pruebas, limita el acceso compartiendo el enlace solo con el grupo.

## Decisiones funcionales
- Participación: cada jugador desde su propio dispositivo.
- Evaluación: únicamente votos de participantes, de 1 a 5.
- Acceso: enlace privado con token aleatorio.
- Una tostada por usuario y sala.
- Los votos y la media de cada tostada son visibles para todos los participantes.

## Actualización v3: eventos individuales

Cada miembro de la sala recibe un evento aleatorio propio al crear la sala o entrar por primera vez. El evento aparece en su panel personal y también en la ficha pública de su tostada al presentarla.

Si ya tienes la aplicación desplegada, ejecuta `supabase_update.sql` en Supabase SQL Editor y después sustituye `index.html`, `app.js` y `styles.css` en GitHub Pages. Conserva tu `config.js` actual para mantener la URL y la clave de tu proyecto.
