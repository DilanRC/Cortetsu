# cortetsu-rescue — recuperación Rust sin Quickshell ni Go

F2 (en desarrollo), **no se instala ni activa automáticamente**. CI compila el
binario en Linux y prueba generaciones reales de esquema 1 con datos de prueba.

Comandos:

- `cortetsu-rescue verify`: verifica `SYSTEM.json`, `BUILD.json` y hashes de los
  dotfiles, rechaza punteros fuera de los directorios administrados.
- `cortetsu-rescue status`: inspección de las generaciones.
- `cortetsu-rescue plan-rollback`: plan de rollback, **no cambia nada**.
- `cortetsu-rescue exec`: interpreta exclusivamente `system.verify` del contrato
  `cortetsu.exec/1` mediante stdin/stdout JSON, sin lanzar procesos ni mutar.
- `cortetsu-rescue recover`: revierte una transacción interrumpida usando un
  journal persistido antes de tocar los enlaces. Funciona sin checkout.
- `cortetsu-rescue rollback --acknowledge-unmanaged-helpers`: **opción peligrosa
  y explícita**: intercambia los punteros de generación bajo el mismo `flock`
  que usa `core/system.py`, crea journal duradero, verifica y compensa fallos.
  **No restaura los helpers `~/.local/bin`**, por lo que no debe usarse para
  revertir una actualización que haya modificado sus binarios, salvo después
  de restaurarlos desde un respaldo verificado y compatible.

Ninguno de los comandos modifica archivos de sesión, configuración del usuario,
servicios systemd, Hyprland, hardware ni la ejecución del shell. Los enlaces
cambian el estado de la instalación, pero el proceso del shell no se recarga
implícitamente.

## Riesgos que siguen bloqueando la adopción

1. Integrar helpers en generaciones con manifiestos y hashes (schema 2) y
   demostrar restore/upgrade/downgrade de formato antes de un cutover.
2. La CI prueba un `SIGKILL` durante el intercambio de punteros y `recover`
   independiente. Faltan fallos de disco lleno, permisos insuficientes y
   compatibilidad con generaciones que contienen helpers.
3. Probar con un sistema CachyOS real y una generación previa compatible; la CI
   solo hace pruebas aisladas.
4. Congelar una política de recuperación cuando la instancia anterior del shell
   sigue viva y puede usar helpers instalados distintos del nuevo generation.

No sustituir `scripts/cortetsu` ni `core/system.py` hasta superar esos gates.
