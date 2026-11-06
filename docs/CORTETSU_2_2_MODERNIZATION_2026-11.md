# Cortetsu 2.2 — modernización y compatibilidad

Fecha: 2026-11-06. Base: `main` en `fe158a7cdd701ecd0b9be4c8a693f793e0f41299`.
El checkout real conserva sin cambios sus dos artefactos locales de
`.codebase-memory/`; la implementación se hizo en un clon Git aislado porque
el watcher global puede regenerarlos.

## Fase 1 — actualización y entorno

`sudo pacman -Syu` y después `yay -Syu` terminaron correctamente, sin
transacción parcial. Pacman actualizó 46 paquetes. Yay actualizó VS Code
1.144.0→1.145.1, PhpStorm/JRE 2026.2.4→2026.3 y Spotifast 0.16.0→0.17.1.

| Componente | Versión instalada al cierre | Resultado de comprobación |
|---|---|---|
| CachyOS kernel | 7.3.1-1 | El kernel activo coincide; no requiere reinicio para las pruebas de build. |
| CachyOS LTS | 6.18.55-2 | Módulo NVIDIA disponible para ambos kernels. |
| NVIDIA | 615.78.08-2 (userspace y módulo) | `modinfo` coincide con el kernel activo; `dkms status` no muestra NVIDIA pendiente. |
| Mesa | 26.2.6-1 | `pacman -Qkk` sin archivos alterados. |
| Hyprland | 0.57.1-1.1 | El proceso de la sesión sigue en 0.57.0; no se reinició. |
| Quickshell | 0.3.2, rev. `4f508be` | `qs --version` y compilación QML verificadas. |
| Qt | 6.12.0 | Base y declarative 6.12.0; suites QML pasan. |
| Rust / Go | 1.99.1 / 1.27.3 | fmt, Clippy, tests Go con race detector y vet pasan. |

El hook de recompilación detectó `linux-wallpaperengine-git`; se revisó su
PKGBUILD, se confirmó el upstream oficial `a0ddce5` (`r643`) frente a `r627`
instalado y se reconstruyó como usuario normal con `yay`. La receta usa ramas
de submódulos fijadas por el commit de upstream y declara `sha512sums=SKIP`;
esa limitación de verificación de fuentes queda registrada. El build e
instalación terminaron en `r643.a0ddce58-1` y la revisión posterior ya no lo
marca para recompilar.

El sistema dispone de snapshots Snapper root anteriores y posteriores a las
transacciones (473/474 pacman, 475/476 yay y 477/478 rebuild AUR). No se hizo
rollback. Los `.pacnew` revisados quedaron intactos; no había uno de escritorio
que necesitara reemplazar una configuración personal. `pacman -Qkk` no halló
alteraciones en kernel, NVIDIA, Mesa, Hyprland, Quickshell, Qt, Rust ni Go.
El portátil no se reinició y la sesión activa no se recargó.

## Fase 2 — compatibilidad e inventario

Se contrastaron las versiones instaladas con las fuentes oficiales:

- [Hyprland releases](https://github.com/hyprwm/Hyprland/releases): 0.57.1
  trae correcciones acumuladas para 0.57.0. El binario instalado se probó en
  compositores anidados; la sesión abierta sigue usando 0.57.0.
- [Quickshell changelog](https://quickshell.org/changelog/): 0.3.2 incluye
  compatibilidad con Qt 6.12 y correcciones para lifecycle, sockets,
  notificaciones, red y hotplug que son relevantes a Cortetsu.
- [Qt 6.12](https://doc.qt.io/qt-6.12/qt-releases.html) es la rama LTS
  instalada; los tests compilan el runtime generado, que aplana el staging de
  `cortetsu/base/`, no el árbol de fuentes como si fuera el producto final.
- [Rust release notes](https://doc.rust-lang.org/releases.html) y
  [Go release history](https://go.dev/doc/devel/release) se revisaron para
  1.99.1 y 1.27.3; Cortetsu conserva su contrato Go `1.22` y no necesita una
  API experimental nueva.

La verificación estática recorrió 311 archivos QML. Rust contiene ocho crates
activos y Go cubre el coordinador/IPC. Se revisaron los límites de superficie,
staging, procesos del runtime y contratos de instalación mediante sus tests
existentes, integración anidada y suite de regresiones. El inventario de
hallazgos priorizados es:

| Prioridad | Hallazgo y evidencia | Decisión |
|---|---|---|
| P1 | Copilot configuraba `SUPER + SHIFT + F23`, pero el keymap latam asigna `XF86Assistant` a ese nivel y el bind no disparaba (salida real del test: `[]`). | Corregido con bind por XKB keycode `SUPER + SHIFT + code:201`; prueba anidada verifica la acción y que F23/Shift+F23 solos no disparen. |
| P2 | `ConnectivityNmAdapter.busy` podía recibir un valor no booleano durante el montaje/destrucción del `Process`; el fixture retenía objetos hijos en el singleton y emitía asignaciones QML `[undefined]`. | Corregido con un ternario que siempre da `true/false`, liberación explícita del estado del fixture y test de observación que rechaza warnings y loops. |
| P2 | Tests de composición leían migradores Python que ya no viven en runtime, y una aserción mantenía el nombre previo del controlador de overlays. | Corregidos para consultar el oráculo congelado y el contrato actual. La prueba del adaptador demostró los fallos antes del arreglo. |
| P2 | El test histórico de GameMode prefijaba el runtime temporal hasta exceder los 108 bytes de `sun_path`; Hyprland rechazaba el socket antes de probar el servicio. | El runner acorta únicamente el directorio efímero de la copia desechable; el test completo pasa sin omitir assertions. |
| P2 | El primer cambio del test QML invocaba Python desde `scripts/cortetsu`, haciendo fallar el guard `build-native.sh` contra dependencias Python en el launcher distribuido. | El test se convirtió en un script Bash separado que conserva las verificaciones de marcador, asignaciones undefined y binding loops. El build de producción volvió a pasar sin debilitar el guard. |
| P3 | `qml-design-lint` informa 22 hallazgos entre 311 archivos (curvas, tamaños de targets y tokens literales). | Se registran como deuda visual preexistente; no justifican rediseñar superficies fuera del defecto. |

No se encontró evidencia segura para eliminar código activo o añadir una capa
de abstracción. No se borró funcionalidad ni se hizo formateo masivo. El estado
actual del inventario histórico de parches quedó aclarado en
[`architecture/patch-debt-status.md`](architecture/patch-debt-status.md).

## Fase 3 — correcciones

Las correcciones son pequeñas y con regresión asociada:

1. El bind de Copilot usa el keycode XKB 201, estable para el botón físico con
   Super+Shift bajo el tipo XKB de Cortetsu; el modelo Rust marca el bind por
   código como asignación de la tecla F23.
2. `busy` evalúa `worker ? worker.running : false`, así la propiedad booleana
   conserva un valor definido durante el montaje y el cierre de NetworkManager;
   la fixture elimina referencias antes de destruir sus objetos.
3. Las pruebas que preservan migraciones históricas siguen leyendo el
   baseline de solo test. El runner adapta la longitud de un directorio
   temporal y usa el contrato actual de la prueba Copilot dentro de la copia,
   sin alterar el snapshot ni el checkout real.
4. La prueba de equivalencia entre keybind helper Rust y Python y la prueba
   QML de observación se ejecutan contra las herramientas instaladas. La
   prueba QML se invoca con Bash y no agrega runtime Python al launcher nativo.

## Fase 4 — verificación y publicación

En la copia candidata, `scripts/cortetsu test --developer` pasó la suite
histórica completa; `CORTETSU_TEST_PINENTRY=/tmp/cortetsu-pinentry-fixed
./scripts/cortetsu test` pasó Rust, Go, Node, Qt Quick, las fixtures Quickshell,
la regresión QML de Wi-Fi, compilación integral de shell y realm. La prueba de
Wi-Fi se repitió directamente tras trasladarla de Python a Bash. Rust fmt y
Clippy con `-D warnings`, `go test -race ./...` y `go vet ./...` también
pasaron.

`scripts/build-native.sh` compiló los ocho bins Rust y cinco comandos Go hacia
`/tmp`; la primera ejecución detectó correctamente que el launcher había
adquirido una referencia a Python. Tras mover el test a Bash, build-native
pasó. `cortetsu/bin/build-runtime.sh --stage` generó y selló el runtime en un
`CORTETSU_DATA_ROOT` aislado; la compilación completa de Quickshell fue `OK`.
`scripts/verification/build-regressions.sh` pasó 32 entrypoints estables, cero
dependencias Python en el runtime, 49 oracles archivados y sus contratos QML
de policy/notificaciones.

Agent Realms en Hyprland headless pasó 155/155 checks y produjo 80 capturas en
cinco escenarios (tema oscuro/claro, transparencia off/on y movimiento
reducido); 150 líneas de warnings fueron clasificadas, cero quedaron sin
clasificar. La misma matriz corrió desde una extracción limpia de `fe158a7`:
155/155, 80 capturas y cero fallos. Las 80 parejas miden 1920×1080 y se
compararon píxel a píxel: la diferencia mayor fue 1,41% (Dashboard claro),
localizada en reloj/clima; Hardware varía hasta 0,42% por lecturas vivas. La
inspección visual de dashboard, ajustes, sesión y superficies conserva
geometría y paleta. La evidencia local de ambos recorridos está en:

- Candidata final: `/var/tmp/cortetsu22-modernization-final-realm-state/evidence/56cd031-20261106-024546`
- Baseline `fe158a7`: `/tmp/cortetsu22-modernization/baseline-clean-state/evidence/102be7f-20261106-023527`

No se hizo una comparación de rendimiento ni se afirma una mejora: los cambios
no pretenden optimizar CPU, PSS o latencia y el runtime real no se promovió ni
se recargó. La certificación física del botón Copilot, HDMI, suspensión,
multimonitor con hardware y adopción de Hyprland 0.57.1 requiere dispositivos
reales o reinicio; permanece pendiente.

## Publicación y workflows

`main` se publicó por push normal desde `fe158a7` en tres commits acotados:

| Commit | Cambio |
|---|---|
| `5e40885` | Booleano seguro en el ciclo de vida de Connectivity y prueba QML de regresión. |
| `6618883` | Bind Copilot por keycode XKB y comprobación con compositor anidado. |
| `d6238c9` | Oráculos congelados, runner limitado a cada test y documentación de deuda/modernización. |

En la verificación de publicación, `main` y `origin/main` coincidieron en
`d6238c9459579e58a54caf31e264f9a10f87b02d`; `git diff --check` pasó. Los cinco
workflows de ese HEAD terminaron con `success`:

| Workflow | Resultado |
|---|---|
| Cortetsu native owners | [success](https://github.com/DilanRC/Cortetsu/actions/runs/42190834235) |
| Cortetsu static validation | [success](https://github.com/DilanRC/Cortetsu/actions/runs/42190834439) |
| Cortetsu native end-to-end | [success](https://github.com/DilanRC/Cortetsu/actions/runs/42190834272) |
| Cortetsu QML and native installation | [success](https://github.com/DilanRC/Cortetsu/actions/runs/42190834359) |
| Cortetsu coordinator and IPC | [success](https://github.com/DilanRC/Cortetsu/actions/runs/42190834325) |

El primer intento de native owners quedó más de diez minutos en la instalación
de dependencias del runner. Se canceló esa ejecución atascada y se repitió el
workflow completo; el reintento terminó correctamente. Las pruebas locales
incluyen la instalación aislada, esquema 2 y rollback; no se instaló Cortetsu
en la sesión activa.
