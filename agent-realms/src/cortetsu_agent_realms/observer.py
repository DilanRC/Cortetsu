"""Authenticated, read-only observer for one realm.

Layout (host-only, never mounted into a realm):

    $XDG_RUNTIME_DIR/cortetsu-agent-realms/observers/<realm>/   0700
        control.sock   0600  Unix control channel, peer UID checked
        .lock                one observer per realm
        launch-*.html  0600  one-use browser launch file, removed on use/expiry

The browser gateway listens on 127.0.0.1, serves fixed in-memory routes only
and grants the `observe` capability, never `control` or `admin`.
"""
from __future__ import annotations

import argparse
import fcntl
import json
import os
import shutil
import signal
import socket
import socketserver
import stat
import struct
import subprocess
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any, Callable

from .auth import AuthError, Capability, CredentialStore
from .paths import RealmError, host_runtime_root, paths_for, repo_root, validate_name

CONTROL_NAME = "control.sock"
MAX_CONTROL_BYTES = 4096
MAX_BODY_BYTES = 1024

INDEX_HTML = """<!doctype html><html lang=es><meta charset=utf-8>
<meta name=viewport content='width=device-width,initial-scale=1'><meta name=referrer content=no-referrer>
<title>Agent Realm observer</title>
<style>body{margin:0;background:#111;color:#eee;font:14px system-ui,sans-serif}header{padding:.5rem}
img{display:block;max-width:100vw;max-height:92vh;margin:auto;object-fit:contain}</style>
<header id=s role=status>Autorizando…</header><img id=i alt='Captura del escritorio virtual'>
<script src=/app.js></script></html>
""".encode()

# The session token stays in this closure: never in storage, cookies or URLs.
APP_JS = b"""(()=>{'use strict';
const st=document.getElementById('s'),img=document.getElementById('i');let token=null,last=null;
const say=t=>{st.textContent=t};
async function login(){const m=location.hash.match(/^#t=([A-Za-z0-9_-]{20,128})$/);
history.replaceState(null,'',location.pathname);
if(!m){say('Sin autorizaci\\u00f3n. Ejecuta: agent-realm observe <realm> --open');return false}
const r=await fetch('/api/session',{method:'POST',cache:'no-store',headers:{'Content-Type':'application/json'},
body:JSON.stringify({ticket:m[1]})});if(!r.ok){say('Ticket rechazado o caducado');return false}
token=(await r.json()).token;return true}
async function tick(){let wait=1000;try{const h={Authorization:'Bearer '+token};
const s=await fetch('/api/state',{headers:h,cache:'no-store'});
if(s.status===401||s.status===403){say('Acceso revocado o caducado');return}
const j=await s.json();wait=j.interval_ms||1000;
if(!j.online){say('Realm '+j.name+' sin captura: '+(j.error||'esperando'))}else{
const f=await fetch('/api/frame',{headers:h,cache:'no-store'});
if(f.status===401||f.status===403){say('Acceso revocado o caducado');return}
if(f.ok){const u=URL.createObjectURL(await f.blob());img.onload=()=>{if(last)URL.revokeObjectURL(last);last=u};
img.src=u;say('Realm '+j.name+' \\u00b7 frame '+(f.headers.get('X-Frame-Id')||''))}}}
catch(e){say('Observador detenido');return}setTimeout(tick,wait)}
login().then(ok=>{if(ok)tick()}).catch(()=>say('Observador no disponible'));})();
"""

SECURITY_HEADERS = {
    "Cache-Control": "no-store, max-age=0",
    "Pragma": "no-cache",
    "Content-Security-Policy": "default-src 'none'; script-src 'self'; style-src 'unsafe-inline'; "
                               "img-src blob:; connect-src 'self'; base-uri 'none'; form-action 'none'; "
                               "frame-ancestors 'none'",
    "X-Content-Type-Options": "nosniff",
    "X-Frame-Options": "DENY",
    "Referrer-Policy": "no-referrer",
    "Cross-Origin-Resource-Policy": "same-origin",
    "Cross-Origin-Opener-Policy": "same-origin",
}


def observer_dir(name: str, *, create: bool = False) -> Path:
    validate_name(name)
    base = host_runtime_root() / "cortetsu-agent-realms"
    directory = base / "observers" / name
    if create:
        for folder in (base, base / "observers", directory):
            try:
                folder.mkdir(mode=0o700)
            except FileExistsError:
                pass
            _require_private_dir(folder)
    return directory


def _require_private_dir(folder: Path) -> None:
    info = folder.lstat()
    if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid():
        raise RealmError(f"directorio del observador inseguro (symlink o ajeno): {folder}")
    if info.st_mode & 0o077:
        folder.chmod(0o700)


class Observer:
    """State shared by the HTTP gateway, the control channel and the watchdog."""

    def __init__(self, name: str, *, interval: float = 0.5, monitor: str | None = None,
                 idle_timeout: float = 900.0, store: CredentialStore | None = None,
                 capture_fn: Callable[..., Any] | None = None,
                 identity_fn: Callable[[], str | None] | None = None):
        self.name = name
        self.interval = interval
        self.monitor = monitor
        self.idle_timeout = idle_timeout
        self.store = store or CredentialStore()
        self.port = 0
        self.stopping = threading.Event()
        self.directory = observer_dir(name)
        self._capture = capture_fn or self._default_capture
        self._identity_fn = identity_fn or (lambda: _realm_identity(name))
        self.identity = self._identity_fn()
        if self.identity is None:
            raise RealmError(f"la sesión {name!r} no está activa")
        self._frame_lock = threading.Lock()
        self._frame: Any = None
        self._frame_at = 0.0
        self._frame_error: str | None = None
        # launch file -> (deadline, ticket); touched by HTTP, control and watchdog threads.
        self._launch_files: dict[Path, tuple[float, str]] = {}
        self._launch_lock = threading.Lock()
        self._last_activity = time.monotonic()

    @property
    def origin(self) -> str:
        return f"http://127.0.0.1:{self.port}"

    def _default_capture(self) -> Any:
        from .capture import capture
        return capture(self.name, monitor=self.monitor)

    def frame(self) -> Any:
        with self._frame_lock:
            now = time.monotonic()
            if self._frame is None or now - self._frame_at >= self.interval:
                try:
                    frame = self._capture()
                except (RealmError, OSError, subprocess.SubprocessError) as exc:
                    self._frame_error = str(exc)[:300]
                    self._frame = None
                    return None
                if getattr(frame, "session", self.identity) != self.identity:
                    self._frame_error = "el realm cambió de sesión"
                    self._frame = None
                    self.shutdown()
                    return None
                self._frame, self._frame_at, self._frame_error = frame, now, None
            return self._frame

    def state(self) -> dict[str, Any]:
        frame = self.frame()
        result: dict[str, Any] = {"name": self.name, "online": frame is not None,
                                  "interval_ms": int(self.interval * 1000)}
        if frame is None:
            result["error"] = self._frame_error or "sin captura"
        else:
            result["frame"] = frame.metadata()
        return result

    def issue_launch_file(self) -> Path:
        ticket = self.store.issue_ticket({Capability.OBSERVE})
        self._last_activity = time.monotonic()
        target = self.directory / f"launch-{os.urandom(6).hex()}.html"
        body = (f"<!doctype html><meta charset=utf-8><meta name=referrer content=no-referrer>"
                f"<meta http-equiv=refresh content=\"0;url={self.origin}/#t={ticket}\">"
                f"<title>Agent Realm observer</title>Abriendo el observador…").encode()
        fd = os.open(target, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW | os.O_CLOEXEC, 0o600)
        with os.fdopen(fd, "wb") as handle:
            handle.write(body)
        with self._launch_lock:
            self._launch_files[target] = (time.monotonic() + self.store.ticket_ttl, ticket)
        return target

    def redeemed(self, ticket: str) -> None:
        self._last_activity = time.monotonic()
        self._drop_launch_files(lambda _deadline, owner: owner == ticket)

    def _drop_launch_files(self, should_drop: Callable[[float, str], bool]) -> None:
        with self._launch_lock:
            for path, (deadline, ticket) in list(self._launch_files.items()):
                if should_drop(deadline, ticket):
                    path.unlink(missing_ok=True)
                    del self._launch_files[path]

    def pending_launches(self) -> int:
        with self._launch_lock:
            return len(self._launch_files)

    def revoke(self) -> int:
        self._drop_launch_files(lambda _deadline, _ticket: True)
        return self.store.revoke_all()

    def shutdown(self) -> None:
        self.revoke()
        self.stopping.set()

    def watch_once(self) -> None:
        now = time.monotonic()
        self._drop_launch_files(lambda deadline, _ticket: deadline <= now)
        if self._identity_fn() != self.identity:
            self.shutdown()
            return
        activity = max(self._last_activity, self.store.last_activity() or 0.0)
        if self.store.active_sessions() == 0 and not self.pending_launches() and \
                now - activity >= self.idle_timeout:
            self.shutdown()


def _realm_identity(name: str) -> str | None:
    from .capture import session_identity
    from .process import load_meta, process_alive
    try:
        meta = load_meta(paths_for(name))
    except RealmError:
        return None
    if meta.get("state") not in {"running", "degraded", "paused"} or not process_alive(meta):
        return None
    return session_identity(meta)


def make_http_handler(observer: Observer) -> type[BaseHTTPRequestHandler]:
    class Handler(BaseHTTPRequestHandler):
        server_version = "agent-realm-observer"
        sys_version = ""
        protocol_version = "HTTP/1.1"
        timeout = 10

        def log_message(self, _format: str, *_args: Any) -> None:
            return  # Request lines may carry credentials; never log them.

        def _send(self, code: int, body: bytes, content_type: str = "application/json",
                  extra: dict[str, str] | None = None) -> None:
            self.send_response(code)
            for key, value in SECURITY_HEADERS.items():
                self.send_header(key, value)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(body)))
            for key, value in (extra or {}).items():
                self.send_header(key, value)
            self.end_headers()
            if self.command != "HEAD":
                self.wfile.write(body)

        def _error(self, code: int, message: str) -> None:
            self._send(code, json.dumps({"error": message}).encode())

        def send_error(self, code: int, message: str | None = None, explain: str | None = None) -> None:
            # The stock page echoes the request line; answer with a fixed body instead.
            self.close_connection = True
            self._error(code, "petición HTTP inválida")

        def _route(self) -> str | None:
            # Exact routes only; no filesystem is ever consulted.
            host = self.headers.get("Host")
            if host != f"127.0.0.1:{observer.port}":
                self._error(421, "Host no autorizado")
                return None
            origin = self.headers.get("Origin")
            if origin is not None and origin != observer.origin:
                self._error(403, "Origin no autorizado")
                return None
            path = self.path.split("?", 1)[0]
            # The launch file navigates here cross-site; only the public page allows that.
            site = self.headers.get("Sec-Fetch-Site")
            if path.startswith("/api/") and site is not None and site not in {"same-origin", "none"}:
                self._error(403, "petición entre sitios rechazada")
                return None
            return path

        def _token(self) -> str | None:
            value = self.headers.get("Authorization", "")
            return value[7:] if value.startswith("Bearer ") else None

        def _authorized(self) -> bool:
            try:
                observer.store.authorize(self._token(), Capability.OBSERVE)
                return True
            except AuthError as exc:
                self._send(401, json.dumps({"error": str(exc)}).encode(),
                           extra={"WWW-Authenticate": 'Bearer realm="agent-realm"'})
                return False

        def do_GET(self) -> None:
            path = self._route()
            if path is None:
                return
            if path == "/":
                self._send(200, INDEX_HTML, "text/html; charset=utf-8")
            elif path == "/app.js":
                self._send(200, APP_JS, "text/javascript; charset=utf-8")
            elif path == "/api/state":
                if self._authorized():
                    self._send(200, json.dumps(observer.state(), ensure_ascii=False).encode())
            elif path == "/api/frame":
                if self._authorized():
                    frame = observer.frame()
                    if frame is None:
                        self._error(503, "sin captura disponible")
                    else:
                        width, height = frame.delivered
                        self._send(200, frame.data, "image/png",
                                   {"X-Frame-Id": frame.frame_id, "X-Frame-Width": str(width),
                                    "X-Frame-Height": str(height)})
            else:
                self._error(404, "ruta inexistente")

        do_HEAD = do_GET

        def do_POST(self) -> None:
            path = self._route()
            if path is None:
                return
            if path != "/api/session":
                self._error(404, "ruta inexistente")
                return
            if self.headers.get("Origin") != observer.origin:
                self._error(403, "Origin requerido")
                return
            if self.headers.get("Content-Type", "").split(";")[0].strip() != "application/json":
                self._error(415, "se requiere application/json")
                return
            try:
                length = int(self.headers.get("Content-Length", ""))
            except ValueError:
                self._error(411, "Content-Length requerido")
                return
            if length < 0 or length > MAX_BODY_BYTES:
                self._error(413, "cuerpo demasiado grande")
                return
            try:
                ticket = json.loads(self.rfile.read(length)).get("ticket")
                token, caps = observer.store.redeem(ticket)
            except (ValueError, AttributeError, AuthError):
                self._error(401, "ticket inválido, usado o caducado")
                return
            observer.redeemed(ticket)
            self._send(200, json.dumps({"token": token,
                                        "capabilities": sorted(c.value for c in caps)}).encode())

        def _reject(self) -> None:
            self._error(405, "método no admitido")

        do_PUT = do_DELETE = do_PATCH = do_OPTIONS = _reject

    return Handler


def peer_uid(conn: socket.socket) -> int:
    creds = conn.getsockopt(socket.SOL_SOCKET, socket.SO_PEERCRED, struct.calcsize("3i"))
    return struct.unpack("3i", creds)[1]


def make_control_handler(observer: Observer) -> type[socketserver.StreamRequestHandler]:
    class Control(socketserver.StreamRequestHandler):
        timeout = 5

        def handle(self) -> None:
            if peer_uid(self.connection) != os.getuid():
                return
            line = self.rfile.readline(MAX_CONTROL_BYTES)
            try:
                command = json.loads(line).get("command")
            except (ValueError, AttributeError):
                command = None
            if command == "status":
                reply = {"ok": True, "name": observer.name, "port": observer.port, "pid": os.getpid(),
                         "sessions": observer.store.active_sessions(), "url": observer.origin + "/"}
            elif command == "launch":
                reply = {"ok": True, "launch_file": str(observer.issue_launch_file()),
                         "url": observer.origin + "/"}
            elif command == "revoke":
                reply = {"ok": True, "revoked": observer.revoke()}
            elif command == "stop":
                observer.shutdown()
                reply = {"ok": True, "stopped": True}
            else:
                reply = {"ok": False, "error": "comando desconocido"}
            self.wfile.write(json.dumps(reply).encode() + b"\n")

    return Control


class _UnixServer(socketserver.ThreadingMixIn, socketserver.UnixStreamServer):
    daemon_threads = True

    def handle_error(self, request: Any, client_address: Any) -> None:
        return


class _HTTPServer(ThreadingHTTPServer):
    daemon_threads = True

    def handle_error(self, request: Any, client_address: Any) -> None:
        return  # Dropped clients are normal; tracebacks could echo request data.


def serve(name: str, *, port: int = 0, interval: float = 0.5, monitor: str | None = None,
          idle_timeout: float = 900.0, ready: Callable[[Observer], None] | None = None,
          observer: Observer | None = None) -> None:
    directory = observer_dir(name, create=True)
    lock_fd = os.open(directory / ".lock", os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW | os.O_CLOEXEC, 0o600)
    try:
        fcntl.flock(lock_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        os.close(lock_fd)
        raise RealmError(f"ya hay un observador activo para {name!r}") from None
    control_path = directory / CONTROL_NAME
    http = control = None
    threads: list[threading.Thread] = []
    original = {sig: signal.getsignal(sig) for sig in (signal.SIGTERM, signal.SIGINT)} \
        if threading.current_thread() is threading.main_thread() else {}
    try:
        observer = observer or Observer(name, interval=interval, monitor=monitor, idle_timeout=idle_timeout)
        for sig in original:
            signal.signal(sig, lambda *_: observer.shutdown())
        # Only the lock holder reaches this point, so a leftover socket is stale.
        control_path.unlink(missing_ok=True)
        old_umask = os.umask(0o177)
        try:
            control = _UnixServer(str(control_path), make_control_handler(observer))
        finally:
            os.umask(old_umask)
        http = _HTTPServer(("127.0.0.1", port), make_http_handler(observer))
        observer.port = http.server_port
        for target in (http.serve_forever, control.serve_forever):
            thread = threading.Thread(target=target, kwargs={"poll_interval": 0.25}, daemon=True)
            thread.start()
            threads.append(thread)
        if ready:
            ready(observer)
        while not observer.stopping.wait(1.0):
            observer.watch_once()
    finally:
        if observer is not None:
            observer.shutdown()
        for server in (http, control):
            if server is not None:
                server.shutdown()
                server.server_close()
        control_path.unlink(missing_ok=True)
        for sig, handler in original.items():
            signal.signal(sig, handler)
        os.close(lock_fd)


def control_request(name: str, command: str, timeout: float = 5.0) -> dict[str, Any] | None:
    """Send one command to the running observer; None when none is running."""
    path = observer_dir(name) / CONTROL_NAME
    try:
        info = path.lstat()
    except FileNotFoundError:
        return None
    if not stat.S_ISSOCK(info.st_mode) or info.st_uid != os.getuid():
        raise RealmError("el socket de control del observador no es un socket propio")
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as sock:
        sock.settimeout(timeout)
        try:
            sock.connect(str(path))
        except (ConnectionRefusedError, FileNotFoundError):
            return None
        try:
            sock.sendall(json.dumps({"command": command}).encode() + b"\n")
            data = sock.makefile("rb").readline(MAX_CONTROL_BYTES)
        except OSError as exc:
            raise RealmError("respuesta inválida del observador") from exc
    try:
        reply = json.loads(data)
    except ValueError as exc:
        raise RealmError("respuesta inválida del observador") from exc
    if not isinstance(reply, dict) or not reply.get("ok"):
        raise RealmError(f"el observador rechazó {command}: {reply}")
    return reply


def notify_realm_stopped(name: str) -> None:
    """Best effort: make a running observer revoke access and exit now."""
    try:
        control_request(name, "stop", timeout=2.0)
    except (RealmError, OSError):
        pass


def _observer_env() -> dict[str, str]:
    env = {"PATH": "/usr/local/bin:/usr/bin:/bin", "PYTHONPATH": str(repo_root() / "src")}
    for key in ("HOME", "LANG", "XDG_RUNTIME_DIR", "XDG_STATE_HOME", "XDG_DATA_HOME",
                "XDG_CONFIG_HOME", "XDG_CACHE_HOME", "DBUS_SESSION_BUS_ADDRESS"):
        if key in os.environ:
            env[key] = os.environ[key]
    return env


def ensure_running(name: str, *, port: int = 0, interval: float = 0.5, monitor: str | None = None,
                   idle_timeout: float = 900.0, timeout: float = 10.0) -> dict[str, Any]:
    status = control_request(name, "status")
    if status:
        return status
    if _realm_identity(name) is None:
        raise RealmError(f"la sesión {name!r} no está activa")
    args = [sys.executable, "-m", "cortetsu_agent_realms.observer", name, "--port", str(port),
            "--interval", str(interval), "--idle-timeout", str(idle_timeout)]
    if monitor:
        args += ["--monitor", monitor]
    proc = subprocess.Popen(args, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                            stderr=subprocess.PIPE, start_new_session=True, close_fds=True,
                            env=_observer_env())
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        status = control_request(name, "status")
        if status:
            proc.stderr.close()
            return status
        if proc.poll() is not None:
            detail = proc.stderr.read(4000).decode(errors="replace").strip()
            raise RealmError(f"el observador terminó al iniciar: {detail}")
        time.sleep(0.05)
    proc.terminate()
    raise RealmError("el observador no publicó su socket de control a tiempo")


def open_browser(launch_file: str) -> None:
    opener = shutil.which("xdg-open", path="/usr/local/bin:/usr/bin:/bin")
    if not opener:
        raise RealmError("xdg-open no está disponible; abre el archivo de lanzamiento a mano")
    # Only the path travels in argv; the one-use ticket stays inside the 0600 file.
    subprocess.Popen([opener, Path(launch_file).as_uri()], stdin=subprocess.DEVNULL,
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="cortetsu_agent_realms.observer")
    parser.add_argument("name")
    parser.add_argument("--port", type=int, default=0)
    parser.add_argument("--interval", type=float, default=0.5)
    parser.add_argument("--monitor")
    parser.add_argument("--idle-timeout", type=float, default=900.0)
    args = parser.parse_args(argv)
    try:
        serve(args.name, port=args.port, interval=args.interval, monitor=args.monitor,
              idle_timeout=args.idle_timeout)
    except (RealmError, OSError) as exc:
        print(f"agent-realm observer: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
