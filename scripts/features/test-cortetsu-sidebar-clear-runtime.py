#!/usr/bin/env python3
"""Clearing notifications with the notification centre open logs no binding loop.

The real sidebar Content.qml, Notifs and NotifData run in Quickshell on the
offscreen platform, inside a private D-Bus session (Notifs owns a
NotificationServer) with HOME and the state directory in a temporary tree and
a no-op `cortetsu-notifications` first on PATH, so nothing here touches the
desktop's notifications or history.

Closing each item the way Notifs.applyClearState does used to log one
"Binding loop detected for property model" per notification (22 at once in
the shell journal on 2026-10-23): a delegate destroyed by the model change
unlocked its item, which removed it from Notifs and bumped `revision` while
the ListView was still applying the previous model.
"""
import os
import shutil
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2] / "cortetsu"
COUNT = 6

SHELL = """import QtQuick
import QtQuick.Window
import Quickshell
import "services"
import "modules/sidebar" as Sidebar

ShellRoot {
    id: root
    property int step: 0
    property var view: null
    Component { id: notifData; NotifData {} }
    QtObject { id: screenState; property bool sidebar: true }

    Window {
        width: 440; height: 700; visible: true
        Sidebar.Content { id: content; anchors.fill: parent; screenState: screenState }
    }

    function find(item, type) {
        if (!item) return null;
        if (String(item).startsWith(type)) return item;
        for (const child of item.children) { const hit = find(child, type); if (hit) return hit; }
        return null;
    }

    Timer {
        interval: 200; repeat: true; running: true
        onTriggered: {
            if (root.step === 0) {
                const items = [];
                for (let i = 0; i < %(count)d; ++i)
                    items.push(notifData.createObject(root, { key: `n${i}`, summary: `Aviso ${i}`, appName: "prueba" }));
                Notifs.list = [...items, ...Notifs.list];
                Notifs.refreshCollections();
            } else if (root.step === 1) {
                root.view = root.find(content, "QQuickListView");
                console.log("SIDEBAR_ACTIVE", root.view.count);
                // Notifs.applyClearState closes every item in one pass.
                Notifs.list.slice().forEach(item => item.close());
            } else {
                console.log("SIDEBAR_AFTER", root.view.count, Notifs.list.length);
                Qt.quit();
            }
            root.step += 1;
        }
    }
}
""" % {"count": COUNT}

with tempfile.TemporaryDirectory(prefix="cortetsu-sidebar-clear-") as temporary:
    folder = Path(temporary)
    for name in ("modules", "components", "services", "theme", "assets", "utils"):
        shutil.copytree(ROOT / name, folder / name)
    (folder / "shell.qml").write_text(SHELL)
    bin_dir = folder / "bin"
    bin_dir.mkdir()
    stub = bin_dir / "cortetsu-notifications"
    stub.write_text("#!/bin/sh\nexit 0\n")
    stub.chmod(0o755)
    env = {**os.environ, "QT_QPA_PLATFORM": "offscreen", "HOME": str(folder / "home"),
           "XDG_STATE_HOME": str(folder / "state"), "XDG_CACHE_HOME": str(folder / "cache"),
           "PATH": f"{bin_dir}:{os.environ['PATH']}"}
    env.pop("WAYLAND_DISPLAY", None)
    # A bare bus: no service activation, so no portal starts without a display.
    bus = folder / "bus.conf"
    bus.write_text('<!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-Bus Bus Configuration 1.0//EN" '
                   '"http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd"><busconfig><type>session</type>'
                   '<listen>unix:tmpdir=/tmp</listen><policy context="default"><allow send_destination="*"/>'
                   '<allow own="*"/></policy></busconfig>')
    result = subprocess.run(["dbus-run-session", f"--config-file={bus}", "--", "quickshell", "-p", str(folder / "shell.qml")],
                            env=env, capture_output=True, text=True, timeout=int(os.environ.get("T", 60)))
    output = result.stdout + result.stderr
    assert f"SIDEBAR_ACTIVE {COUNT}" in output, output
    assert "SIDEBAR_AFTER 0 0" in output, output
    loops = output.count("Binding loop")
    assert loops == 0, f"{loops} binding loops while clearing:\n{output}"
    for marker in ("TypeError", "ReferenceError", "Unable to assign", "is not a type"):
        assert marker not in output, output

print(f"PASS: clearing {COUNT} notifications with the centre open empties it without a binding loop")
