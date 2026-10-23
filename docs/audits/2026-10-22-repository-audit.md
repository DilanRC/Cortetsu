# Cortetsu 2.0 — auditoría estática integral y QA de nube

**Fecha de revisión:** 22 de octubre de 2026 (Costa Rica; los runs de GitHub se registran en UTC).  
**Rama:** main. **Base exacta del inventario:** e2efd4175331ac17df7b9e04631c7c8321a2cf3d.  
**Alcance:** código y artefactos versionados, configuración, compilación, interfaces, pruebas e instalación simulada. **Excluye F10 y F11 físicas**: no se ha instalado, recargado o ejecutado el escritorio en el HP Victus.

## Método y alcance de la evidencia

- Se obtuvo por GitHub Actions un archivo de todo HEAD, lista de archivos versionados, revisión y checksum SHA-256. El checksum del archivo descargado se verificó antes de analizarlo. [Snapshot reproducible](https://github.com/DilanRC/Cortetsu/actions/runs/39893160924).
- Se recorrieron **1.529 archivos** y las referencias de **512 QML, 76 Rust, 51 Go, 33 JavaScript y 312 Python**. El inventario distingue módulos propios de la base compatible de procedencia y de los fixtures de pruebas.
- **268 QML** corresponden al árbol de primera parte fuera de base y pruebas; el resto comprende base, tests y componentes auxiliares. El constructor copia base, módulos, servicios y componentes a una generación aislada. Que un nombre no aparezca en una búsqueda global **no prueba** que el componente esté muerto: QML admite carga dinámica y referencias locales por importación.
- Se revisaron imports de archivos locales, nombres de componentes, duplicados exactos, puntos de entrada, bucles y procesos persistentes, controles accesibles, contratos de configuración, pruebas y acciones de instalación peligrosas.
- En la copia aislada pasaron **24 de 25** scripts de validación reproducidos, además de sintaxis Bash, compilación Python y gofmt. El script de carga Hyprland con Lua quedó **no ejecutable localmente por ausencia de Lua**, no por un resultado funcional negativo. Go test local quedó bloqueado por dependencias Go externas no disponibles sin conexión; los tests con race detector, vet y los crates Rust se comprueban mediante los runners de GitHub.
- Los checks CI verdes prueban el escenario sintético de Arch, QML y runtime nativo. No prueban tasas de CPU tras sesiones largas, HDMI/Wayland/NVIDIA, suspensión, monitores físicos ni latencias en gaming.

## Hallazgos confirmados y acciones

| Prioridad | Evidencia | Resultado |
| --- | --- | --- |
| P1 rendimiento | services/CortetsuSpectrum.qml arrancaba cava siempre por running=true, aunque visualiserEnabled es false por defecto y ServiceLoader lo instancia al inicio. | **Corregido**: el proceso sigue el ajuste y descarta muestras al detenerse; añadido fixture QML de reposo. Ahorro de CPU aún no cuantificado físicamente. |
| P1 comando | services/Storage.qml envolvía df en sh -c para redirigir stderr. | **Corregido**: argv estructurado directo para df, sin cambiar columnas de salida. |
| P1 interacción | modules/hardware/ProfileChoice.qml permitía emitir chosen por acción de accesibilidad mientras busy o disabled. | **Corregido**: una ruta de petición compartida para puntero, teclado y accesibilidad; test QML nuevo. |
| P2 código muerto | modules/display/TopologyDragOverlay.qml no tiene ningún consumidor activo y el Editor actual construye su topología en topologyCanvas. Solo lo menciona un inventario histórico. | **Eliminado** el archivo suelto. Se preservó el editor activo y se añadió aserción estática contra su reaparición accidental. |
| P1 gate incompleto | La regla antigua buscaba el texto literal sh -c solo en modules; omitía argumentos ["sh","-c"] en services y una invocación multilínea del portapapeles. | **Corregido**: escaneo de primera parte con cuatro excepciones heredadas enumeradas. Una invocación nueva o la desaparición de una excepción sin actualizar la prueba falla explícitamente. |
| P1 cobertura | El gate qmlformat analizaba Settings y controles, no el inventario completo. | **Ampliado** para analizar los 512 archivos QML mediante el Qt real del runner Arch. |
| P2 documentación | README presentaba versiones temporales de Hyprland y Quickshell como stack confirmado; FINAL-QA-REPORT.md con DO_NOT_MERGE pertenecía a septiembre. | **Corregido**: referencias históricas explícitas para evitar confundirlas con la versión instalada y la aceptación actual. |

## Deuda y riesgos que NO se han ocultado

### P0 — adopción indiscriminada de procesos

La acción **shell adopt** de scripts/cortetsu aún contiene **pkill -TERM -x qs**. Aunque exige invocación explícita, identifica procesos solamente por nombre y podría terminar un Quickshell ajeno a Cortetsu. **No se ejecutó**. Para corregirlo hay que identificar con garantías la instancia propia (PID, cgroup o unidad supervisora), verificar propiedad y procedencia y añadir fixtures de varias instancias. Evitar un pkill global no justifica sustituirlo por otro patrón de nombres igual de incierto. Su cambio se aísla del trabajo QML y no requiere ejecutar la prueba física ahora.

### P1 — cuatro invocaciones heredadas mediante shell desde QML

Quedan cuatro sitios conocidos y cubiertos por la allowlist de regresión:

1. services/Cpu.qml: glob de zonas térmicas. Debe migrar al sondeo Rust, conservando una identificación correcta del sensor (un índice arbitrario de thermal_zone no garantiza temperatura CPU).
2. services/CortetsuSpectrum.qml: comprobación opcional de cava. Ya es inactivo por defecto; eliminar el shell implica tratar explícitamente el caso en que cava no esté instalado.
3. services/ConnectivityBluetooth.qml: busctl Connect, stdout/stderr y código de salida BlueZ. Una sustitución requiere conservar la señal de éxito, fallo y timeout.
4. modules/clipboard/Content.qml: MIME de archivos de Clipse y flujo de bytes a wl-copy. La ruta usa argumento posicional citado, pero debe pasar a una API nativa que mantenga MIME y stdin antes de retirarla.

La política de arquitectura sigue siendo **no incorporar comandos nuevos de shell a QML**. Las cuatro excepciones son deuda registrada, no un aval de diseño.

### P1 — módulos grandes y responsabilidad mezclada

Los puntos de mayor tamaño en QML propio: **overview/Content.qml (1.101 líneas)**, **BottomHub.qml (882)**, **clipboard/Content.qml (871)**, **wallpaper/Content.qml (833)**, **CortetsuConfig.qml (754)**, **launcher/AppList.qml (741)** y **display/Editor.qml (713)**. La función de carga de CortetsuConfig ocupa aproximadamente **238 líneas**.

Plan de modularización recomendado: primero fixtures de datos y contratos funcionales; después separar normalización/validación de preferencias en módulos puros, lógica de selección y modelos de la vista, sin sustituir bindings observables ni aumentar procesos por monitor. La longitud por sí sola no demuestra un defecto ni autoriza reescribirlos de una sola vez.

### P2 — similitud y posibles falsos positivos

- **CortetsuMask.qml** y **base/components/effects/Mask.qml** son idénticos por bytes, pero pertenecen a fronteras de importación distintas; no se eliminan ni se inventa un symlink.
- Los nombres **CortetsuSurface**, **CortetsuText**, **Nexus** y otros aparecen en múltiples carpetas, pero sus propiedades y destinatarios difieren. Los adaptadores de iconos y estados son intencionales, no dos implementaciones activas.
- **StartupPageFixture.qml** parece sin consumidores en búsqueda de tipos, pero se usa por ruta en scripts/cortetsu test; **se conserva**.
- El import local **kblayout** de CortetsuKeyboardPopup se resuelve desde la base ensamblada en staging; no es una referencia rota del runtime.
- Una revisión histórica indica preferencias guardadas sin lectores activos, por compatibilidad con esquemas anteriores. No se borran datos del usuario solo por no hallar referencias en una vista.

### P2 — diseño y rendimiento por confirmar

Las pautas de Emil Kowalski e Impeccable se aplicaron como criterios de revisión: estados y affordances, foco/teclado, jerarquía, densidad adaptable, movimiento con intención, superficies controladas y prioridad de la identidad gráfica de Cortetsu. Se dispone de capturas sintéticas de Settings a 1368×900 y 880×620, con Material Symbols Rounded instalado y verificado en Arch. No hay evidencia física de todos los paneles y modos de escala, por lo que no se califican como aceptación visual F10.

Los timers de Weather (1 h), SysInfo (15 s) y observadores D-Bus/NM deben evaluarse por consumidores y necesidad antes de apagarlos: algunos mantienen estado útil con las superficies cerradas. El informe histórico también deja pendiente comprobar contraste de mensajes bermellón e incremento de consumo en sesiones muy largas. **No se inventaron mediciones ni se sacrificaron efectos sin datos.**

## Matriz de verificación y límites

| Gate | Situación |
| --- | --- |
| Inventario Git y SHA-256 de fuente | Verificado contra e2efd417 |
| Scripts locales de calidad, contratos, configuración, modelos y frontend | 24 PASS; 1 NO EJECUTADO por Lua ausente |
| Bash -n, compileall Python, gofmt | PASS |
| Test Go offline del entorno de análisis | NO EJECUTADO completo: faltan módulos externos en cache |
| Qt Quick Test / qmlformat / integración QML real | Ejecutados en GitHub Actions Arch por commit |
| Rust: fmt, Clippy, tests, release y paridad | Ejecutados por matrix CI en GitHub |
| Go: race, vet, contratos IPC y D-Bus | Ejecutados por CI en GitHub |
| Visual QML 880 y 1368 sintético | Evidencias GitHub; no sustituye hardware |
| F10 QA física y F11 release | **NO EJECUTADAS**, por decisión del usuario |

## Siguiente iteración segura

1. Sustituir pkill global en adopción por identificación supervisada de instancias y pruebas multinstancia, sin tocar procesos del portátil.
2. Crear un owner Rust dedicado a MIME/passthrough de clipboard y prueba de paridad de bytes.
3. Integrar medición de sensor térmico correcto con probes Rust, sin suponer thermal_zone0 ni NVIDIA activa.
4. Extraer módulos de CortetsuConfig y vistas grandes por dominio con test de identidad de binding y conservación de focus/scroll.
5. Mantener CI Qt/QML visual más checks a11y y pruebas de carga larga simulada; reservar multimonitor físico, GPU, HDMI y gaming para F10.

**Regla de cierre:** una auditoría de fuente completa no es una certificación de todos los comportamientos. Solo los cambios con evidencia de tests, rollback y aceptación explícita se promueven como verificados; ningún producto se instala en la sesión local durante esta revisión.
