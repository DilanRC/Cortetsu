# Cortetsu protocol — módulos aislados, sin activación

Módulo Go `github.com/DilanRC/Cortetsu/cortetsu/protocol`.

- `execv1`: solicitudes/salidas de helpers `cortetsu.exec/1`, fixtures y fingerprints JCS.
- `ipcv1`: contrato `cortetsu.ipc/1`, sesiones, AF_UNIX **solo pruebas**, sin mutaciones.
- `policy`: motor `observe/simulate` con reglas declarativas, eventos secuenciados y campos permitidos.
- `shadow`: simulador de trazas offline y salida explicativa segura.
- `cmd/cortetsu-shadow`: CLI opt-in de simulación; **no es un daemon**.
- `observehypr` y `cmd/cortetsu-coordinator`: escucha de eventos Hyprland por AF_UNIX, solo lectura, campos de evento redactados, epoch nuevo y resnapshot tras reconexión. Se activa únicamente al invocar la CLI; sin unidad systemd ni escritor de recursos.

Probar:

```sh
go test -race ./...
go vet ./...
go run ./cmd/cortetsu-shadow -rules fixtures/rules.json < fixtures/trace.ndjson
```

Fases y gates: `docs/migration/F1b/README.md`. Este código NO está conectado a Quickshell ni a Rust y no reemplaza helpers de Python.


Probar observación voluntaria en entorno desechable (solo emite metadatos):

```sh
go run ./cmd/cortetsu-coordinator --session test --socket /ruta/socket2.sock
```

El modo por defecto usa `XDG_RUNTIME_DIR` y `HYPRLAND_INSTANCE_SIGNATURE`.
Nunca activar como servicio hasta validar identidad de sesión, ACL y energía.
