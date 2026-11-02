"""Minimal JSON-RPC client for agent-realm-mcp over stdio, shared by tests and acceptance."""
from __future__ import annotations

import json
import os
import select
import subprocess
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class Server:
    def __init__(self, config_home: str, profile: str, state_home: str | None = None,
                 command: list[str] | None = None, cwd: Path | None = None):
        env = {"PATH": "/usr/bin:/bin", "HOME": os.environ["HOME"], "XDG_CONFIG_HOME": config_home,
               "XDG_RUNTIME_DIR": os.environ.get("XDG_RUNTIME_DIR", "/tmp")}
        if state_home:  # tests isolate state; live acceptance uses the real realm state
            env.update(XDG_STATE_HOME=state_home, XDG_DATA_HOME=state_home)
        argv = command or [str(ROOT / "bin/agent-realm-mcp"), "--profile", profile]
        self.proc = subprocess.Popen(argv, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                     stderr=subprocess.PIPE, env=env, cwd=cwd)
        self.next_id = 0
        self.pending: dict[int, dict] = {}

    def send(self, message: dict) -> None:
        self.proc.stdin.write(json.dumps(message).encode() + b"\n")
        self.proc.stdin.flush()

    def read(self, timeout: float = 15) -> dict:
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            ready, _, _ = select.select([self.proc.stdout], [], [], 0.2)
            if ready:
                line = self.proc.stdout.readline()
                if not line:
                    raise EOFError(self.proc.stderr.read().decode())
                return json.loads(line)  # any non-JSON byte on stdout fails here
        raise TimeoutError("no response from MCP server")

    def submit(self, method: str, params: dict | None = None) -> int:
        self.next_id += 1
        self.send({"jsonrpc": "2.0", "id": self.next_id, "method": method, "params": params or {}})
        return self.next_id

    def wait_for(self, request_id: int, timeout: float = 60) -> dict:
        while request_id not in self.pending:
            message = self.read(timeout)
            if "id" in message:
                self.pending[message["id"]] = message
        return self.pending.pop(request_id)

    def request(self, method: str, params: dict | None = None, timeout: float = 60) -> dict:
        return self.wait_for(self.submit(method, params), timeout)

    def handshake(self, version: str = "2025-06-18") -> dict:
        result = self.request("initialize", {"protocolVersion": version, "capabilities": {},
                                             "clientInfo": {"name": "agent-realms-tests", "version": "1"}})
        self.send({"jsonrpc": "2.0", "method": "notifications/initialized"})
        return result

    def call(self, name: str, arguments: dict | None = None, timeout: float = 60) -> dict:
        return self.request("tools/call", {"name": name, "arguments": arguments or {}}, timeout)

    def close(self) -> str:
        self.proc.stdin.close()
        try:
            self.proc.wait(timeout=10)
        except subprocess.TimeoutExpired:
            self.proc.kill()
            self.proc.wait()
        err = self.proc.stderr.read().decode()
        self.proc.stdout.close()
        self.proc.stderr.close()
        return err
