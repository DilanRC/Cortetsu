# Investigación de motores Orbital

Inspección estática del 16 de noviembre de 2026. No se ejecutaron motores,
pruebas, builds ni benchmarks. Las capacidades de fuente no certifican que
un wallpaper concreto funcione.

## Referencias conservadas

Clones fuera del producto, en `/home/dilan/Documentos/Referencias-Cortetsu/`.
Se conservaron sin modificar código ni inicializar sus submódulos:

| Referencia | Commit | Licencia y función |
| --- | --- | --- |
| [Almamu/linux-wallpaperengine](https://github.com/Almamu/linux-wallpaperengine) | `a0ddce586e9ff12e9d31ca6b103f6036cc1b68fe` | GPL-3.0-only; renderizador C++ OpenGL |
| [jagrat7/linux-wallpaper-engine](https://github.com/jagrat7/linux-wallpaper-engine) | `a874c9dbc1632654073e6289014ba09e6971b78a` | MIT; interfaz Electron y supervisor del motor Almamu |
| [Aromatic05/we-layerd](https://github.com/Aromatic05/we-layerd) | `7cf98158d0fa7af1440507242f5a06513286dfc6` | GPL-2.0-or-later; daemon Rust y presentación Wayland |

Además del clone principal Almamu existe `linux-wallpaperengine-installed`,
checkout del commit instalado obtenido de la caché Git AUR mediante clone
compartido; depende de los objetos de esa caché. Los clones `*-source` son
copias filtradas adicionales de jagrat7 y we-layerd. Ninguno se incorpora al repo.

## Instalación observada

`pacman -Qi/-Ql` confirma `linux-wallpaper-engine-ux 0.4.11-1` y
`linux-wallpaperengine-git r643.a0ddce58-1`. El primero depende de Electron39
y del segundo. `/usr/bin/linux-wallpaperengine` es un script propiedad del
paquete que cambia a `/opt/linux-wallpaperengine`, añade su `lib` a
`LD_LIBRARY_PATH` y ejecuta el ELF de ese directorio.

El ELF y su biblioteca usan RUNPATH `$ORIGIN:$ORIGIN/lib:$ORIGIN/lib64`.
`readelf -d` muestra OpenGL, GLEW 2.3, SDL2, FFmpeg (avcodec/avformat 63,
avutil 61, swresample 7), libmpv 2, PulseAudio, FreeType, Wayland client/EGL,
X11/Xrandr, D-Bus, kissfft y CEF. Se observaron los SONAME GLEW y avcodec
requeridos en `/usr/lib`; esto no sustituye una comprobación futura del loader.
El paquete incluye CEF, recursos Chromium y SwiftShader. No se modificaron
archivos pacman ni se crearon enlaces ABI.

## Contrato verificable de Almamu

La fuente exacta instalada en `Application/ApplicationContext.cpp` acepta:

- `--screen-root MONITOR --bg DIRECTORIO`, con opciones ordenadas por salida.
- `--layer background|bottom|top|overlay`; el predeterminado es **bottom**.
- `--fps` (30 predeterminado), `--hwdec auto|nvdec-copy|no` (auto).
- `--volume` (15 predeterminado), `--silent`, `--noautomute`.
- `--scaling stretch|fit|fill|default`, `--clamp clamp|border|repeat`.
- `--assets-dir`, `--set-property nombre=valor`, `--list-properties`.
- Desactivación de partículas, ratón y parallax; captura estática y pausa
  fullscreen configurable. No hay evidencia aquí de IPC para cambiar FPS vivo.

`Render/CWallpaper.cpp` construye CScene, CVideo y CWeb. Por tanto Web tiene
implementación CEF real: no debe etiquetarse todo Web como imposible. Escenas
y Web requieren clasificación conservadora por wallpaper; assets, shaders,
scripts y APIs pueden no coincidir con el motor Windows. Vídeo usa libmpv.
El modo `auto` no constituye una garantía de elección Radeon en GPU híbrida.

`WaylandOutputViewport.cpp` crea layer-shell con namespace
`linux-wallpaperengine`, región de entrada vacía, teclado desactivado y zona
exclusiva -1. La integración deberá pedir background explícitamente y separar
los widgets para que no queden ocultos por superficies del mismo nivel.

## Comparación y decisión

Jagrat7 es una referencia de catálogo, propiedades y supervisión por pantalla,
no otro renderizador. Su código `src/main/services/supervisor` identifica
procesos por argumentos; Cortetsu debe conservar handles propios y no copiar
una adopción de procesos externos.

we-layerd combina Rust con una biblioteca nativa cargada mediante `libloading`
en `crates/we-renderer-sys`. Su submódulo `wallpaper-engine-renderer` apunta a
`b2e01e421adc8fade6d1b4d124d5f7fec3463094`; no se descargó ni auditó ese
renderizador. Su arquitectura documenta workers por salida, DMA-BUF con
fallback SHM, frame callbacks, hotplug y escalado fraccional. Son referencias
útiles para interfaces futuras, no mejoras de compatibilidad demostradas aquí.
No se completó una evaluación comparativa de forks adicionales.

Recomendación: conservar Almamu como proceso sustituible y hacer catálogo,
persistencia y ownership en Rust dentro de Cortetsu. Reimplementar escenas
implicaría parsers de assets, shaders, efectos, scripting, audio y entrada;
reimplementar Web implicaría mantener igualmente un navegador. No hay evidencia
que justifique ese coste ni una reducción de compatibilidad. No se copia código
GPL ni se enlaza su biblioteca al runtime MIT en esta entrega. Una futura
redistribución del motor deberá cumplir su licencia y las de sus dependencias.

## Steam y sesión observados

`libraryfolders.vdf` declara únicamente `/home/dilan/.local/share/Steam`.
Existen `steamapps/workshop/content/431960` y
`steamapps/common/wallpaper_engine/assets`. No existe la raíz Flatpak habitual
en este HOME. Esto no excluye instalaciones personalizadas.

`hyprctl monitors -j` observa eDP-1 a 1920×1080/144.003 Hz y HDMI-A-1 a
1920×1080/60 Hz. `hyprctl layers -j` atribuye background de ambas pantallas
a `cortetsu-background`, PID 2585. No se observó un renderizador externo en
la consulta de procesos. No se alteró ownership ni se verificó el enlace
físico GPU-conector en esta investigación.

QA posterior deberá comprobar loader, escenas representativas, CEF, audio,
elección de GPU, superficies/widgets, hotplug y recuperación antes de habilitar
reproducción. No se afirma mejora de consumo o rendimiento.

## Decisiones tomadas para la reproducción (17 de noviembre de 2026)

Revisión estática adicional del checkout instalado. Tampoco se ejecutó nada.

- **Presentación**: Almamu tiene driver Wayland propio
  (`Render/Drivers/WaylandOpenGLDriver.cpp`, layer-shell por `wl_output`) y lo
  elige cuando `XDG_SESSION_TYPE=wayland` (`WallpaperApplication.cpp:667`). No
  hace falta un adaptador. we-layerd queda como referencia para un backend futuro
  con DMA-BUF.
- **Argumentos**: `--volume` y `--silent` forman un grupo mutuamente excluyente
  (`ApplicationContext.cpp:523-534`). `--scaling` y `--bg` se aplican a la
  última `--screen-root`. `--set-property` acepta `true/1` para bool, `stof`
  para slider y valores listados para combo (`Data/Model/Property.h`).
- **Biblioteca**: el wrapper `/usr/bin/linux-wallpaperengine` exporta
  `LD_LIBRARY_PATH=/opt/linux-wallpaperengine/lib` y entra en ese directorio. El
  supervisor reproduce ambas cosas sin pasar por un shell.
- **GPU**: en este equipo hay RTX 3050 (01:00.0) y Radeon HawkPoint2 (06:00.0).
  glvnd carga `10_nvidia.json` antes que `50_mesa.json`, así que fijar el vendor
  EGL a Mesa es la forma explícita de mantener el render en la integrada.
  `--hwdec auto` puede elegir NVDEC; la política integrada usa `no`.
- **Pantalla completa**: `WaylandFullScreenDetector.cpp` usa
  `zwlr_foreign_toplevel_management_v1`, disponible en Hyprland.
- **Web**: `WebBrowser/WebBrowserContext.cpp:87` fija `settings.no_sandbox = true`.
  Queda bloqueado hasta disponer de un backend aislado.
