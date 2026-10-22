# F3 — Piloto reversible: estado DND local (sandbox)

El primer dominio de escritura seleccionado es **notification-status.json / DND**:
una única clave booleana con cambio reversible, no display, energía ni red.
Es el piloto más pequeño para validar el journal de Rust sin riesgo de apagar
pantallas o alterar el sistema. El control del estado pertenece actualmente
al servicio de notificaciones QML y al módulo CortetsuNotifications.

`cortetsu/notification-helper/src/pilot.rs` implementa únicamente en **tests**
la secuencia `lock -> preflight -> journal fsync -> atomic_write -> readback ->
commit`, así como recuperación después de interrupción y rechazo de restaurar
si otro escritor editó el mismo archivo. Prueba la conservación de claves ajenas
y rechaza JSON corrupto sin mutar. Usa HOME privado temporal; ningún comando
instalado puede activar este piloto.

**No autorizar cutover en la sesión real** hasta designar a un único propietario
para `Notifs.qml`/`CortetsuNotifications.qml`, añadir revision/CAS y confirmar
las transiciones desde la UI y el helper. El simple lock entre procesos Rust
no coordina `FileView.setText()` de QML. El gate F3 de producción permanece
**NOT_TESTED** hasta esa prueba y el rollback físico.
