# Agent Realms en Cortetsu

`cortetsu realm` construye cualquier commit de Cortetsu, o el checkout tal como
está, lejos del escritorio, y lo ejecuta en un *realm*: un Hyprland headless
propio con HOME, D-Bus de sesión, runtime Wayland, procesos y logs privados.
Sirve para probar un cambio de shell (superficies, foco, tema, transparencia)
sin instalarlo, para reproducir una regresión en un commit viejo y para que un
agente capture y opere el escritorio sin tocar la sesión real.

El runtime vive en este repositorio, en [`agent-realms/`](../agent-realms/README.md)
(Python estándar, sin dependencias obligatorias). La CLI está en
`cortetsu/bin/cortetsu-realm` y se llama desde `cortetsu realm`; las pruebas
corren en `cortetsu test` y en CI. No hace falta ningún checkout aparte.

## Qué nunca toca

Ningún subcomando de `cortetsu realm` lee ni escribe:

- las generaciones promovidas (`~/.local/share/cortetsu`,
  `~/.config/quickshell/cortetsu/current`);
- `~/.config/cortetsu` ni ningún archivo personal;
- el Hyprland, el Quickshell, el D-Bus o el teclado de la sesión;
- tu índice de Git, tu rama ni tus archivos (`build .` usa un índice temporal).

`down` y `relaunch` solo actúan sobre los scopes systemd y el Quickshell del
realm nombrado; no envían señales a procesos del anfitrión. `install` no se
ejecuta y ningún servicio de la sesión se reinicia.

## Requisitos

- CachyOS/Arch con Hyprland (Aquamarine), Weston con backend headless y renderer
  GL, y un render node AMD. No hace falta un monitor.
- `bubblewrap`, `dbus-daemon`, `systemd-run`, `grim`, `quickshell`, `jq`,
  Python ≥ 3.11 y namespaces de usuario sin privilegios.
- Para `build` y `qa`: la cadena de `cortetsu install` (cargo, go, Qt Quick
  Test). `qa` usa además `magick` (ImageMagick) para los fondos de prueba.

```fish
cortetsu realm doctor
```

comprueba todo lo anterior y compila bajo demanda los dos binarios pequeños del
runtime (cliente de entrada virtual y shim de Weston) en
`~/.cache/cortetsu-agent-realms`.

## Comandos

```fish
cortetsu realm build 8e0cf39        # worktree + nativos + generación sellada; imprime la ruta
cortetsu realm build .              # el checkout actual, con cambios y archivos nuevos
cortetsu realm up .                 # construye y lo ejecuta en el realm "cortetsu"
cortetsu realm ipc drawers toggle dashboard
cortetsu realm ipc bottomHub inspect | jq '.[0]'
cortetsu realm exec -- hyprctl -j layers
cortetsu realm shot ~/realm.png
cortetsu realm observe              # visor de solo lectura en el navegador
cortetsu realm relaunch             # reinicia solo el shell del realm, con su HOME tal cual
cortetsu realm down
cortetsu realm qa .                 # matriz visual y funcional; ver abajo
cortetsu realm gc                   # borra worktrees y builds; nunca la evidencia
```

`--name N` elige otro realm en todos los comandos, así que pueden convivir
varios (`up 8e0cf39 --name viejo` junto a `up . --name nuevo`); `up --size
2560x1440` cambia la salida headless. Los comandos funcionan desde cualquier
directorio: buscan el repositorio en `CORTETSU_REPO_ROOT`, en el clon donde
vive el helper y en `~/.local/share/cortetsu/repository` (el que apunta la
instalación).

| Variable | Por defecto | Uso |
|---|---|---|
| `CORTETSU_REPO_ROOT` | autodetectado | clon de Cortetsu |
| `CORTETSU_AGENT_REALMS` | `<repo>/agent-realms` | otro runtime, para desarrollarlo |
| `CORTETSU_REALM_CACHE` | `~/.cache/cortetsu/realm` | worktrees y `target/` de cargo |
| `CORTETSU_REALM_STATE` | `~/.local/state/cortetsu/realm` | evidencia de `qa` |
| `CORTETSU_REALM_TIMEOUT` | `30` | segundos por operación (IPC, captura) |

Códigos de salida: 0 éxito, 1 error o comprobación fallida, 64 acción
desconocida, 124 una operación agotó su tiempo, 130/143 interrumpido.

## Cómo aísla la construcción

- Cada revisión vive en `~/.cache/cortetsu/realm/worktrees/<sha>`
  (`git worktree` detached). Una segunda llamada con el mismo sha reutiliza el
  build; uno interrumpido se detecta (falta `shell.qml` o el binario) y se
  rehace.
- `.` es un commit de instantánea: un índice temporal recoge archivos
  modificados, preparados y nuevos (respetando `.gitignore`) y `commit-tree` lo
  cuelga de `HEAD`. El mismo árbol da el mismo sha. No crea ramas ni refs: el
  objeto queda suelto hasta que `git gc` lo recoja.
- `build-runtime.sh --stage` corre con `CORTETSU_DATA_ROOT` y
  `CORTETSU_RUNTIME_ROOT` dentro del worktree: las pruebas Qt Quick y la
  compilación en Quickshell son las de `cortetsu install`, pero la generación
  queda en `<worktree>/.realm-data`, nunca en la del escritorio.
- El realm monta el worktree en `/workspace` en solo lectura; `dist/runtime` es
  un enlace relativo a la generación, válido dentro y fuera.
- `agent-realms/scripts/realm-cortetsu.sh` enlaza los helpers nativos del
  worktree en el HOME del realm, sustituye `cortetsu-launch-persistent` por un
  adaptador sin systemd, cierra cualquier otro Quickshell *del realm* y espera
  a que el IPC del shell responda.

## `cortetsu realm qa`

Arranca un realm efímero (`qa`, o `--name`), ejecuta cinco rondas y lo detiene
al terminar, también si una comprobación falla, si hay un error o con Ctrl+C.
`--keep-realm` lo deja vivo para depurar.

| Ronda | Fondo | Transparencia | Movimiento reducido |
|---|---|---|---|
| 1 | oscuro | off | no |
| 2 | oscuro | on | no |
| 3 | claro | off | no |
| 4 | claro | on | no |
| 5 | oscuro | on | sí |

En cada ronda escribe `preferences.json` en el HOME del realm, reinicia el
shell (Cortetsu no vigila ese archivo) y aplica el fondo por la vía real
(`cortetsu-wallpaper set` → `cortetsu-wallpaper-select`). La primera ronda
empieza sin estado de fondo, como un HOME recién creado. Después comprueba por
IPC y captura:

- escritorio; Dashboard, Calendario, menú de sesión y launcher (abre y cierra);
- Ajustes rápidos por el mismo toggle que el atajo;
- popouts de red, audio y batería del BottomHub (abre el pedido y cierra);
- diálogo de autenticación: el `PolkitDialog` del build en la capa Overlay con
  el velo de `PolkitHost` y un AuthFlow simulado
  (`cortetsu/tests/realm/polkit-preview.qml`); el realm no tiene polkitd;
- el log del shell: ninguna línea de error QML/JS del propio build.

Cada IPC y cada captura tienen un plazo (`CORTETSU_REALM_TIMEOUT`); el plazo de
IPC corre *dentro* del realm, así que un comando colgado muere en el scope del
realm y no deja huérfanos. Una captura fallida es un FAIL del informe, no el fin
de la ejecución.

### Evidencia

```
~/.local/state/cortetsu/realm/evidence/<sha>-<fecha>/
  report.tsv                 una línea PASS/FAIL por comprobación, con esperado y obtenido
  summary.tsv                commit, comprobaciones, fallos, capturas, warnings
  <ronda>-<superficie>.png   50 capturas
  <ronda>-shell.log          log completo del shell en esa ronda
  <ronda>-warnings.log       sus líneas WARN/ERROR
  <ronda>-unclassified.log   las que no son limitaciones conocidas del realm
  known-warnings.ere         la lista usada para clasificar
```

`--out DIR` elige otro directorio. La evidencia no se borra nunca: ni `down`,
ni `gc`, ni un QA fallido o interrumpido la tocan. Para liberar espacio,
bórrala tú:

```fish
du -sh ~/.local/state/cortetsu/realm/evidence/*
rm -r ~/.local/state/cortetsu/realm/evidence/<sha>-<fecha>
```

### Warnings conocidos

[`cortetsu/tests/realm/known-warnings.txt`](../cortetsu/tests/realm/known-warnings.txt)
lista, con su motivo, lo que el realm no ofrece: servicios D-Bus de sistema
(UPower, power-profiles, NetworkManager, BlueZ), PipeWire, tema de iconos,
sesión logind para el agente polkit real, y el ruido de text-input-v3 de Qt.
Esas líneas no fallan. Una línea que nombra un `.qml`/`.js` del build, un
`TypeError`, `ReferenceError` o `Binding loop` falla la ronda. El resto queda en
`*-unclassified.log` para revisarlo; si es del entorno, añádelo a la lista con
su motivo.

## Añadir una prueba

- Lógica de la CLI (resolución, instantánea, limpieza, clasificación):
  `cortetsu/tests/test-cortetsu-realm.sh`, contra un `agent-realm` falso. Corre
  en `cortetsu test` y en CI sin realm.
- Una superficie en la matriz: una función `qa_*` en `cortetsu/bin/cortetsu-realm`
  que abra por IPC, espere con `wait_for`, registre con `check`, capture con
  `shot` y cierre; llámala desde `qa_round`. Cada `check` es una línea del
  informe.
- El runtime del realm: `agent-realms/tests/`
  (`PYTHONPATH=agent-realms/src python3 -m unittest discover -s agent-realms/tests`).

## Depurar un realm que falla

```fish
cortetsu realm qa . --keep-realm --name debug     # deja el realm vivo tras el informe
grep -v '^PASS' ~/.local/state/cortetsu/realm/evidence/*/report.tsv
cortetsu realm observe --name debug               # ver qué hay en pantalla
cortetsu realm exec --name debug -- qs log --path /workspace/dist/runtime/shell.qml
cortetsu realm exec --name debug -- hyprctl -j layers
agent-realms/bin/agent-realm logs debug --tail 200   # compositor y supervisor
cortetsu realm down --name debug
```

Si un realm quedó a medias (corte de luz, `kill -9`):
`agent-realms/bin/agent-realm recover <nombre>` limpia sus sockets y scopes
exactos; después `cortetsu realm down --name <nombre>`.

## Límites

Un PASS del realm valida el shell de Cortetsu en un Hyprland headless sobre la
iGPU AMD. No valida hardware:

- sin HDMI ni la ruta NVIDIA, sin s2idle/reanudación, sin GameMode ni juegos a
  pantalla completa, sin escalado fraccional físico;
- polkit es simulado: el error de contraseña real, el reintento con PAM y el
  bloqueo de `faillock` solo existen en la sesión real;
- el foco con dos monitores físicos y el consumo de la GPU se miden en el
  portátil.

Esas pruebas siguen en [`docs/PHYSICAL_QA.md`](PHYSICAL_QA.md), con criterios
PASS/FAIL y rollback. La comparación visual es humana: `qa` asegura que cada
superficie abre, cierra y queda capturada en cada combinación; no compara
píxeles.
