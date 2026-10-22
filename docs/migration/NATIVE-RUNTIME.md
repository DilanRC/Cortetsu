# Cortetsu 2.0 — contrato del runtime nativo

La migración F1b–F9 integra una plataforma Rust, helpers Rust, coordinación Go
y un cliente QML compartido. El instalador construye y adopta generaciones de
helpers junto al shell y los dotfiles. La instalación existente del usuario
sólo cambia cuando éste ejecuta el instalador; publicar este código no la cambia.

## Responsabilidades y compatibilidad

| Owner | Funciones |
| --- | --- |
| `cortetsu-platform` | CLI, dotfiles, system, GC, doctor, temas, importaciones, migraciones, composición, hashes y recuperación del instalador |
| `cortetsu-rescue` | Verificación independiente, rollback duradero y frontera tipada `cortetsu.exec/1` |
| `cortetsu-hardware-runtime` | Display plan/probe/persist/transaction/workspaces, hardware probe/power, GameMode, nvibrant y power-auto |
| `cortetsu-desktop-runtime` | Calendar, Pomodoro, emoji, startup, captura, grabación, schemes, wallpaper/color y secretos de NetworkManager |
| `cortetsu-notifications-rs` | Historial, dismiss/clear y estado DND transaccional |
| `cortetsu-display-presets-rs` | List/get/save/delete de presets; utiliza el planner nativo |
| `cortetsu-prune-applications-rs` | Diagnóstico y cuarentena de `.desktop` de usuario |
| `cortetsu-keybinds` | Editor y compilador de atajos, ya nativo antes de esta entrega |
| `cortetsu-coordinator` | Observación por sesión, evaluación de reglas, consentimiento y ejecución verificada |

Los 28 entrypoints de [`native-helpers.tsv`](../../cortetsu/native-helpers.tsv)
mantienen sus nombres. Sus pequeños launchers Bash eligen el ejecutable y el
dispatcher fijo dentro del mismo bundle; no ejecutan Python ni interpretan
código recibido por IPC. La CLI principal resuelve su plataforma junto a su
propio ejecutable. Los recursos de schemes y emoji quedan fijados a la misma
generación por `cortetsu-resource-root`.

Los originales se conservan como
[referencias con hashes](../../tests/reference/python-runtime/MANIFEST.json).
Las pruebas diferenciales comparan dos implementaciones y dos HOME separados;
no comparan un wrapper nativo contra el mismo binario.

## Construcción e instalación

Para compilar desde un checkout con Rust/Cargo y Go disponibles:

```sh
scripts/build-native.sh
```

Produce `dist/native`, sin modificar HOME ni lanzar servicios. Los lockfiles
Rust y Go quedan versionados. La instalación requiere las herramientas
declaradas en [`packages/arch.toml`](../../packages/arch.toml), incluido Qt Quick
Test para comprobar las superficies antes de promoverlas. El proyecto no
instala paquetes del sistema automáticamente.

Desde el checkout, o desde una CLI Cortetsu ya instalada:

```sh
scripts/cortetsu install
cortetsu verify
cortetsu status
```

`scripts/install-cortetsu.sh --native-bundle /ruta/absoluta/al/bundle` permite
usar un bundle previamente compilado. Se copia a un staging privado y se
verifica/sella; no se reutiliza un directorio mutable como generación activa.

La promoción no reinicia el shell. La adopción del nuevo QML sigue siendo una
acción explícita mediante `cortetsu shell reload`; ese flujo conserva las
protecciones existentes para las aplicaciones de escritorio abiertas. Los
servicios propios de wallpaper y power-auto se actualizan según su estado y
consentimiento; no se habilita power-auto por instalar el runtime nativo.

## Generaciones, journals y rollback

Cada `SYSTEM.json` nuevo usa schema 2 y registra shell, dotfiles y helpers,
sus manifiestos SHA-256 y los nombres de launchers administrados. El shell
sellado contiene un inventario `FILES.json`; los ejecutables, un
`HELPERS.json`. La verificación comprueba contenido, manifiestos, rutas,
enlaces activos y launchers. Los hashes detectan alteraciones, pero no son una
firma contra otro proceso con control completo de los archivos del mismo UID.

La instalación bloquea mutaciones concurrentes y respalda archivos y enlaces
antes de cambiarlos. Conserva un journal con fases PREPARED, ACTIVE,
COMMITTED o RECOVERED. Los respaldos tienen hashes y una identidad de sus
directorios padres: recuperación rechaza corrupción y padres redirigidos
antes de restaurar el primer archivo. Los errores normales disparan undo;
una interrupción abrupta se recupera en la siguiente instalación o con:

```sh
cortetsu recover
cortetsu verify
```

El rollback canónico restaura todas las capas y verifica la selección:

```sh
cortetsu generations
cortetsu rollback
cortetsu verify
```

`cortetsu-rescue verify`, `plan-rollback`, `rollback` y `recover` funcionan sin
QML, Go ni checkout. `rescue recover` corresponde a su journal de rollback;
para journals pendientes del instalador, dotfiles o promoción se utiliza
`cortetsu recover`. Un journal COMMITTED con drift posterior produce un error:
no deshace un commit duradero para ocultar una modificación posterior.

Al actualizar desde schema 1, el instalador conserva intacto el `SYSTEM.json`
original y crea un checkpoint schema 2 con sus helpers capturados. Su campo
`legacySourceSystem` preserva la procedencia y GC mantiene esa referencia.
Volver a dicho checkpoint puede recuperar helpers Python históricos. Por ello
no se desinstala Python del sistema. Las generaciones nativas posteriores
contienen exclusivamente owners nativos y scripts Bash.

La recolección sigue siendo explícita, mediante un plan identificado:
`cortetsu gc` no borra nada; `--apply --plan-id ...` vuelve a verificar el plan
bajo los locks de las capas. Se retienen current, previous, referencias y pins,
incluidos helpers. Ver detalles de recuperación y almacenamiento en
[`platform-rs/README.md`](../../cortetsu/platform-rs/README.md).

## Sesiones, contratos y automatización

QML mantiene un único bridge para el shell. El coordinador publica un socket
AF_UNIX y un descriptor privados por firma de sesión, con UID validado y epoch
representable exactamente en JavaScript. Un lock excluye dos coordinadores de
la misma sesión; otra sesión dispone de socket y epoch propios. Reconexiones,
desconexiones y pérdidas de owners invalidan el estado y la histéresis previa.

Los mensajes QML sólo solicitan snapshots, catálogo y explicaciones. La
activación usa una CLI local con argumentos estructurados y dominios
permitidos. La ejecución de recursos viaja por `cortetsu.exec/1`: operaciones
enumeradas, argumentos tipados, revisión esperada, UUID de idempotencia y
deadline. No existe una operación de shell o argv arbitrario. El parser
rechaza duplicados, mensajes incompletos, cero negativo y números no válidos.

Las señales Hyprland y D-Bus invalidan snapshots; los campos usados por reglas
se leen del owner. logind, UPower y NetworkManager usan D-Bus nativo. No se
conservan títulos de ventanas, nombres de redes ni secretos en las trazas.

**Instalar inicia la observación del coordinador cuando se carga el nuevo
shell; no concede permiso a ninguna automatización.** En Settings →
Automatización se puede activar cada dominio para la sesión actual. La CLI
equivalente permite inspección, activación, pausa y desactivación:

```sh
cortetsu-policy status
cortetsu-policy rules
cortetsu-policy enable notifications
cortetsu-policy override notifications 900
cortetsu-policy override notifications 0
cortetsu-policy disable notifications
```

Los dominios permitidos son `notifications`, `gamemode`, `power` y `display`.
La configuración privada pertenece a una sesión concreta. Una nueva sesión
no hereda su autoridad. Para retirar expresamente la autorización de una
sesión anterior, Settings ofrece revocación; la CLI exige su propietario
esperado: `cortetsu-policy revoke DOMAIN EXPECTED_OWNER`. Esta operación no
autoriza automáticamente a la sesión nueva y rechaza un propietario que haya
cambiado desde la lectura.

El catálogo incorporado contiene seis reglas: DND on/off y GameMode on/off
según fullscreen, ahorro con batería baja y balanced al conectar alimentación.
Usa TTL de cinco segundos, histéresis de 400 ms y cooldown de dos segundos.
`rules.json` privado permite un catálogo explícito de hasta 128 reglas; los
argumentos vuelven a pasar el contrato tipado. Display ofrece preview de un
perfil de un único monitor con guarda de rollback; no hay una regla de
pantallas activada en el catálogo predeterminado.

El runner consulta consentimiento y estado vigente antes de actuar. No vuelve
a aplicar un estado ya satisfecho. Persiste INTENT antes de la mutación y sólo
registra APPLIED después del readback del owner. Un resultado incierto conserva
evidencia y bloquea reejecución; cambiar el UUID no evita la recuperación
requerida del dominio. Una operación ya aceptada puede terminar durante una
revocación; las siguientes no obtienen consentimiento.

Los cambios manuales tienen prioridad. Los owners registran una pausa de una
hora por defecto; `CORTETSU_MANUAL_OVERRIDE_SECONDS` permite ajustar ese plazo
hasta 24 horas. La pausa explícita de Settings/CLI es adicional. Los receipts
de automatización tienen capacidad acotada y conservan tombstones durante su
horizonte; agotarlo devuelve un error, sin borrar evidencia para reejecutar.
La elección manual sigue disponible aun si el ledger automático está lleno.

## Notificaciones y secretos

DND tiene un único owner Rust. CLI, QML y Go comparten lock, revisión,
journal e historial de solicitudes. QML conserva el último estado confirmado
si falta el archivo y muestra indisponibilidad; no lo convierte en un falso
`off`. Estado corrupto o un symlink de historial produce error sin sobrescribir
su destino. `clear` conserva el comportamiento explícito de vaciar un historial
regular corrupto.

El historial sigue siendo un array compatible. QML envía un lote con IDs base,
entries y `clear_revision` al owner; el readback elimina bajas concurrentes y
preserva llegadas posteriores al lote. `notifs-clear.json` identifica un clear
incluso si el historial ya era `[]`, y su estado pending permite completar un
clear interrumpido sin resucitar entradas antiguas.

El helper de credenciales usa D-Bus nativo y recibe el secreto por stdin. QML
sólo activa un perfil después de comprobar la confirmación del guardado. Las
pruebas incluyen fallo, confirmación ausente y cancelación en cola/en ejecución.

## Evidencia y límites de las pruebas

| Gate | Evidencia ejecutable |
| --- | --- |
| Compilación/formato/lint | Ocho crates, Cargo.lock, Clippy estricto; Go build/vet/gofmt |
| Paridad | Notifications, presets, cuarentena, normalización/migraciones, contratos hardware; fixtures de paletas y cuantización |
| Durabilidad | CAS/replay, interrupción antes/después de commit, ledger lleno, journals corruptos, parents redirigidos y bundles alterados |
| Sesiones y owners | AF_UNIX y D-Bus privados, dos sesiones, owner loss/reconnect, cancelación real, `go test -race` |
| Política real | `scripts/verification/test-active-policy.py`: Go → Rust, consentimiento, override manual, no replay y crash/reconnect |
| Instalador real | `scripts/features/test-cortetsu-build.py`: dos generaciones, PATH sin Python, corrupción, rollback y undo tras fallo |
| QML real | Qt Quick Test y fixtures Quickshell de bridge, Settings, credenciales e historial/DND |
| F9 | Inventario Go `--require-native`, paquetes, launchers y hashes de originales |

GitHub Actions ejecuta Qt y Quickshell desde Arch para mantener su ABI común.
Las fixtures usan HOME/XDG privados; las pruebas del instalador sustituyen
`systemctl` para no gestionar los servicios del runner. Los contratos hardware
usan owners simulados o buses privados; no prueban físicamente una GPU o monitor.

La QA F10 de HDMI/hotplug, suspensión, consumo y gaming AMD/NVIDIA, y la
aceptación F11 de una release final, permanecen separadas. La integración de
código F1b–F9 no constituye una medición de rendimiento ni una instalación
verificada en el portátil.
