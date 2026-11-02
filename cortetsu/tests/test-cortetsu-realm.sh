#!/usr/bin/env bash
# cortetsu realm without a realm: a stub agent-realm and scratch Git repositories.
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HELPER="$REPO/cortetsu/bin/cortetsu-realm"
TMP="$(mktemp -d)"
cleanup() {
    [[ -z "${QA_PID:-}" ]] || kill -KILL -- "-$QA_PID" 2>/dev/null || true
    chmod -R u+w "$TMP" 2>/dev/null || true
    rm -rf -- "$TMP"
}
trap cleanup EXIT
fails=0
ok() { printf 'PASS: %s\n' "$1"; }
bad() { printf 'FAIL: %s\n' "$1" >&2; fails=$((fails + 1)); }

# Stub Agent Realms. "live" is running; `status` without a name lists every
# realm, with $STUB_LIVE_WORKSPACE as the live one. `run` logs its arguments,
# prints the child's output and then the metadata object, as the real one
# does; with STUB_HANG=1 it never answers. Every call is logged.
mkdir -p "$TMP/realms/bin" "$TMP/realms/scripts"
cat > "$TMP/realms/bin/agent-realm" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$STUB_LOG"
case "$1" in
    status)
        if [[ -z "${2:-}" ]]; then printf '[{"alive": true, "workspace": "%s"}]\n' "${STUB_LIVE_WORKSPACE:-/w}"
        elif [[ "$2" == live ]]; then echo '{"alive": true, "workspace": "/w"}'
        else echo '{"alive": false, "workspace": "/w"}'; fi ;;
    run) [[ "${STUB_HANG:-0}" == 0 ]] || exec sleep 60
         shift 3; printf '{"surface": "child json"}\n{\n  "nested": 1\n}\n'
         printf '{\n  "command": [\n    "%s"\n  ],\n  "exit_code": 0\n}\n' "$1" ;;
    start|stop) ;;
    *) exit 1 ;;
esac
SH
printf '#!/bin/sh\n' > "$TMP/realms/scripts/realm-cortetsu.sh"
chmod +x "$TMP/realms/bin/agent-realm" "$TMP/realms/scripts/realm-cortetsu.sh"
# The QA fixtures only need to exist; a stub keeps the test free of ImageMagick.
mkdir -p "$TMP/bin"
printf '#!/bin/sh\nfor last; do :; done\n: > "$last"\n' > "$TMP/bin/magick"
chmod +x "$TMP/bin/magick"
export PATH="$TMP/bin:$PATH"
export CORTETSU_AGENT_REALMS="$TMP/realms" CORTETSU_REALM_CACHE="$TMP/cache" \
    CORTETSU_REALM_STATE="$TMP/state" STUB_LOG="$TMP/stub.log"
: > "$STUB_LOG"

out="$("$HELPER" exec --name live -- /usr/bin/qs 2>&1)"
expected=$'{"surface": "child json"}\n{\n  "nested": 1\n}'
[[ "$out" == "$expected" ]] && ok "the child's own JSON survives; only the metadata object is dropped" \
    || bad "strip_metadata: got [$out]"

: > "$STUB_LOG"
"$HELPER" ipc --name live drawers list >/dev/null
grep -qxF 'run live -- /usr/bin/timeout -k 2 30 /usr/bin/qs ipc --path /workspace/dist/runtime/shell.qml call drawers list' "$STUB_LOG" \
    && ok "an IPC call is bounded by a timeout that runs inside the realm" || bad "ipc timeout: $(cat "$STUB_LOG")"
: > "$STUB_LOG"
"$HELPER" exec --name live -- /usr/bin/true >/dev/null
grep -qxF 'run live -- /usr/bin/true' "$STUB_LOG" && ok "exec runs the user's command unbounded" || bad "exec: $(cat "$STUB_LOG")"

if out="$("$HELPER" ipc --name stopped drawers list 2>&1)"; then
    bad "ipc against a stopped realm succeeded"
else
    [[ "$out" == *"no está activo"* ]] && ok "a stopped realm is an error, not empty output" || bad "unclear error: $out"
fi

status=0; "$HELPER" nonsense >/dev/null 2>&1 || status=$?
((status == 64)) && ok "unknown action exits 64" || bad "unknown action exited $status"

# Agent Realms ships in this repository; the current directory does not matter.
out="$(cd / && env -u CORTETSU_AGENT_REALMS -u CORTETSU_REPO_ROOT bash -c \
    'source "$1"; require_realms; printf "%s\n%s\n" "$(repo_root)" "$AR"' _ "$HELPER")"
[[ "$out" == "$REPO"$'\n'"$REPO/agent-realms/bin/agent-realm" ]] \
    && ok "from /, the repository and its agent-realms/ are found without configuration" || bad "resolution: $out"
[[ -x "$REPO/agent-realms/bin/agent-realm" && -x "$REPO/agent-realms/scripts/realm-cortetsu.sh" ]] \
    && ok "agent-realms/ provides agent-realm and realm-cortetsu.sh" || bad "agent-realms/ incomplete"

# Warning triage of a QA round: known realm limitations are not failures,
# an error located in the build's own QML is.
# shellcheck source=/dev/null
source "$HELPER"
QA_REPORT="$TMP/report.tsv"; : > "$QA_REPORT"; QA_FAILS=0
KNOWN_WARNINGS="$TMP/known.ere"
grep -Ev '^(#|$)' "$REPO/cortetsu/tests/realm/known-warnings.txt" > "$KNOWN_WARNINGS"
in_realm_bounded() { cat "$FAKE_LOG"; }
FAKE_LOG="$TMP/known.log"
printf '%s\n' $'\e[33m  WARN\e[97m quickshell.service.upower\e[0m: Could not connect to DBus. UPower service will not work.' \
    '  WARN qt.qpa.wayland.textinput: virtual void QtWaylandClient::QWaylandTextInputv3::disableSurface(wl_surface*) Trying to disable 0x1 but 0x0 is focused' \
    '  WARN quickshell.qmlscanner: Ignoring unresolvable import "x"' '  INFO qml: fine' > "$FAKE_LOG"
qa_log live "$TMP" known
FAKE_LOG="$TMP/own.log"
printf '%s\n' '  WARN qml: @/workspace/.realm-data/runtime/generations/x/modules/Foo.qml[12:5]: TypeError: Cannot read property of null' \
    '  WARN something.new: an unknown message' > "$FAKE_LOG"
qa_log live "$TMP" own
[[ "$(cut -f1,2 "$QA_REPORT")" == $'PASS\tknown sin errores QML propios\nFAIL\town sin errores QML propios' && "$QA_FAILS" == 1 ]] \
    && ok "known realm limitations pass; the build's own QML error fails" || bad "triage: $(cat "$QA_REPORT")"
[[ ! -s "$TMP/known-unclassified.log" && "$(wc -l < "$TMP/own-unclassified.log")" == 2 \
    && "$(wc -l < "$TMP/known-warnings.log")" == 2 ]] \
    && ok "ANSI colours stripped, qmlscanner and INFO dropped, the rest left for review" || bad "triage logs"
unset -f in_realm_bounded

# Snapshot of a dirty checkout: untracked files are in it, ignored ones are
# not, and the user's index, branch and files are untouched.
git init -q "$TMP/repo"
cd "$TMP/repo"
git config user.email t@t; git config user.name t
printf 'ignored.txt\n' > .gitignore
echo base > tracked.txt
git add -A; git commit -qm base
echo changed > tracked.txt
echo new > untracked.txt
echo secret > ignored.txt
echo staged > staged.txt; git add staged.txt
index_before="$(git diff --cached --name-status)"; status_before="$(git status --porcelain)"
first="$(snapshot_commit "$TMP/repo")"
second="$(snapshot_commit "$TMP/repo")"
[[ "$first" == "$second" ]] && ok "an unchanged checkout gives the same snapshot commit" || bad "snapshot not stable"
[[ "$(git show "$first:tracked.txt")" == changed && "$(git show "$first:untracked.txt")" == new \
    && "$(git show "$first:staged.txt")" == staged ]] && ok "the snapshot holds modified, staged and untracked files" \
    || bad "snapshot content"
git cat-file -e "$first:ignored.txt" 2>/dev/null && bad "ignored file leaked into the snapshot" \
    || ok "ignored files stay out of the snapshot"
[[ "$(git rev-parse "$first^")" == "$(git rev-parse HEAD)" ]] && ok "the snapshot's parent is HEAD" || bad "parent"
[[ "$(git diff --cached --name-status)" == "$index_before" && "$(git status --porcelain)" == "$status_before" ]] \
    && ok "index and working tree untouched" || bad "the snapshot changed the user's index or files"
cd "$REPO"

# A Cortetsu-shaped scratch repository with two "built" worktrees in the cache.
CR="$TMP/cortetsu"
mkdir -p "$CR/scripts" "$CR/cortetsu/tests/realm"
: > "$CR/cortetsu.toml"; : > "$CR/scripts/build-native.sh"
cp "$REPO/cortetsu/tests/realm/known-warnings.txt" "$REPO/cortetsu/tests/realm/polkit-preview.qml" "$CR/cortetsu/tests/realm/"
git -C "$CR" init -q; git -C "$CR" -c user.email=t@t -c user.name=t commit -qm init --allow-empty
git -C "$CR" add -A; git -C "$CR" -c user.email=t@t -c user.name=t commit -qm files
sha="$(git -C "$CR" rev-parse HEAD)"
idle_wt="$TMP/cache/worktrees/$(git -C "$CR" rev-parse HEAD^)"
live_wt="$TMP/cache/worktrees/$sha"
git -C "$CR" worktree add -q --detach "$idle_wt" HEAD^
git -C "$CR" worktree add -q --detach "$live_wt" HEAD
mkdir -p "$live_wt/dist/native" "$live_wt/.realm-data/runtime/gen" "$live_wt/.realm-tools/qa-x"
: > "$live_wt/.realm-data/runtime/gen/shell.qml"; ln -s ../.realm-data/runtime/gen "$live_wt/dist/runtime"
printf '#!/bin/sh\n' > "$live_wt/dist/native/cortetsu-platform"; chmod +x "$live_wt/dist/native/cortetsu-platform"
mkdir -p "$TMP/state/evidence/old"; : > "$TMP/state/evidence/old/report.tsv"
chmod -R a-w "$idle_wt"  # sealed generations are read-only

# Ctrl+C or a kill in the middle of a QA run still stops the realm.
: > "$STUB_LOG"
STUB_HANG=1 CORTETSU_REPO_ROOT="$CR" setsid bash "$HELPER" qa "$sha" --name qa-int --out "$TMP/qa-int" \
    >"$TMP/qa-int.log" 2>&1 &
QA_PID=$!
for _ in $(seq 100); do grep -q '^run qa-int' "$STUB_LOG" && break; sleep 0.1; done
kill -TERM -- "-$QA_PID"
status=0; wait "$QA_PID" || status=$?
QA_PID=""
grep -qxF 'stop qa-int' "$STUB_LOG" && ((status == 143)) \
    && ok "a terminated QA run stops its realm and exits 143" || bad "qa cleanup: status=$status log=$(cat "$STUB_LOG")"
[[ -f "$TMP/qa-int/report.tsv" && -f "$live_wt/.realm-tools/qa-qa-int/walls/dark.png" ]] \
    && ok "the interrupted run keeps its evidence directory; fixtures are per realm" || bad "qa evidence or fixtures"

# gc: removes idle worktrees, even read-only ones; keeps a live realm's
# worktree and every evidence directory; a second run has nothing to do.
out="$(STUB_LIVE_WORKSPACE="$live_wt" CORTETSU_REPO_ROOT="$CR" "$HELPER" gc 2>&1)" || bad "gc exited non-zero"
[[ ! -e "$idle_wt" && -d "$live_wt" && -f "$TMP/state/evidence/old/report.tsv" && "$out" == *"lo usa un realm activo"* ]] \
    && ok "gc removes idle worktrees and keeps the live one and the evidence" || bad "gc: $out"
out="$(STUB_LIVE_WORKSPACE=/elsewhere CORTETSU_REPO_ROOT="$CR" "$HELPER" gc 2>&1)" || bad "gc exited non-zero"
out="$(STUB_LIVE_WORKSPACE=/elsewhere CORTETSU_REPO_ROOT="$CR" "$HELPER" gc 2>&1)" || bad "gc exited non-zero"
[[ ! -e "$live_wt" && -z "$(git -C "$CR" worktree list --porcelain | grep "$TMP/cache")" && "$out" != *ERROR* ]] \
    && ok "gc is idempotent and leaves no stale worktree entries" || bad "gc again: $out"

((fails == 0)) || exit 1
echo "PASS: cortetsu realm"
