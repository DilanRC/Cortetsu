# Orbital: integración Steam en construcción

Estado: **PARTIAL_NO_VERIFICADO**. Esta entrega incorpora descubrimiento y
consulta del catálogo; no completa la sustitución de una interfaz de Wallpaper
Engine. No se ejecutaron pruebas, builds, lints, benchmarks ni renderizadores.
La instalación activa no se modificó.

## Arquitectura y límites

El catálogo pertenece a `cortetsu-desktop-runtime`, mediante el dispatcher
`cortetsu-orbital`. QML consume JSON; no interpreta project.json ni ejecuta
comandos de Steam. El lanzador sigue el mecanismo de helpers del bundle.
No hay un daemon nuevo. Véase [contrato](ORBITAL_CONTRATO.md) y
[investigación de motores](ORBITAL_MOTORES.md).

Conservar el renderizador existente es la dirección elegida. Reimplementar
Scene supone reproducir formatos, shaders, efectos, scripts, audio e interacción;
una traducción a Rust no aporta por sí sola compatibilidad. Rust puede asumir
descubrimiento, validación, procesos y persistencia sin copiar el motor GPL.
Los backends deberán declarar capacidades por versión y por recurso, no por
una lista optimista de extensiones.

## Estado de las capacidades

| Área | Esta entrega | Trabajo pendiente |
| --- | --- | --- |
| Steam | Catálogo local sin requerir Steam abierto | Observación incremental de cambios |
| Imagen | Conserva el flujo estático existente | Selección independiente por salida |
| Scene, Video, Web | Metadatos y compatibilidad conservadora | Reproducción integrada |
| Monitores | Conserva apertura Orbital por pantalla | Ownership y restauración por monitor |
| Temas | Conserva pipeline oficial de imágenes | Extracción explícita desde preview animado |
| Procesos | No inicia ni adopta motores | Supervisor con handles, salidas y recuperación |
| Preferencias | No migra el estado estático | Favoritos, colecciones, perfiles y playlists |
| Energía | No cambia políticas de sesión | Eventos de batería, bloqueo, juego y suspensión |
| Integraciones | Biblioteca dentro de Orbital | Launcher, ajustes rápidos y búsqueda unificada |

La disponibilidad del motor no prueba que un wallpaper funcione. CEF en el
motor instalado permite estudiar Web; no equivale a compatibilidad universal.
La interfaz no debe ofrecer Aplicar para un elemento animado mientras no exista
la transacción correspondiente.

## Contrato previsto para reproducción

El supervisor deberá mantener por salida: selección deseada, proceso poseído,
selección confirmada, fallback y último error. Solo podrá señalizar hijos propios;
no `pkill` ni adopción de PID externos. Un lock de sesión evitará supervisores
duplicados. Detectar un propietario externo bloqueará la transición hasta una
decisión explícita del usuario. El fondo estático no debe retirarse antes de una
confirmación observable del nuevo renderizador. La mera creación del proceso
no constituye esa confirmación.

La política deberá consumir eventos del coordinador y de Hyprland: desconexión,
reconexión, resolución, escala y orientación; bloqueo, suspensión, inactividad,
batería, perfil energético, fullscreen y maximización. El usuario elegirá pausar,
limitar FPS o mantener activo. 30 FPS será el punto de partida previsto, no la
frecuencia del monitor. La selección de GPU no forzará NVIDIA. No se afirma
ninguna mejora de consumo: faltan mediciones por GPU, tipo y política.

El renderizador debe usar layer background; los widgets deben conservar su
orden visible e input. Antes de implementar el cambio hay que resolver la
coexistencia con `cortetsu-background`, hoy propietario de ambas salidas.

Persistencia futura: versión explícita, escritura atómica bajo lock, preferencias
por conector y recuperación ante rutas ausentes. No copiar contenido Workshop al
estado ni al repositorio. Las paletas Ink, Washi y Kurogane solo cambiarán por
elección explícita mediante el pipeline oficial. Lockscreen usará imagen estática.

## Instalación reversible posterior

No instalar esta etapa como integración de reproducción terminada. Tras completar
implementación y QA autorizado, construir un bundle con el helper registrado y
usar el procedimiento de generaciones de
[NATIVE-RUNTIME](../../migration/NATIVE-RUNTIME.md). Guardar la generación previa;
promover mediante el instalador canónico y adoptar QML mediante recarga explícita.
No editar archivos de pacman ni sustituir bibliotecas con symlinks.

Rollback: seleccionar la generación anterior con `cortetsu rollback` y verificar
con `cortetsu verify`, únicamente durante la futura instalación autorizada. Esta
etapa no crea procesos persistentes ni migra preferencias, por lo que no exige
deshacer estado nuevo del usuario. Las futuras migraciones deberán preservar el
estado previo para permitir volver a la generación anterior.

## Certificación pendiente

Consultar [QA posterior](QA_POSTERIOR.md). La revisión estática no certifica
compilación, navegación, accesibilidad, reproducción ni consumo. Las comprobaciones
visuales anti-slop quedan pendientes por la prohibición de ejecutar la interfaz.

Inventario QML: se añadió `modules/wallpaper/SteamLibrary.qml`. Regenerar el
inventario generado durante QA; no se ejecutó su generador en esta construcción.

Revisión de entrega: Thermos A detectó apertura bloqueante de archivos especiales,
corregida con apertura no bloqueante y validación del handle. Thermos B no detectó
bloqueantes estructurales; se limitaron avisos y títulos para preservar la galería.
Ambas revisiones fueron estáticas, con agentes separados. Anti-slop: reutilización
de tokens y ausencia de controles de reproducción ficticios revisadas en fuente;
layout, contraste, teclado y comportamiento quedan **NO VERIFICADOS**. No hay
un PASS de interacción ni de rendimiento.
