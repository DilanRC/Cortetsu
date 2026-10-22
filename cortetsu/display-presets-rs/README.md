# Presets de pantalla — owner Rust

El bundle nativo publica `cortetsu-display-presets` mediante este ejecutable.
Conserva list/get/save/delete, usa el planner nativo con argv fijo y deadline,
y almacena JSON atómicamente bajo lock en HOME/XDG. Gestionar un preset no
aplica cambios de monitor; la aplicación pertenece al owner transaccional
hardware. La prueba de paridad compara el Python congelado y Rust en HOME
separados. La QA de monitores físicos sigue siendo un gate independiente.

Ver [runtime nativo](../../docs/migration/NATIVE-RUNTIME.md).
