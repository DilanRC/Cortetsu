#!/usr/bin/env bash
# Lanza (o relanza) un build de Cortetsu dentro de un realm ya iniciado con
# --workspace WORKTREE: enlaza los helpers nativos del worktree en el HOME del
# realm, sustituye cortetsu-launch-persistent por el adaptador sin systemd y
# espera a que el IPC del shell responda.
# Uso: scripts/realm-cortetsu.sh REALM WORKTREE [RUNTIME]   (RUNTIME relativo al worktree, por defecto dist/runtime)
# Variables: CORTETSU_REALM_ENV="VAR=valor ..." añade entorno al shell (p. ej. un escenario de GPU).
set -euo pipefail
cd "$(dirname "$0")/.."
REALM=${1:?uso: realm-cortetsu.sh REALM WORKTREE [RUNTIME]}
WORKTREE=${2:?uso: realm-cortetsu.sh REALM WORKTREE [RUNTIME]}
RUNTIME=${3:-dist/runtime}
AR=bin/agent-realm
SHELL_QML=/workspace/$RUNTIME/shell.qml
[[ -f $WORKTREE/$RUNTIME/shell.qml ]] || { echo "falta $WORKTREE/$RUNTIME/shell.qml" >&2; exit 2; }
[[ -d $WORKTREE/dist/native ]] || { echo "falta $WORKTREE/dist/native (scripts/build-native.sh)" >&2; exit 2; }

# The workspace is mounted read-only, so the adapter is placed in the worktree
# from the host (the directory is meant to stay out of Git).
install -D -m 0755 scripts/realm-cortetsu-launch-persistent "$WORKTREE/.realm-tools/bin/cortetsu-launch-persistent"

# agent-realm run expands $VAR in its arguments, so the realm-side script uses none.
"$AR" run "$REALM" -- /bin/sh -c 'set -e; mkdir -p ~/.local/bin; ln -sf /workspace/dist/native/* ~/.local/bin/;
  ln -sf /workspace/.realm-tools/bin/cortetsu-launch-persistent ~/.local/bin/cortetsu-launch-persistent' >/dev/null

# One shell per realm: an instance of another build left running keeps its own
# layers, focus grabs and IPC, and silently skews every comparison.
for id in $("$AR" run "$REALM" -- /usr/bin/qs list --all 2>/dev/null | sed -n 's/^Instance \([A-Za-z0-9]*\):$/\1/p'); do
  "$AR" run "$REALM" -- /usr/bin/qs kill --id "$id" >/dev/null 2>&1 || true
done
# cortetsu-resource-root of the build prints the host path; inside the realm the
# sources live under /workspace.
# shellcheck disable=SC2086
"$AR" run --detach --compositor-child "$REALM" -- /usr/bin/env CORTETSU_RESOURCE_ROOT=/workspace/cortetsu \
  ${CORTETSU_REALM_ENV:-} /usr/bin/qs --path "$SHELL_QML" >/dev/null
for _ in $(seq 80); do
  reply=$("$AR" run "$REALM" -- /usr/bin/qs ipc --path "$SHELL_QML" call bottomHub isShown 2>/dev/null || true)
  if grep -qxE 'true|false' <<<"$reply"; then
    echo "Cortetsu responde en $REALM ($SHELL_QML)"
    exit 0
  fi
  sleep 0.5
done
echo "Cortetsu no respondió por IPC en $REALM" >&2
exit 1
