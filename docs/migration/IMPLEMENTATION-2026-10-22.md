# Cortetsu 2.0 — integración nativa

Base de trabajo: `ce9523ea8a403ba106162cd8118b264897104db8`, rama `main`.
Autorización: completar F1b–F9 directamente en main, sin PR ni instalación en
el portátil. Las pruebas de hardware F10 y aceptación F11 se mantienen como
resultados independientes; no pueden inferirse de la compilación.

## Contrato de entrega

1. F1b: contrato estricto compartido, dispatch tipado, revisiones, idempotencia
   durable y respuestas verificadas. Nunca argv recibido por IPC.
2. F2: helpers inmutables dentro de SYSTEM schema 2, adopción respaldada de
   launchers, verificación y recuperación offline, rollback coordinado.
3. F3: DND con un único escritor Rust, journal, CAS, lectura posterior y
   recuperación ante interrupción; QML deja de escribir el archivo.
4. F4/F6: coordinador por sesión, observación y políticas con prioridad,
   caducidad, intervención manual, consentimiento por dominio y auditoría.
5. F5/F9: equivalentes nativos de todos los entrypoints Python del runtime y
   del instalador. Python histórico puede conservarse como oráculo de pruebas;
   ningún ejecutable instalado debe requerirlo.
6. F7: un cliente QML por shell, negociación, reconexión, estado explícito de
   error y ausencia de escrituras optimistas en estado autoritativo.
7. F8: activación explícita por dominio, validación del owner y desactivación
   recuperable. Instalar no implica habilitar automatizaciones de hardware.

## Decisiones de implementación

- Se conserva el formato plano de bundles existente:
  `helpers/builds/<id>/<ejecutable>` con `HELPERS.json`.
- Los launchers estables resuelven `helpers/current/<ejecutable>`; las
  dependencias de un helper se resuelven dentro de su misma generación.
- El coordinador no es necesario para usar comandos manuales ni recuperar
  generaciones desde TTY.
- Las fuentes Python se conservan hasta demostrar la paridad de cada bloque;
  eliminarlas del inventario sin reemplazar su comportamiento no cierra F9.

## Verificación requerida

Compilación y lint Rust/Go; pruebas de contrato compartidas; carreras de
notificaciones y dos sesiones IPC; instalación y rollback sobre HOME/XDG
temporales; fallos de integridad, permisos, interrupción y espacio; gate de
runtime sin Python; comprobación de CI sobre el commit publicado.

El informe de estado final debe distinguir lo implementado, lo probado en
nube y lo que requiere el equipo físico. Este documento no es una declaración
de finalización.

## Resultado integrado

La implementación resultante y sus comandos se documentan en
[NATIVE-RUNTIME.md](NATIVE-RUNTIME.md). La tabla de entrega se mantiene en
[STATUS-2026-10-22.md](STATUS-2026-10-22.md); los resultados de CI corresponden
al SHA publicado en GitHub Actions. El plan original se conserva para poder
contrastar la entrega con sus requisitos.
