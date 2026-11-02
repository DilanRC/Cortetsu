#!/usr/bin/env python3
"""Live MCP acceptance against real realms, speaking JSON-RPC to bin/agent-realm-mcp.

Steps: start, launch a GTK app, screenshot, move, click, type, Enter, verify, close,
host focus unchanged; plus concurrency, cancellation, duplicate start, reconnection,
cross-realm isolation, backend failure with recovery and explicit stop.
Usage: scripts/acceptance-mcp.py [evidence-dir]   (needs scripts/setup-mcp-venv.sh)
"""
from __future__ import annotations

import base64
import json
import os
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tests"))
from mcp_wire import Server  # noqa: E402

AR = str(ROOT / "bin/agent-realm")
OUT = Path(sys.argv[1] if len(sys.argv) > 1 else ROOT / "evidence/mcp-acceptance")
OUT.mkdir(parents=True, exist_ok=True)
SUFFIX = str(os.getpid())
REALM, OTHER = f"mcpe2e-{SUFFIX}", f"mcpother-{SUFFIX}"
TEXT = "hola realm 42"
log_lines: list[str] = []


def log(message: str) -> None:
    print(message, flush=True)
    log_lines.append(message)


def fail(message: str) -> None:
    log(f"FAIL: {message}")
    raise SystemExit(1)


def host_focus() -> str:
    out = subprocess.run(["hyprctl", "activewindow", "-j"], capture_output=True, text=True).stdout
    data = json.loads(out or "{}")
    return json.dumps({"address": data.get("address"), "class": data.get("class")})


def tool(server: Server, name: str, arguments: dict | None = None, *, expect_error: bool = False,
         timeout: float = 60) -> dict:
    started = time.monotonic()
    reply = server.call(name, arguments, timeout)
    elapsed = (time.monotonic() - started) * 1000
    result = reply.get("result")
    if result is None:
        if expect_error:
            return {"protocol_error": reply.get("error"), "elapsed_ms": elapsed}
        fail(f"{name}: error de protocolo {reply.get('error')}")
    if bool(result.get("isError")) != expect_error:
        fail(f"{name} {arguments}: isError={result.get('isError')} {result.get('content')}")
    data = dict(result.get("structuredContent") or {})
    data["_elapsed_ms"] = round(elapsed, 1)
    data["_content"] = result.get("content", [])
    return data


def wait_window(server: Server, predicate, timeout: float = 20) -> dict:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        for window in tool(server, "window_list")["windows"]:
            if predicate(window):
                return window
        time.sleep(0.3)
    fail("la ventana esperada no apareció")
    raise AssertionError


def main() -> None:
    tmp = tempfile.TemporaryDirectory(prefix="agent-realm-mcp-e2e-")
    config = Path(tmp.name)
    (config / "cortetsu-agent-realms").mkdir(mode=0o700)
    profiles = {"schema": 1, "profiles": {
        "e2e": {"realm": REALM, "capabilities": ["observe", "control", "admin"], "lifecycle": "persistent",
                "start": {"workspace": str(ROOT / "tests/fixtures"), "readonly_workspace": True}},
        "other": {"realm": OTHER, "capabilities": ["observe"], "autostart": False}}}
    path = config / "cortetsu-agent-realms/profiles.json"
    path.write_text(json.dumps(profiles))
    path.chmod(0o600)
    servers: list[Server] = []

    def connect(profile: str = "e2e") -> Server:
        server = Server(str(config), profile)
        servers.append(server)
        server.handshake("2025-06-18")
        return server

    focus_before = host_focus()
    log(f"host focus before: {focus_before}")
    try:
        client = connect()
        log(f"tools: {len(client.request('tools/list')['result']['tools'])}")

        # 1. open the realm
        started = tool(client, "realm_start", timeout=90)
        log(f"1 realm_start: state={started['state']} reused={started['reused']} ({started['_elapsed_ms']} ms)")
        if started["state"] != "running":
            fail("el realm no quedó running")

        # duplicate start from a second client reuses the same realm
        twin = connect()
        again = tool(twin, "realm_start")
        log(f"  duplicate realm_start from second client: reused={again['reused']}")
        if not again["reused"]:
            fail("un segundo inicio creó otra instancia")
        twin.close()

        # 2. launch a GTK app (scoped, trackable)
        launched = tool(client, "app_launch", {"argv": ["/usr/bin/python3", "/workspace/gtk_entry_probe.py"]})
        app_id = launched["app_id"]
        log(f"2 app_launch: app_id={app_id}")
        window = wait_window(client, lambda w: (w.get("title") or "").startswith("entry probe"))
        log(f"  window: {window['address']} at={window['at']} size={window['size']}")

        # 3. screenshot, downscaled so coordinates must be transformed
        shot = tool(client, "screenshot", {"max_width": 640})
        image = next(c for c in shot["_content"] if c["type"] == "image")
        (OUT / "01-before-input.png").write_bytes(base64.b64decode(image["data"]))
        log(f"3 screenshot: frame={shot['frame_id']} original={shot['original_resolution']} "
            f"delivered={shot['delivered_resolution']} scale={shot['scale']} ({shot['_elapsed_ms']} ms)")
        if shot["delivered_resolution"][0] != 640:
            fail("la captura no se entregó al ancho pedido")

        # 4-5. move and click the entry, in frame pixels
        (wx, wy), (ww, wh) = window["at"], window["size"]
        rx, ry = shot["region"][0], shot["region"][1]
        fx, fy = (wx + ww / 2 - rx) * shot["scale"], (wy + wh / 2 - ry) * shot["scale"]
        moved = tool(client, "pointer", {"action": "move", "x": fx, "y": fy, "frame_id": shot["frame_id"]})
        log(f"4 pointer move: frame ({fx:.1f},{fy:.1f}) -> desktop {moved['desktop']} ({moved['_elapsed_ms']} ms)")
        clicked = tool(client, "pointer", {"action": "click", "x": fx, "y": fy, "frame_id": shot["frame_id"]})
        log(f"5 pointer click at desktop {clicked['desktop']}")
        expected = [int(wx + ww / 2), int(wy + wh / 2)]
        if abs(clicked["desktop"][0] - expected[0]) > 2 or abs(clicked["desktop"][1] - expected[1]) > 2:
            fail(f"mapeo de coordenadas incorrecto: {clicked['desktop']} != {expected}")
        out_of_frame = tool(client, "pointer", {"action": "click", "x": 700, "y": 10,
                                                "frame_id": shot["frame_id"]}, expect_error=True)
        log(f"  click outside frame refused: {out_of_frame['error']['code']}")

        # a still screen must not count as a change (let the first-focus animation finish)
        time.sleep(1.5)
        idle = tool(client, "wait_for_change", {"timeout_s": 1.5})
        log(f"  wait_for_change without input: {idle['changed']} after {idle['elapsed_s']} s")
        if idle["changed"]:
            fail("wait_for_change informó un cambio sin entrada")

        # 6. type while a concurrent wait_for_change watches the screen
        waiter = client.submit("tools/call", {"name": "wait_for_change", "arguments": {"timeout_s": 10}})
        time.sleep(1.0)
        typed = tool(client, "keyboard", {"action": "type", "value": TEXT})
        change = client.wait_for(waiter)["result"]["structuredContent"]
        log(f"6 keyboard type: {typed['typed']} chars ({typed['_elapsed_ms']} ms); "
            f"concurrent wait_for_change: {change}")
        if not change["changed"]:
            fail("wait_for_change no detectó el texto escrito")

        # 7. Enter
        tool(client, "keyboard", {"action": "key", "value": "Return"})
        log("7 keyboard key Return")

        # 8. verify through the app's own state
        done = wait_window(client, lambda w: (w.get("title") or "").startswith("submitted:"))
        result_file = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share")) / \
            "cortetsu-agent-realms" / REALM / "home/entry-result.txt"
        log(f"8 verify: title={done['title']!r} file={result_file.read_text()!r}")
        if done["title"] != f"submitted: {TEXT}" or result_file.read_text() != TEXT:
            fail("la app no recibió exactamente el texto")
        shot = tool(client, "screenshot", {"max_width": 640})
        image = next(c for c in shot["_content"] if c["type"] == "image")
        (OUT / "02-after-enter.png").write_bytes(base64.b64decode(image["data"]))
        stale = tool(client, "pointer", {"action": "click", "x": 1, "y": 1, "frame_id": "nope"},
                     expect_error=True)
        log(f"  unknown frame refused: {stale['error']['code']}")

        # cancellation: a long wait is cancelled and the session keeps serving
        waiter = client.submit("tools/call", {"name": "wait_for_change", "arguments": {"timeout_s": 30}})
        time.sleep(0.5)
        client.send({"jsonrpc": "2.0", "method": "notifications/cancelled",
                     "params": {"requestId": waiter, "reason": "acceptance"}})
        t0 = time.monotonic()
        status = tool(client, "realm_status")
        log(f"  cancelled wait_for_change; next call answered in {(time.monotonic() - t0) * 1000:.0f} ms "
            f"(state={status['state']})")
        if time.monotonic() - t0 > 5:
            fail("la cancelación dejó el servidor bloqueado")

        # 9. close the app
        closed = tool(client, "app_close", {"app_id": app_id})
        time.sleep(0.8)
        remaining = [w for w in tool(client, "window_list")["windows"] if (w.get("title") or "").startswith("submitted")]
        log(f"9 app_close: {closed['state']} ; probe windows left: {len(remaining)}")
        if remaining or tool(client, "app_list")["result"]:
            fail("la app siguió viva tras app_close")

        # simulated services through MCP
        applied = tool(client, "services_simulate", {"action": "apply", "scenario": "battery-low"}, timeout=60)
        tool(client, "services_simulate", {"action": "set", "assignments": ["upower.battery.percentage=50"]})
        services = tool(client, "services_status")
        log(f"  services_simulate apply battery-low -> {applied['scenario']}; after set: "
            f"battery {services['state']['upower']['battery']['percentage']} %, audio running "
            f"{services['audio_live']['running']}")
        if services["state"]["upower"]["battery"]["percentage"] != 50.0:
            fail("services_simulate set no se aplicó")
        tool(client, "services_simulate", {"action": "stop"})

        # cross-realm: another realm's windows are invisible to this client
        subprocess.run([AR, "start", "--ephemeral", OTHER], check=True, capture_output=True)
        subprocess.run([AR, "run", "--detach", "--compositor-child", OTHER, "--", "kitty", "--title",
                        "foreign-window"], check=True, capture_output=True)
        time.sleep(2)
        titles = [w.get("title") for w in tool(client, "window_list")["windows"]]
        log(f"  cross-realm: e2e client sees {titles}")
        if "foreign-window" in titles:
            fail("un cliente vio ventanas de otro realm")
        viewer = connect("other")
        forbidden = viewer.call("pointer", {"action": "click", "x": 1, "y": 1})
        log(f"  observe-only client of {OTHER}: pointer -> {forbidden.get('error', {}).get('message') or forbidden['result'].get('isError')}")
        viewer.close()

        # reconnection keeps the persistent realm
        client.close()
        client = connect()
        status = tool(client, "realm_status")
        log(f"  reconnect: state={status['state']} (persistent realm survived the disconnect)")
        if status["state"] != "running":
            fail("la reconexión perdió el realm")

        # backend failure: kill the compositor scope behind the server's back
        meta = json.loads(subprocess.run([AR, "status", REALM], capture_output=True, text=True).stdout)
        subprocess.run(["systemctl", "--user", "kill", "--signal=SIGKILL", meta["systemd_scope_unit"]],
                       check=True)
        time.sleep(1.5)
        broken = tool(client, "screenshot", expect_error=True)
        log(f"  backend killed: screenshot -> {broken['error']['code']}: {broken['error'].get('hint')}")
        recovered = tool(client, "realm_start", timeout=90)
        log(f"  realm_start after crash: state={recovered['state']} reused={recovered['reused']}")
        if recovered["state"] != "running":
            fail("no se recuperó tras el fallo del backend")

        # explicit stop is respected: no silent restart
        tool(client, "realm_stop")
        refused = tool(client, "window_list", expect_error=True)
        log(f"  after realm_stop: window_list -> {refused['error']['code']}")
        if refused["error"]["code"] != "realm_stopped":
            fail("tras realm_stop el realm se reinició solo")
    finally:
        for server in servers:
            if server.proc.poll() is None:
                server.close()
        for name in (REALM, OTHER):
            subprocess.run([AR, "stop", name], capture_output=True)
        tmp.cleanup()

    # 10. host focus and cleanup
    focus_after = host_focus()
    log(f"10 host focus after: {focus_after}")
    if focus_after != focus_before:
        fail("cambió el foco del anfitrión")
    left = subprocess.run(["systemctl", "--user", "list-units", f"agent-realm-*-{SUFFIX}-*", "--no-legend"],
                          capture_output=True, text=True).stdout.strip()
    servers_left = subprocess.run(["pgrep", "-f", "cortetsu_agent_realms.mcp_server"],
                                  capture_output=True, text=True).stdout.strip()
    log(f"scopes left: {len(left.splitlines()) if left else 0}; MCP servers left: {servers_left or 'none'}")
    if left:
        fail("quedaron scopes")
    log("PASS")


if __name__ == "__main__":
    try:
        main()
    finally:
        (OUT / "result.txt").write_text("\n".join(log_lines) + "\n")
