# Display presets en Rust — F5, candidato aislado

CLI de prueba `cortetsu-display-presets-rs`; no reemplaza el Python instalado.
Conserva `list/get/save/delete`, consulta un planner de salida JSON mediante argv fijo,
y **nunca aplica cambios de monitores**. Almacena sus datos en el HOME/XDG del usuario,
con escritura atómica y bloqueo entre instancias Rust. El planner dispone de deadline
12 s; los tests comparan la salida con Python en dos HOME desechables.

Limitaciones: el helper Python original **no comparte** el nuevo flock; no hay
coordinación con QML/hypr-user ni QA física. No instalar ni renombrar la CLI
hasta pasar paridad de configuración real, revisión de errores, recovery
transaccional de helpers y pruebas de monitores AMD/NVIDIA.
