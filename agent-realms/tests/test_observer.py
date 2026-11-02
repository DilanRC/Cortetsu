"""Observer security contracts: real HTTP and control servers, fake capture and realm identity."""
from __future__ import annotations

import http.client
import json
import os
import re
import socket
import stat
import struct
import tempfile
import threading
import unittest
from pathlib import Path
from unittest.mock import patch

from cortetsu_agent_realms import observer as obs
from cortetsu_agent_realms.auth import AuthError, Capability, CredentialStore
from cortetsu_agent_realms.capture import Frame, Monitor
from cortetsu_agent_realms.cli import parser
from cortetsu_agent_realms.paths import RealmError, paths_for


def _png(width: int, height: int) -> bytes:
    return b"\x89PNG\r\n\x1a\n" + struct.pack(">I", 13) + b"IHDR" + struct.pack(">II", width, height) + b"\0" * 9


MONITOR = Monitor("HEADLESS-2", 0, 0, 1280, 800, 1.0, True)


class Clock:
    def __init__(self) -> None:
        self.now = 1000.0

    def __call__(self) -> float:
        return self.now


class RealmStub:
    """Stands in for a live realm: identity can change or disappear like after stop/restart."""

    def __init__(self, name: str) -> None:
        self.name = name
        self.identity: str | None = f"agent-realm-{name}-0123456789.scope:42"
        self.captures = 0

    def capture(self) -> Frame:
        self.captures += 1
        return Frame(data=_png(1280, 800), realm=self.name, monitor=MONITOR, region=(0, 0, 1280, 800),
                     delivered=(1280, 800), image_format="png", frame_id=f"f{self.captures}",
                     session=f"agent-realm-{self.name}-0123456789.scope:42")


class RunningObserver:
    def __init__(self, name: str, store: CredentialStore | None = None) -> None:
        self.realm = RealmStub(name)
        self.observer = obs.Observer(name, interval=0.25, idle_timeout=600, store=store,
                                     capture_fn=self.realm.capture, identity_fn=lambda: self.realm.identity)
        started = threading.Event()
        self.thread = threading.Thread(target=obs.serve, args=(name,),
                                       kwargs={"observer": self.observer, "ready": lambda _o: started.set()},
                                       daemon=True)
        self.thread.start()
        if not started.wait(5):
            raise RuntimeError("observer did not start")

    @property
    def port(self) -> int:
        return self.observer.port

    def request(self, method: str, path: str, *, headers: dict[str, str] | None = None,
                body: bytes | None = None) -> tuple[int, dict[str, str], bytes]:
        conn = http.client.HTTPConnection("127.0.0.1", self.port, timeout=5)
        try:
            conn.request(method, path, body=body, headers=headers or {})
            response = conn.getresponse()
            return response.status, dict(response.getheaders()), response.read()
        finally:
            conn.close()

    def ticket(self) -> str:
        launch = obs.control_request(self.observer.name, "launch")
        text = Path(launch["launch_file"]).read_text()
        return re.search(r"#t=([A-Za-z0-9_-]+)", text).group(1)

    def login(self, ticket: str | None = None) -> tuple[int, dict]:
        body = json.dumps({"ticket": ticket or self.ticket()}).encode()
        status, _headers, data = self.request("POST", "/api/session", body=body, headers={
            "Origin": self.observer.origin, "Content-Type": "application/json"})
        return status, json.loads(data)

    def get(self, path: str, token: str | None = None, **extra: str) -> tuple[int, dict[str, str], bytes]:
        headers = dict(extra)
        if token:
            headers["Authorization"] = f"Bearer {token}"
        return self.request("GET", path, headers=headers)

    def stop(self) -> None:
        self.observer.shutdown()
        self.thread.join(5)


class ObserverTestCase(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory(prefix="agent-realm-observer-")
        runtime = Path(self.tmp.name) / "run"
        runtime.mkdir(mode=0o700)
        self.env = patch.dict(os.environ, {"XDG_RUNTIME_DIR": str(runtime),
                                           "XDG_STATE_HOME": str(Path(self.tmp.name) / "state"),
                                           "XDG_DATA_HOME": str(Path(self.tmp.name) / "data")})
        self.env.start()
        self.running: list[RunningObserver] = []

    def tearDown(self) -> None:
        for item in self.running:
            item.stop()
        self.env.stop()
        self.tmp.cleanup()

    def start(self, name: str = "codex", store: CredentialStore | None = None) -> RunningObserver:
        item = RunningObserver(name, store)
        self.running.append(item)
        return item


class AuthorizationTests(ObserverTestCase):
    def test_authorized_viewer_gets_state_and_png_frame(self) -> None:
        o = self.start()
        status, session = o.login()
        self.assertEqual(status, 200)
        self.assertEqual(session["capabilities"], ["observe"])
        code, _h, body = o.get("/api/state", session["token"])
        self.assertEqual(code, 200)
        self.assertTrue(json.loads(body)["online"])
        code, headers, body = o.get("/api/frame", session["token"])
        self.assertEqual(code, 200)
        self.assertEqual(headers["Content-Type"], "image/png")
        self.assertTrue(body.startswith(b"\x89PNG"))
        self.assertEqual(headers["Cache-Control"], "no-store, max-age=0")
        self.assertIn("frame-ancestors 'none'", headers["Content-Security-Policy"])

    def test_unauthenticated_requests_get_no_frames_or_state(self) -> None:
        o = self.start()
        for path in ("/api/frame", "/api/state"):
            code, headers, body = o.get(path)
            self.assertEqual(code, 401, path)
            self.assertNotIn(b"PNG", body)
            self.assertIn("WWW-Authenticate", headers)
        self.assertEqual(o.realm.captures, 0, "unauthenticated traffic must not trigger captures")

    def test_invalid_tokens_and_tickets_are_rejected(self) -> None:
        o = self.start()
        self.assertEqual(o.get("/api/frame", "x" * 43)[0], 401)
        code, _h, _b = o.request("GET", "/api/frame", headers={"Authorization": "Basic Zm9vOmJhcg=="})
        self.assertEqual(code, 401)
        self.assertEqual(o.login("not-a-ticket-but-long-enough-xxxx")[0], 401)

    def test_ticket_is_single_use_and_launch_file_is_private_then_removed(self) -> None:
        o = self.start()
        launch = Path(obs.control_request("codex", "launch")["launch_file"])
        self.assertEqual(stat.S_IMODE(launch.stat().st_mode), 0o600)
        ticket = re.search(r"#t=([A-Za-z0-9_-]+)", launch.read_text()).group(1)
        self.assertEqual(o.login(ticket)[0], 200)
        self.assertFalse(launch.exists(), "launch file must disappear once its ticket is used")
        self.assertEqual(o.login(ticket)[0], 401)

    def test_redeeming_one_ticket_keeps_other_pending_launch_files(self) -> None:
        o = self.start()
        first = Path(obs.control_request("codex", "launch")["launch_file"])
        second = Path(obs.control_request("codex", "launch")["launch_file"])
        ticket = re.search(r"#t=([A-Za-z0-9_-]+)", first.read_text()).group(1)
        self.assertEqual(o.login(ticket)[0], 200)
        self.assertFalse(first.exists())
        self.assertTrue(second.exists(), "a concurrent viewer must keep its launch file")
        ticket2 = re.search(r"#t=([A-Za-z0-9_-]+)", second.read_text()).group(1)
        self.assertEqual(o.login(ticket2)[0], 200)

    def test_index_page_carries_no_credentials(self) -> None:
        o = self.start()
        ticket = o.ticket()
        for path in ("/", "/app.js"):
            code, _h, body = o.get(path)
            self.assertEqual(code, 200)
            self.assertNotIn(ticket.encode(), body)
            self.assertNotIn(b"localStorage", body)
            self.assertNotIn(b"document.cookie", body)

    def test_observer_session_cannot_control_or_administer(self) -> None:
        store = CredentialStore()
        token, caps = store.redeem(store.issue_ticket({Capability.OBSERVE}))
        self.assertEqual(caps, {Capability.OBSERVE})
        store.authorize(token, Capability.OBSERVE)
        for needed in (Capability.CONTROL, Capability.ADMIN):
            with self.assertRaises(AuthError):
                store.authorize(token, needed)
        o = self.start()
        token = o.login()[1]["token"]
        for method in ("PUT", "DELETE", "PATCH"):
            self.assertEqual(o.request(method, "/api/frame",
                                       headers={"Authorization": f"Bearer {token}"})[0], 405)
        self.assertEqual(o.request("POST", "/api/input", headers={"Origin": o.observer.origin})[0], 404)


class ExpiryAndRevocationTests(ObserverTestCase):
    def test_expired_ticket_idle_session_and_max_age(self) -> None:
        clock = Clock()
        store = CredentialStore(ticket_ttl=60, session_idle=100, session_max_age=1000, clock=clock)
        ticket = store.issue_ticket({Capability.OBSERVE})
        clock.now += 61
        with self.assertRaises(AuthError):
            store.redeem(ticket)
        token, _ = store.redeem(store.issue_ticket({Capability.OBSERVE}))
        clock.now += 101
        with self.assertRaises(AuthError):
            store.authorize(token, Capability.OBSERVE)
        token, _ = store.redeem(store.issue_ticket({Capability.OBSERVE}))
        for _ in range(11):
            clock.now += 90
            store.authorize(token, Capability.OBSERVE)  # activity keeps it under the idle limit
        clock.now += 90
        with self.assertRaises(AuthError):
            store.authorize(token, Capability.OBSERVE)  # absolute age wins

    def test_expired_credentials_over_http(self) -> None:
        clock = Clock()
        o = self.start(store=CredentialStore(ticket_ttl=60, session_idle=100, clock=clock))
        token = o.login()[1]["token"]
        stale_ticket = o.ticket()
        clock.now += 120
        self.assertEqual(o.get("/api/frame", token)[0], 401)
        self.assertEqual(o.login(stale_ticket)[0], 401)

    def test_revocation_invalidates_sessions_and_pending_tickets(self) -> None:
        o = self.start()
        token = o.login()[1]["token"]
        pending = o.ticket()
        self.assertGreaterEqual(obs.control_request("codex", "revoke")["revoked"], 2)
        self.assertEqual(o.get("/api/frame", token)[0], 401)
        self.assertEqual(o.login(pending)[0], 401)
        self.assertEqual(list(o.observer.directory.glob("launch-*")), [])

    def test_restarted_observer_does_not_honor_old_tokens(self) -> None:
        first = self.start()
        token = first.login()[1]["token"]
        first.stop()
        self.running.remove(first)
        second = self.start()
        self.assertEqual(second.get("/api/frame", token)[0], 401)

    def test_tokens_do_not_cross_realms(self) -> None:
        a, b = self.start("codex"), self.start("claude")
        token_a = a.login()[1]["token"]
        self.assertEqual(b.get("/api/frame", token_a)[0], 401)
        self.assertEqual(b.login(a.ticket())[0], 401)
        self.assertEqual(a.get("/api/frame", token_a)[0], 200)


class RealmLifecycleTests(ObserverTestCase):
    def test_stopped_realm_revokes_access_and_closes_observer(self) -> None:
        o = self.start()
        token = o.login()[1]["token"]
        o.realm.identity = None
        o.observer.watch_once()
        o.thread.join(5)
        self.assertFalse(o.thread.is_alive())
        with self.assertRaises(AuthError):
            o.observer.store.authorize(token, Capability.OBSERVE)
        self.assertFalse((o.observer.directory / obs.CONTROL_NAME).exists())
        with self.assertRaises(OSError):
            o.get("/api/frame", token)

    def test_realm_restarted_under_same_name_is_a_different_session(self) -> None:
        o = self.start()
        token = o.login()[1]["token"]
        o.realm.identity = "agent-realm-codex-ffffffffff.scope:99"
        o.observer.watch_once()
        o.thread.join(5)
        self.assertFalse(o.thread.is_alive())
        with self.assertRaises(AuthError):
            o.observer.store.authorize(token, Capability.OBSERVE)

    def test_frame_from_another_session_is_never_served(self) -> None:
        o = self.start()
        token = o.login()[1]["token"]
        o.observer._capture = lambda: Frame(data=_png(1, 1), realm="codex", monitor=MONITOR,
                                            region=(0, 0, 1, 1), delivered=(1, 1), image_format="png",
                                            frame_id="x", session="other:1")
        code, _h, body = o.get("/api/frame", token)
        self.assertIn(code, (401, 503))
        self.assertNotIn(b"PNG", body)

    def test_idle_observer_exits_without_viewers(self) -> None:
        o = self.start()
        o.observer.idle_timeout = 0
        o.observer.watch_once()
        o.thread.join(5)
        self.assertFalse(o.thread.is_alive())

    def test_shutdown_removes_socket_and_launch_files(self) -> None:
        o = self.start()
        o.ticket()
        directory = o.observer.directory
        o.stop()
        self.running.remove(o)
        self.assertFalse((directory / obs.CONTROL_NAME).exists())
        self.assertEqual(list(directory.glob("launch-*")), [])
        self.assertIsNone(obs.control_request("codex", "status"))

    def test_second_observer_for_same_realm_is_refused(self) -> None:
        self.start()
        with self.assertRaisesRegex(RealmError, "ya hay un observador"):
            obs.serve("codex", observer=obs.Observer("codex", capture_fn=lambda: None,
                                                      identity_fn=lambda: "x"))

    def test_crashed_observer_leaves_stale_socket_that_is_replaced(self) -> None:
        directory = obs.observer_dir("codex", create=True)
        stale = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        stale.bind(str(directory / obs.CONTROL_NAME))
        stale.close()  # like SIGKILL: the path survives, nobody listens
        self.assertIsNone(obs.control_request("codex", "status"))
        o = self.start()
        self.assertEqual(obs.control_request("codex", "status")["port"], o.port)


class RequestHardeningTests(ObserverTestCase):
    def test_foreign_origin_host_and_cross_site_fetches_are_refused(self) -> None:
        o = self.start()
        token = o.login()[1]["token"]
        body = json.dumps({"ticket": o.ticket()}).encode()
        self.assertEqual(o.request("POST", "/api/session", body=body, headers={
            "Origin": "http://evil.example", "Content-Type": "application/json"})[0], 403)
        self.assertEqual(o.request("POST", "/api/session", body=body, headers={
            "Content-Type": "application/json"})[0], 403, "POST without Origin must fail")
        self.assertEqual(o.get("/api/frame", token, Origin="http://127.0.0.1:1")[0], 403)
        self.assertEqual(o.get("/api/frame", token, **{"Sec-Fetch-Site": "cross-site"})[0], 403)
        conn = http.client.HTTPConnection("127.0.0.1", o.port, timeout=5)
        conn.putrequest("GET", "/api/frame", skip_host=True)
        conn.putheader("Host", "rebind.example:80")
        conn.putheader("Authorization", f"Bearer {token}")
        conn.endheaders()
        self.assertEqual(conn.getresponse().status, 421)
        conn.close()

    def test_malformed_requests_fail_closed_and_server_survives(self) -> None:
        o = self.start()
        for raw in (b"GARBAGE\r\n\r\n", b"GET\r\n\r\n", b"\x00\xff\xfe\r\n\r\n",
                    b"GET / HTTP/9.9\r\nHost: x\r\n\r\n", b"GET /" + b"a" * 70000 + b" HTTP/1.1\r\n\r\n"):
            with socket.create_connection(("127.0.0.1", o.port), timeout=5) as sock:
                sock.sendall(raw)
                reply = sock.recv(256)
                self.assertTrue(reply == b"" or reply.split()[1] in {b"400", b"414", b"421", b"505"}, reply)
        origin = {"Origin": o.observer.origin}
        self.assertEqual(o.request("POST", "/api/session", body=b"{}", headers={
            **origin, "Content-Type": "text/plain"})[0], 415)
        self.assertEqual(o.request("POST", "/api/session", body=b"x" * 2048, headers={
            **origin, "Content-Type": "application/json"})[0], 413)
        self.assertEqual(o.request("POST", "/api/session", body=b"not json", headers={
            **origin, "Content-Type": "application/json"})[0], 401)
        self.assertEqual(o.request("POST", "/api/session", body=b"[1,2]", headers={
            **origin, "Content-Type": "application/json"})[0], 401)
        self.assertEqual(o.get("/")[0], 200, "server must keep serving after bad input")

    def test_traversal_and_unknown_paths_never_reach_the_filesystem(self) -> None:
        o = self.start()
        token = o.login()[1]["token"]
        secret = Path(self.tmp.name) / "secret.txt"
        secret.write_text("TOP-SECRET")
        for path in ("/../../etc/passwd", "/%2e%2e/%2e%2e/etc/passwd", "//etc/passwd",
                     "/app.js/../../secret.txt", f"/{secret}", "/api/frame/../../../etc/shadow",
                     "/observer-state.json", "/current.png", "/index.html"):
            code, _h, body = o.get(path, token)
            self.assertEqual(code, 404, path)
            self.assertNotIn(b"root:", body)
            self.assertNotIn(b"TOP-SECRET", body)


class FilesystemTrustTests(ObserverTestCase):
    def test_observer_tree_lives_outside_every_realm_mount(self) -> None:
        directory = obs.observer_dir("codex", create=True)
        paths = paths_for("codex")
        self.assertTrue(directory.is_relative_to(Path(os.environ["XDG_RUNTIME_DIR"])))
        for mounted in (paths.state, paths.home, paths.runtime, paths.parent_runtime):
            self.assertFalse(directory.is_relative_to(mounted), mounted)
        for folder in (directory, directory.parent, directory.parent.parent):
            self.assertEqual(stat.S_IMODE(folder.stat().st_mode), 0o700)

    def test_symlinked_observer_directories_are_refused(self) -> None:
        target = Path(self.tmp.name) / "elsewhere"
        target.mkdir()
        base = Path(os.environ["XDG_RUNTIME_DIR"]) / "cortetsu-agent-realms"
        base.mkdir(mode=0o700)
        (base / "observers").symlink_to(target, target_is_directory=True)
        with self.assertRaisesRegex(RealmError, "inseguro"):
            obs.observer_dir("codex", create=True)
        (base / "observers").unlink()
        (base / "observers").mkdir(mode=0o700)
        (base / "observers" / "codex").symlink_to(target, target_is_directory=True)
        with self.assertRaisesRegex(RealmError, "inseguro"):
            obs.observer_dir("codex", create=True)
        self.assertEqual(list(target.iterdir()), [])

    def test_special_files_in_place_of_control_socket_or_lock_are_refused(self) -> None:
        directory = obs.observer_dir("codex", create=True)
        control = directory / obs.CONTROL_NAME
        os.mkfifo(control)
        with self.assertRaisesRegex(RealmError, "no es un socket"):
            obs.control_request("codex", "status")
        control.unlink()
        control.symlink_to("/etc/passwd")
        with self.assertRaisesRegex(RealmError, "no es un socket"):
            obs.control_request("codex", "status")
        control.unlink()
        (directory / ".lock").symlink_to(Path(self.tmp.name) / "planted")
        with self.assertRaises(OSError):
            obs.serve("codex", observer=obs.Observer("codex", capture_fn=lambda: None, identity_fn=lambda: "x"))
        self.assertFalse((Path(self.tmp.name) / "planted").exists())

    def test_control_channel_ignores_other_uids(self) -> None:
        o = self.start()
        with patch.object(obs, "peer_uid", return_value=os.getuid() + 1):
            with self.assertRaisesRegex(RealmError, "respuesta inválida"):
                obs.control_request("codex", "launch")
        self.assertEqual(list(o.observer.directory.glob("launch-*")), [])

    def test_unknown_control_commands_are_rejected(self) -> None:
        self.start()
        with self.assertRaisesRegex(RealmError, "rechazó"):
            obs.control_request("codex", "../../exec")


class RealmStopTests(unittest.TestCase):
    def test_realm_stop_tells_the_observer_before_cleaning_up(self) -> None:
        from cortetsu_agent_realms import runtime
        calls: list[str] = []
        with tempfile.TemporaryDirectory() as tmp, \
             patch.dict(os.environ, {"XDG_STATE_HOME": tmp, "XDG_DATA_HOME": tmp}), \
             patch.object(runtime, "load_meta", return_value={"name": "codex", "schema": 1}), \
             patch.object(runtime, "save_meta"), \
             patch.object(obs, "control_request", side_effect=lambda n, c, **_: calls.append(f"{c}:{n}")), \
             patch.object(runtime, "cleanup_groups", side_effect=lambda _p: calls.append("cleanup")):
            runtime.stop("codex")
        self.assertEqual(calls[:2], ["stop:codex", "cleanup"])


class CliContractTests(unittest.TestCase):
    def test_observe_flags(self) -> None:
        args = parser().parse_args(["observe", "codex", "--open"])
        self.assertTrue(args.open)
        for flag in ("--revoke", "--stop", "--status", "--foreground", "--launch-file"):
            self.assertTrue(getattr(parser().parse_args(["observe", "codex", flag]),
                                    flag[2:].replace("-", "_")))

    def test_browser_launch_never_puts_the_ticket_in_argv(self) -> None:
        with patch.object(obs.subprocess, "Popen") as popen, \
             patch.object(obs.shutil, "which", return_value="/usr/bin/xdg-open"):
            obs.open_browser("/run/user/1000/cortetsu-agent-realms/observers/codex/launch-abc.html")
        argv = popen.call_args.args[0]
        self.assertEqual(argv, ["/usr/bin/xdg-open",
                                "file:///run/user/1000/cortetsu-agent-realms/observers/codex/launch-abc.html"])


if __name__ == "__main__":
    unittest.main()
