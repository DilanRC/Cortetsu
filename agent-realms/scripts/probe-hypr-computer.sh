#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
worktree_path="${1:-/tmp/cortetsu-ref-hypr-computer}"
expected_head="cd00962d7faf3a5059827994fbe746783695787f"
python_path="$worktree_path/.venv/bin/python"
realm_name="hypr-computer-probe-$$-$RANDOM"
data_home="${XDG_DATA_HOME:-$HOME/.local/share}"
realm_home="$data_home/cortetsu-agent-realms/$realm_name/home"
evidence_path="$repo_root/evidence/hypr-computer/live-probe"
start_attempted=0

cleanup() {
    local exit_status=$?
    local stop_status=0
    local artifact
    trap - EXIT
    set +e
    if [[ -d "$realm_home" ]]; then
        mkdir -p "$evidence_path"
        for artifact in \
            hypr-computer-before-input.png \
            hypr-computer-after-input.png \
            hypr-computer-after-update-dialog.png \
            hypr-computer-frame-a.png \
            hypr-computer-frame-b.png \
            hypr-computer-viewer-open.png \
            hypr-computer-viewer-late.png \
            hypr-computer-testapp.log \
            hypr-computer-clock.log \
            hypr-computer-viewer.log; do
            if [[ -f "$realm_home/$artifact" ]]; then
                cp -f "$realm_home/$artifact" "$evidence_path/$artifact"
            fi
        done
        if [[ -f "$realm_home/hypr-computer-probe-results.json" ]]; then
            cp -f "$realm_home/hypr-computer-probe-results.json" "$evidence_path/results.json"
        fi
        if [[ -f "$realm_home/hypr-computer-events.jsonl" ]]; then
            cp -f "$realm_home/hypr-computer-events.jsonl" "$evidence_path/events.jsonl"
        fi
    fi
    if [[ "$start_attempted" == 1 ]]; then
        PYTHONPATH="$repo_root/src" "$repo_root/bin/agent-realm" stop "$realm_name"
        stop_status=$?
        if [[ "$stop_status" != 0 ]]; then
            echo "ERROR: failed to stop ephemeral realm $realm_name (exit $stop_status)" >&2
        fi
    fi
    if [[ "$exit_status" == 0 && "$stop_status" != 0 ]]; then
        exit_status=1
    fi
    exit "$exit_status"
}
trap cleanup EXIT

if [[ "$(git -C "$worktree_path" rev-parse HEAD)" != "$expected_head" ]]; then
    echo "hypr-computer worktree must be at $expected_head" >&2
    exit 2
fi
if [[ ! -x "$python_path" ]]; then
    echo "missing reference venv: $python_path" >&2
    exit 2
fi

PYTHONPATH="$repo_root/src" "$repo_root/bin/agent-realm" doctor
start_attempted=1
PYTHONPATH="$repo_root/src" "$repo_root/bin/agent-realm" start "$realm_name" \
    --width 1280 --height 800 --workspace "$worktree_path" --readonly-workspace --ephemeral

cp "$repo_root/tests/fixtures/hypr_computer_probe.py" "$realm_home/hypr_computer_probe.py"
PYTHONPATH="$repo_root/src" "$repo_root/bin/agent-realm" run "$realm_name" -- \
    /workspace/.venv/bin/python /home/agent/hypr_computer_probe.py
