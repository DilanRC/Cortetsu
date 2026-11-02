"""A private PipeWire graph with virtual devices, inside the realm.

Clients such as Quickshell use PipeWire's native socket ($XDG_RUNTIME_DIR/pipewire-0),
not D-Bus, so the simulation runs a real PipeWire daemon with null sinks and sources.
The realm has no /dev/snd and no ALSA monitor is loaded: nothing can reach speakers.
The small default-device role WirePlumber normally plays (configured default ->
default) is mirrored here from the `default` metadata.
"""
from __future__ import annotations

import json
import os
import signal
import subprocess
import time
from pathlib import Path
from typing import Any, Callable

from gi.repository import GLib

CONFIG = """context.properties = {
    core.daemon = true
    core.name = pipewire-0
    support.dbus = false
    mem.allow-mlock = false
}
context.spa-libs = {
    audio.convert.* = audioconvert/libspa-audioconvert
    support.*       = support/libspa-support
}
context.modules = [
    { name = libpipewire-module-protocol-native }
    { name = libpipewire-module-access
      args = { access.socket = { pipewire-0 = "unrestricted" pipewire-0-manager = "unrestricted" } } }
    { name = libpipewire-module-metadata }
    { name = libpipewire-module-spa-node-factory }
    { name = libpipewire-module-client-node }
    { name = libpipewire-module-adapter }
]
context.objects = [
    { factory = metadata args = { metadata.name = default } }
    { factory = spa-node-factory
      args = { factory.name = support.node.driver node.name = Dummy-Driver
               node.group = pipewire.dummy priority.driver = 20000 } }
]
"""
RESTART_DELAY_MS = 3000


def _run(*argv: str, timeout: float = 5) -> subprocess.CompletedProcess[str]:
    return subprocess.run(list(argv), capture_output=True, text=True, timeout=timeout)


class Audio:
    def __init__(self, state: Callable[[], dict[str, Any]], changed: Callable[[], None], workdir: Path):
        self.state, self.changed = state, changed
        self.workdir = workdir
        self.runtime = Path(os.environ["XDG_RUNTIME_DIR"])
        self.daemon: subprocess.Popen[bytes] | None = None
        self.monitor: subprocess.Popen[bytes] | None = None
        self.monitor_pending = b""
        self.player: subprocess.Popen[bytes] | None = None
        self.applied: dict[str, dict[str, Any]] = {}
        self.restart_source = 0

    # -- daemon -------------------------------------------------------------------------

    def running(self) -> bool:
        return self.daemon is not None and self.daemon.poll() is None

    def start_daemon(self) -> None:
        config = self.workdir / "pipewire.conf"
        config.write_text(CONFIG)
        log = (self.workdir / "pipewire.log").open("ab")
        self.daemon = subprocess.Popen(["/usr/bin/pipewire", "-c", str(config)], stdin=subprocess.DEVNULL,
                                       stdout=log, stderr=log, close_fds=True)
        log.close()
        deadline = time.monotonic() + 5
        while not (self.runtime / "pipewire-0").exists():
            if self.daemon.poll() is not None or time.monotonic() > deadline:
                raise RuntimeError("PipeWire privado no publicó pipewire-0")
            time.sleep(0.05)
        self.applied = {}
        monitor = subprocess.Popen(["/usr/bin/pw-metadata", "-m", "-n", "default"], stdin=subprocess.DEVNULL,
                                   stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, close_fds=True)
        # Non-blocking and bound to this process: a blocking readline() on a partial
        # line, or a stale watch reading a newer monitor, froze the whole main loop.
        os.set_blocking(monitor.stdout.fileno(), False)
        self.monitor, self.monitor_pending = monitor, b""
        GLib.io_add_watch(monitor.stdout.fileno(), GLib.PRIORITY_DEFAULT, GLib.IO_IN | GLib.IO_HUP,
                          self._on_metadata, monitor)

    def stop_daemon(self) -> None:
        for proc in (self.player, self.monitor, self.daemon):
            if proc is not None and proc.poll() is None:
                proc.send_signal(signal.SIGTERM)
                try:
                    proc.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    proc.kill()
                    proc.wait()
        self.player = self.monitor = self.daemon = None
        self.applied = {}
        for leftover in ("pipewire-0", "pipewire-0.lock", "pipewire-0-manager", "pipewire-0-manager.lock"):
            (self.runtime / leftover).unlink(missing_ok=True)

    def _on_metadata(self, fd: int, _condition: int, monitor: subprocess.Popen[bytes]) -> bool:
        if monitor is not self.monitor:
            return False
        try:
            chunk = os.read(fd, 65536)
        except BlockingIOError:
            return True
        except OSError:
            return False
        if not chunk:
            return False
        *lines, self.monitor_pending = (self.monitor_pending + chunk).split(b"\n")
        self.monitor_pending = self.monitor_pending[-65536:]
        for line in lines:
            self._metadata_line(line.decode(errors="replace"))
        return True

    def _metadata_line(self, line: str) -> None:
        # e.g. update: id:0 key:'default.configured.audio.sink' value:'{"name":"x"}' type:'Spa:String:JSON'
        for kind in ("sink", "source"):
            marker = f"key:'default.configured.audio.{kind}' value:'"
            if marker in line:
                raw = line.split(marker, 1)[1].rsplit("' type:", 1)[0]
                try:
                    name = json.loads(raw).get("name")
                except (ValueError, AttributeError):
                    continue
                audio = self.state()["audio"]
                if name in {n["name"] for n in audio[f"{kind}s"]} and audio[f"default_{kind}"] != name:
                    audio[f"default_{kind}"] = name
                    self.changed()

    # -- graph --------------------------------------------------------------------------

    def _nodes(self) -> dict[str, dict[str, Any]]:
        dump = json.loads(_run("/usr/bin/pw-dump").stdout or "[]")
        nodes = {}
        for obj in dump:
            if obj.get("type") != "PipeWire:Interface:Node":
                continue
            info = obj.get("info") or {}
            props = info.get("props") or {}
            name = props.get("node.name")
            if not name:
                continue
            params = (info.get("params") or {}).get("Props") or [{}]
            values = next((p for p in params if "channelVolumes" in p), params[0] if params else {})
            volumes = values.get("channelVolumes") or [0.0]
            nodes[name] = {"id": obj["id"], "media_class": props.get("media.class"),
                           "description": props.get("node.description"),
                           "volume": round(max(volumes) ** (1 / 3), 3), "mute": bool(values.get("mute", False)),
                           "application": props.get("application.name")}
        return nodes

    def _create(self, node: dict[str, Any], media_class: str) -> None:
        props = (f"{{ factory.name=support.null-audio-sink node.name={node['name']} "
                 f"node.description=\"{node['description']}\" media.class={media_class} "
                 "audio.position=[FL FR] object.linger=true monitor.channel-volumes=true }")
        result = _run("/usr/bin/pw-cli", "create-node", "adapter", props)
        if result.returncode != 0:
            raise RuntimeError(f"no se pudo crear el nodo {node['name']}: {result.stderr.strip()}")

    def _set_props(self, node_id: int, volume: float, mute: bool) -> None:
        cubic = round(volume ** 3, 6)
        _run("/usr/bin/pw-cli", "set-param", str(node_id), "Props",
             f"{{ mute: {'true' if mute else 'false'}, channelVolumes: [ {cubic}, {cubic} ] }}")

    def _set_default(self, kind: str, name: str | None) -> None:
        for key in (f"default.audio.{kind}", f"default.configured.audio.{kind}"):
            if name is None:
                _run("/usr/bin/pw-metadata", "-n", "default", "-d", "0", key)
            else:
                _run("/usr/bin/pw-metadata", "-n", "default", "0", key, json.dumps({"name": name}),
                     "Spa:String:JSON")

    def sync(self) -> None:
        audio = self.state()["audio"]
        if audio["restarting"]:
            if self.running():
                self.stop_daemon()
            if not self.restart_source:
                self.restart_source = GLib.timeout_add(RESTART_DELAY_MS, self._finish_restart)
            return
        if not audio["available"]:
            self.stop_daemon()
            return
        if not self.running():
            self.start_daemon()
        live = self._nodes()
        wanted = {n["name"]: (n, "Audio/Sink") for n in audio["sinks"]}
        wanted |= {n["name"]: (n, "Audio/Source") for n in audio["sources"]}
        for name, info in live.items():
            if info["media_class"] in {"Audio/Sink", "Audio/Source"} and name not in wanted:
                _run("/usr/bin/pw-cli", "destroy", str(info["id"]))
                self.applied.pop(name, None)
        created = False
        for name, (node, media_class) in wanted.items():
            if name not in live:
                self._create(node, media_class)
                created = True
        if created:
            live = self._nodes()
        for name, (node, _media_class) in wanted.items():
            desired = {"volume": node["volume"], "mute": node["mute"]}
            if name in live and self.applied.get(name) != desired:
                self._set_props(live[name]["id"], node["volume"], node["mute"])
                self.applied[name] = desired
        for kind in ("sink", "source"):
            if self.applied.get(f"default:{kind}") != {"name": audio[f"default_{kind}"]}:
                self._set_default(kind, audio[f"default_{kind}"])
                self.applied[f"default:{kind}"] = {"name": audio[f"default_{kind}"]}
        self._sync_playback(audio)

    def _sync_playback(self, audio: dict[str, Any]) -> None:
        playing = self.player is not None and self.player.poll() is None
        if audio["playback"] and not playing and audio["default_sink"]:
            # Silence from /dev/zero into a null sink: a real stream, no sound anywhere.
            zero = open("/dev/zero", "rb")
            self.player = subprocess.Popen(
                ["/usr/bin/pw-cat", "--playback", "--raw", "--format", "s16", "--rate", "48000", "--channels", "2",
                 "--target", audio["default_sink"],
                 "-P", "{ application.name = \"Reproductor simulado\" media.name = \"Reproduccion simulada\" }",
                 "-"],
                stdin=zero, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, close_fds=True)
            zero.close()
        elif not audio["playback"] and playing:
            self.player.terminate()
            self.player.wait(timeout=3)
            self.player = None

    def _finish_restart(self) -> bool:
        self.restart_source = 0
        self.state()["audio"]["restarting"] = False
        self.changed()
        return False

    def live_status(self) -> dict[str, Any]:
        if not self.running():
            return {"running": False}
        nodes = self._nodes()
        return {"running": True, "nodes": {name: {k: v for k, v in info.items() if k != "id"}
                                           for name, info in nodes.items() if name != "Dummy-Driver"}}
