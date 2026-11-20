# Contextos

Estado: instalado el 2026-11-20 y cubierto por pruebas automáticas:
`cortetsu/tests/test-context-model.node.js` (planes, deshacer, validación,
estado, importación) y `scripts/features/test-cortetsu-contexts-runtime.py`
(el servicio contra el `CortetsuConfig` real, con dobles para No molestar,
modo juego, Orbital y el coordinador). Queda la comprobación en la sesión
real de lo asíncrono y del perfil de energía, que las pruebas no tocan a
propósito: ver
[QA_POSTERIOR.md](roadmap/cortetsu-3.0/QA_POSTERIOR.md#contextos-escenarios-sin-ejecutar).

Un contexto es un conjunto con nombre de ajustes que ya existen. Se activa y
se deshace de una vez. No es una autoridad nueva: cada ajuste se escribe a
través de su dueño actual.

| Ajuste | Dueño | Notas |
| --- | --- | --- |
| Tema, movimiento, transparencia, visualizador, avisos, Hub (vistas previas, miniaturas, separación entre islas), dashboard | `CortetsuConfig` (`preferences.json`) | El tema se aplica primero, porque `selectTheme` carga el movimiento y la transparencia propios de ese tema |
| No molestar | `Notifs.setDnd` → `cortetsu-notifications dnd` | Asíncrono |
| Modo juego | `GameMode.setEnabled` → `cortetsu-gamemode` | Asíncrono; sus fallos los avisa GameMode |
| Perfil de energía | `PowerProfiles.profile` (power-profiles-daemon) | «Rendimiento» se ignora si el daemon no lo ofrece. No toca frecuencias ni otro hardware |
| Pausar fondos animados | `CortetsuContexts.orbitalHold`, al que se enlaza `Orbital.hold` → `heartbeat` del supervisor | El supervisor pausa con el motivo `context` y reanuda al quitarlo. Orbital se crea al arrancar, así que la pausa vuelve con la sesión |

## Una sola autoridad

- Si el coordinador de automatización tiene activo el dominio
  `notifications`, `gamemode` o `power`, el contexto **no** toca ese ajuste y
  lo dice («La automatización conserva: …»). El ajuste aparece como omitido
  en Ajustes → Contextos.
- Al desactivar solo se restauran los ajustes que siguen con el valor que puso
  el contexto. Lo que el usuario cambió mientras tanto se queda como está.
- Cambiar de contexto desactiva el anterior antes de activar el siguiente; nunca
  hay dos instantáneas apiladas.

## Contextos incluidos

| Id | Cambia |
| --- | --- |
| `university` | Sin visualizador, sin aviso de lo que suena, avisos ocultos en pantalla completa, dashboard con clima y sin multimedia |
| `development` | Vistas previas y miniaturas de ventanas, métricas en el dashboard, sin aviso de lo que suena |
| `gaming` | Modo juego, No molestar, fondos animados en pausa, sin visualizador ni miniaturas, Hub compacto |
| `battery` | Perfil de ahorro, fondos animados en pausa, sin visualizador ni miniaturas, dashboard cada 5 s. El tema no cambia |

Los incluidos no se editan y Ajustes los muestra como una lista de valores;
«Duplicar» crea uno propio editable (32 como máximo), que sí ofrece cada
ajuste con «Sin cambio» y sus valores. Un contexto propio puede renombrarse, ajustar cada valor o dejarlo
«Sin cambio», eliminarse (con confirmación; si está activo se desactiva
antes), exportarse e importarse.

## Estado y formato

`$XDG_STATE_HOME/cortetsu/contexts.json`, `version: 1`:
`custom`, `active`, `applied`, `restore`, `skipped`. Cualquier clave fuera de
`ContextModel.KEYS` se descarta al leer o importar. Un archivo roto o de otra
versión deja los contextos desactivados con un error visible y no se
sobrescribe hasta que el usuario cambie algo.

Exportación: `{ "kind": "cortetsu-context", "version": 1, name, icon,
summary, settings }`. La exportación reemplaza el archivo si existe (la fila
pide confirmación). La importación añade el contexto sin activarlo.

## Superficies

- Ajustes → Aplicaciones y servicios → **Contextos**.
- Launcher: una acción por contexto («Contexto: Gaming»; «Salir de Gaming»
  cuando está activo).
- IPC: `cortetsu shell ipc contexts list|active|activate <id>|deactivate|toggle <id>`.

## Archivos

`cortetsu/services/ContextModel.js` (validación y planes, sin efectos),
`cortetsu/services/CortetsuContexts.qml` (aplicación, estado, IPC),
`cortetsu/modules/settings/sections/ContextsSection.qml`, registro en
`PageRegistry.qml` y `SettingsController.qml`, acciones en
`modules/launcher/services/Actions.qml`, y `hold` en
`services/Orbital.qml` y `desktop-runtime-rs/src/orbital_session.rs`.

## Límites conocidos

- Cambiar de tema dentro de un contexto guarda en ese tema los valores de
  movimiento y transparencia que tenía al salir (comportamiento existente de
  `selectTheme`). Al desactivar se vuelve al tema anterior con sus valores.
- DND y modo juego son asíncronos: si el helper falla, el contexto queda
  activo y el ajuste no cambió; al desactivar no se «restaura» nada para él.
- No hay activación automática por hora, red o aplicación: el coordinador de
  automatización sigue siendo el único que decide por reglas.

## Rollback

`git revert` de los commits de contextos. `contexts.json` es nuevo y una
versión anterior lo ignora; los ajustes que un contexto dejó en
`preferences.json` siguen siendo ajustes normales. Para volver al estado
previo, desactivar el contexto antes del rollback.
