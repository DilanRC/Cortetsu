# Cortetsu 2.3: personalización global y validación

Fecha: 8 de noviembre de 2026. Base: `13eae888dc98736a9f1bc098420e47e189e67c13`.
La instalación real y adopción suave se verificaron tras la validación aislada.
La comprobación de los cinco workflows del HEAD publicado se comunica con el
resultado final, enlazando sus ejecuciones en GitHub.

## Resultado funcional

Una paleta efectiva nativa alimenta Quickshell, Hyprland, Kitty, GTK y los
consumidores Qt/KDE compatibles. Los perfiles Ink/Washi/Kurogane conservan su
identidad, selección de esquema/variante/modo y preferencias por tema. La primera
selección de un tema usa sus colores propios. Los tokens de geometría, material
y fuentes comparten límites entre compilador, QML e importador.

Settings añade galería, vistas previas reversibles de tema/esquema, modo claro y
oscuro, origen manual/automático, cuatro integraciones independientes, ocho
controles de material/geometría, tres fuentes, perfiles portables y restauración
confirmada. La protección de aumentos de volumen y la duración del OSD tienen
consumidores reales. El Bottom Hub conserva sus cuatro islas y adapta bordes y
altura a los tokens. MiniSlider anima el progreso presentado y deriva el ancho.

La matriz de end-4 revisa 177 controles: 41 adaptados (34 A, 5 B, 2 C), 108 fuera
del producto/layout actual y 28 pendientes de justificación adicional. Estos
últimos no se consideran descartes definitivos. No se copió implementación QML
GPL. La referencia fijada y las razones individuales están en
[settings-end4-parity.json](settings-end4-parity.json).

## Verificación ejecutada

| Comprobación | Resultado y evidencia |
| --- | --- |
| Build nativo completo | PASS, ocho crates Rust y cinco binarios Go |
| Runtime staged, compilación Quickshell e integridad | PASS, generaciones temporales; nunca el árbol fuente |
| `build-regressions.sh` sobre staging | PASS, incluido lint estricto; [log](evidence/cortetsu-23-20261108/cortetsu-23-gates.log) |
| Rust fmt/Clippy, todos los targets de ocho crates | PASS; [log](evidence/cortetsu-23-20261108/cortetsu-23-rust-lint.log) |
| Suite nativa completa con pinentry aislado corregido | PASS; [log](evidence/cortetsu-23-20261108/cortetsu-23-full-patched.log) |
| Go test, vet y race | PASS |
| Settings: estado real, teclado, fallos, preferencias y Weston | PASS; [log](evidence/cortetsu-23-20261108/cortetsu-23-settings-final.log) |
| Controles nuevos | 38 comprobaciones de interacción/efecto y 17 de restauración en proceso nuevo |
| Proyecciones, independencia de fallos, respaldo, recuperación, perfiles | Ocho contratos PASS; [log](evidence/cortetsu-23-20261108/cortetsu-23-theme-sync.log) |
| Generación sellada con overlays mutables | PASS, escritura de overlays no cambia CSS sellado ni digest; [log](evidence/cortetsu-23-20261108/cortetsu-23-sealed.log) |
| Instalación oficial y rollback aislados | Dos instalaciones, rollback y regreso PASS; [log](evidence/cortetsu-23-20261108/cortetsu-23-isolated-rollback.log) |
| IPC y Agent Realms | PASS dentro de la suite nativa |

Una ejecución inicial de rescue falló por leer el archivo PID antes de que el
hijo escribiera el número. La prueba espera ahora un PID válido dentro del plazo,
sin cambiar la propiedad del proceso. Otra ejecución encontró transitoriamente
un lock de instalación ocupado en la prueba de rollback: 100 ejecuciones de esa
suite y la suite nativa completa posterior pasaron. No se cambió el protocolo de
locks para ocultar ese resultado.

## Inspección visual y anti-slop

Dirección conservada: tinta/materiales de Cortetsu, Washi claro y Kurogane,
Nexus lateral, tipografía existente y cuatro islas. La galería usa muestras para
comparar los tres temas; los indicadores de estado reflejan confirmación nativa.
La animación de progreso conserva continuidad y respeta movimiento reducido.

Se generaron 144 capturas de las ocho páginas con tres temas, ventana normal y
estrecha, escala 125 %, transparencia, movimiento reducido y Aura claro/oscuro.
El comando reproducible es `python3 scripts/features/test-cortetsu-settings-visual.py
--out /ruta/nueva`. Los PNG completos quedan en `/tmp/cortetsu-23-visual-final`
en esta ejecución. Las hojas revisadas se conservan en el repositorio:
[Ink](evidence/cortetsu-23-20261108/settings-ink.jpg),
[Washi](evidence/cortetsu-23-20261108/settings-washi.jpg),
[Kurogane](evidence/cortetsu-23-20261108/settings-kurogane.jpg) y
[condiciones](evidence/cortetsu-23-20261108/settings-conditions.jpg).
Se comparó la organización con las referencias end-4 fijadas de las ocho páginas;
la paleta y los materiales siguen siendo propios de Cortetsu.

Delivery gate: PASS en jerarquía, reflujo y elisión, controles con efecto real,
estados pendientes/error/no disponible, navegación por teclado y cierre/reapertura.
Contraste de roles: pruebas QML. Lectores de pantalla físicos: no comprobados;
no se afirma certificación de accesibilidad. El render offscreen no demuestra
compatibilidad universal de aplicaciones externas.

## Rendimiento

Mismo fixture temporal, backend nativo y configuración; tres rondas alternadas
sobre el árbol base archivado y el actual. [Datos](evidence/cortetsu-23-20261108/cortetsu-23-performance.json).
Medianas de apertura: 46 → 67 ms. Objetos iniciales: 876 → 1266. Veinte ciclos de
apertura, ocho páginas y cierre: 1781 → 2152 ms. La ampliación añade controles y
cuesta 21 ms de apertura en esta medición; no es una mejora de rendimiento.
Son medidas de desarrollo con otros procesos de pruebas activos, no un benchmark
exclusivo. Los tests confirman que cerrar Settings destruye sus páginas y que un
cambio de paleta conserva los objetos existentes. No se añadió daemon ni polling
residente al motor de temas; las escrituras iguales se omiten.

## Limitaciones externas verificadas

El `/usr/bin/pinentry-gnome3` instalado reproduce SIGSEGV en el sondeo de arranque.
La ejecución con ese binario queda FAIL, conservada en
[el log del fallo](evidence/cortetsu-23-20261108/system-pinentry-failure.log).
Se construyó pinentry 1.3.3 en `/tmp` con el parche existente y SHA-256 verificado
por `scripts/dependencies/build-pinentry.py`; la suite completa con ese binario
pasa, igual que la separación ya utilizada por CI. No se instaló globalmente ni
se cambiaron bibliotecas o symlinks ABI. Véase también [DEVELOPMENT_2_2.md](DEVELOPMENT_2_2.md).

Kitty y muchos consumidores GTK/Qt requieren recargar configuración o reabrir la
aplicación. Libadwaita recibe modo y el acento nominal compatible más próximo;
no se promete RGB arbitrario. La sesión usa qtengine: se cambia solo su ruta de
paleta, con respaldo y restauración. qt6ct permanece conservado y no se anuncia
como consumidor dinámico. Los cambios externos del usuario impiden restaurar
ciegamente una configuración ajena. Detalles en [THEMING.md](THEMING.md).

## Instalación y sesión real

Instalación oficial con bundle nativo validado: PASS. Generación activa
`20261108-144654-47910-914828456`; generación anterior conservada para rollback.
El runtime corresponde al commit de código `e3847552`; los commits siguientes
solo registran evidencia. `cortetsu verify` confirma current/previous, tema,
dotfiles y sistema. [Instalación](evidence/cortetsu-23-20261108/live-install.log),
[verificación](evidence/cortetsu-23-20261108/live-verify.log).

`cortetsu shell reload` adoptó el runtime sin cambiar el PID 2933 de Quickshell.
El proceso de power-auto continúa con PID 945. No se reinició Hyprland ni el
sistema. [Recarga](evidence/cortetsu-23-20261108/live-reload.log).

Ciclos reales de Washi, Kurogane e Ink: la selección nativa y la preferencia
observada por QML coinciden; Hyprland confirma `applied`, y Kitty/GTK/Qt declaran
`reopen` sin errores. Se exportó y restauró el perfil original. El foco,
fullscreen, modo, escala y frecuencia del monitor permanecieron iguales.
[Comprobación](evidence/cortetsu-23-20261108/live-themes.json).
No se forzó la reapertura de aplicaciones personales para aparentar aplicación
en vivo. Se evitó abrir ventanas de prueba sobre el navegador fullscreen.

Los respaldos privados previos están en
`~/.local/state/cortetsu/qa-23-before-20261108/`; los respaldos por destino del
motor permanecen en `theme-backups/`. La recuperación de generación usa
`cortetsu rollback`; la recuperación del perfil usa `cortetsu-scheme profile
import /ruta/visual-profile.json` y `sync-projections`. No se borró ninguna
generación. Los dos artefactos .codebase-memory conservaron su SHA-256 y no se
incluyen en los commits.

Las muestras de tres segundos de CPU/PSS están en
[antes](evidence/cortetsu-23-20261108/live-before.json) y
[después](evidence/cortetsu-23-20261108/live-after.json). Comparten PID pero una
recarga libera estado previo, por lo que no se atribuye una diferencia de PSS
exclusivamente a estos cambios. Son observaciones de sesión, no un umbral de
rendimiento garantizado.

Thermos: revisión independiente de corrección PASS y de mantenibilidad PASS.
Se resolvieron validación de perfiles, export de defaults/borde, merge parcial,
confirmación de errores, origen automático y fidelidad de fixtures visuales.
Las 144 capturas finales se regeneraron desde scheme.json completo producido
por el motor nativo, conservando modo y paleta efectiva. También pasan y se
revisaron capturas de Hub/popouts, avisos, Dashboard, lock, Hardware, calendario,
Wallpaper Orbital y selector de compartir pantalla:
[hoja visual](evidence/cortetsu-23-20261108/surfaces.jpg),
[pruebas adicionales](evidence/cortetsu-23-20261108/surface-tests.log).
