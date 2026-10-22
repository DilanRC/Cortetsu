#!/usr/bin/env python3
"""Cloud-only Go IPC -> Rust exec/1 readback integration (no active desktop)."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import signal
import socket
import subprocess
import tempfile
import time
from pathlib import Path


def create_legacy_generation(folder: Path) -> dict[str, Path]:
    data = folder / "data"
    runtime = folder / "shell-runtime"
    roots = {
        "shell": data / "builds" / "shell-one",
        "dotfiles": data / "dotfiles" / "builds" / "dots-one",
        "system": data / "system" / "builds" / "system-one",
    }
    for path in roots.values():
        path.mkdir(parents=True)
    runtime.mkdir()
    (roots["shell"] / "shell.qml").write_text("// fixture\n")
    (roots["shell"] / "BUILD_ID").write_text("shell-one\n")
    (roots["shell"] / "BUILD.json").write_text(json.dumps({"schema": 1}))
    payload = b"example = 42\n"
    target = roots["dotfiles"] / "home" / "example.toml"
    target.parent.mkdir()
    target.write_bytes(payload)
    digest = hashlib.sha256(b"F\x00" + payload).hexdigest()
    (roots["dotfiles"] / "MANIFEST.json").write_text(
        json.dumps({"schema": 1, "entries": [{"target": "example.toml", "sha256": digest}]})
    )
    (roots["system"] / "SYSTEM.json").write_text(json.dumps({
        "schema": 1, "shellGeneration": str(roots["shell"]),
        "dotfilesGeneration": str(roots["dotfiles"]), "repositoryRevision": "e2e-test"
    }))
    (runtime / "current").symlink_to(roots["shell"])
    (data / "dotfiles" / "current").symlink_to(roots["dotfiles"])
    (data / "system" / "current").symlink_to(roots["system"])
    return {"data": data, "runtime": runtime, **roots}


def send(writer, frame: dict) -> None:
    writer.write((json.dumps(frame, separators=(",", ":")) + "\n").encode())
    writer.flush()


def receive(reader) -> dict:
    raw = reader.readline(65537)
    assert raw.endswith(b"\n") and len(raw) <= 65537, "socket replied with truncated/oversized frame"
    return json.loads(raw)


def test(bridge: Path, rescue: Path) -> None:
    with tempfile.TemporaryDirectory(prefix="cortetsu-f1b-") as temp:
        root = Path(temp)
        generations = create_legacy_generation(root)
        xdg = root / "xdg-runtime"
        xdg.mkdir(mode=0o700)
        home = root / "home"
        home.mkdir()
        env = {**os.environ, "HOME": str(home), "XDG_RUNTIME_DIR": str(xdg),
               "CORTETSU_DATA_ROOT": str(generations["data"]),
               "CORTETSU_RUNTIME_ROOT": str(generations["runtime"])}
        check = subprocess.run([str(rescue), "verify"], capture_output=True, text=True, env=env, timeout=10)
        assert check.returncode == 0, check.stderr
        starting_files = sorted(p.relative_to(root).as_posix() for p in root.rglob("*") if p.is_file())
        child = subprocess.Popen([str(bridge), "--session", "test-run", "--rescue-binary", str(rescue)],
                                 stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, env=env)
        try:
            meta = xdg / "cortetsu" / "bridge-test-run.json"
            for _ in range(200):
                if meta.is_file() or child.poll() is not None:
                    break
                time.sleep(0.025)
            assert meta.is_file(), "the per-session Unix socket never started"
            desc = json.loads(meta.read_text())
            endpoint = Path(desc["socket"])
            assert endpoint.is_socket() and endpoint.stat().st_mode & 0o777 == 0o600
            with socket.socket(socket.AF_UNIX) as conn:
                conn.settimeout(6)
                conn.connect(str(endpoint))
                with conn.makefile("rwb", buffering=0) as pipe:
                    send(pipe, {"type": "hello", "protocol": "cortetsu.ipc",
                                "version": {"major": 1, "minor": 0}, "client": "test-client",
                                "client_version": "2.0", "session_id": "test-run",
                                "session_epoch": desc["session_epoch"],
                                "capabilities": ["system.verify"]})
                    accepted = receive(pipe)
                    assert accepted["type"] == "hello_ack" and "system.verify" in accepted["capabilities"]
                    request_id = "123e4567-e89b-12d3-a456-426614174001"
                    send(pipe, {"type": "request", "protocol": "cortetsu.ipc",
                                "version": {"major": 1, "minor": 0}, "id": request_id,
                                "op": "system.verify", "session_id": "test-run", "session_epoch": desc["session_epoch"],
                                "deadline_ms": 5000, "body": {}})
                    result = receive(pipe)
                    assert result["outcome"] == "read", result
                    assert result["body"]["revision"] == "e2e-test", result
                    assert result["id"] == request_id
                    # A mutation has no Rust executor and cannot reuse this read-only IPC channel.
                    send(pipe, {"type": "request", "protocol": "cortetsu.ipc",
                                "version": {"major": 1, "minor": 0}, "id": request_id,
                                "op": "display.profile.preview", "session_id": "test-run",
                                "session_epoch": desc["session_epoch"], "deadline_ms": 5000,
                                "body": {"monitor": "HDMI-A-1"}})
                    rejection = receive(pipe)
                    assert rejection["outcome"] == "rejected", rejection
        finally:
            child.send_signal(signal.SIGTERM)
            try:
                _, error = child.communicate(timeout=5)
            except subprocess.TimeoutExpired:
                child.kill()
                _, error = child.communicate(timeout=5)
            assert child.returncode == 0, error.decode(errors="replace")
        assert not meta.exists(), "metadata survived bridge shutdown"
        assert not endpoint.exists(), "socket survived bridge shutdown"
        after_files = sorted(p.relative_to(root).as_posix() for p in root.rglob("*") if p.is_file())
        assert starting_files == after_files, (starting_files, after_files)
        print("PASS: Go IPC and Rust system.verify (schema1), no mutations or leaked socket")


if __name__ == "__main__":
    args = argparse.ArgumentParser()
    args.add_argument("--bridge", required=True, type=Path)
    args.add_argument("--rescue", required=True, type=Path)
    opts = args.parse_args()
    test(opts.bridge.resolve(), opts.rescue.resolve())
