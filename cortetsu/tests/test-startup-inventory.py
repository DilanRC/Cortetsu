#!/usr/bin/env python3
"""Temporary-home checks for startup inventory and reversible toggles."""
import importlib.machinery
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import tempfile

SCRIPT = Path(__file__).resolve().parents[1] / "bin/cortetsu-startup"
loader = importlib.machinery.SourceFileLoader("cortetsu_startup", str(SCRIPT))
spec = importlib.util.spec_from_loader(loader.name, loader)
app = importlib.util.module_from_spec(spec)
loader.exec_module(app)


def put(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def qml_process_starts(path: Path) -> list[str]:
    """Find automatic Process and detached-command starts, ignoring strings/comments."""
    source = path.read_text(encoding="utf-8")
    masked = list(source)
    index = 0
    quote = None
    while index < len(source):
        char = source[index]
        next_char = source[index + 1] if index + 1 < len(source) else ""
        if quote:
            if char == "\\":
                for offset in range(index, min(index + 2, len(source))):
                    if source[offset] != "\n":
                        masked[offset] = " "
                index += 2
                continue
            if char == quote:
                quote = None
            if char != "\n":
                masked[index] = " "
        elif char in {"'", '"', "`"}:
            quote = char
            masked[index] = " "
        elif char == "/" and next_char == "/":
            while index < len(source) and source[index] != "\n":
                masked[index] = " "
                index += 1
            continue
        elif char == "/" and next_char == "*":
            masked[index] = masked[index + 1] = " "
            index += 2
            while index < len(source) and source[index:index + 2] != "*/":
                if source[index] != "\n":
                    masked[index] = " "
                index += 1
            if index < len(source):
                masked[index] = masked[index + 1] = " "
                index += 2
            continue
        index += 1
    code = "".join(masked)
    def blocks(type_name: str):
        for match in re.finditer(rf"\b{re.escape(type_name)}\s*\{{", code):
            depth = 1
            cursor = match.end()
            while cursor < len(code) and depth:
                if code[cursor] == "{":
                    depth += 1
                elif code[cursor] == "}":
                    depth -= 1
                cursor += 1
            yield match.start(), code[match.end():cursor - 1]

    def marker_at(offset: int) -> str:
        preceding = [line for line in source[:offset].splitlines() if line.strip()]
        marker = next((found for line in reversed(preceding[-2:])
                       if (found := re.search(r"//\s*startup inventory:\s*(cortetsu:[\w-]+)", line))), None)
        return marker.group(1) if marker else ""

    processes = {}
    starts = []
    for offset, block in blocks("Process"):
        id_match = re.search(r"\bid\s*:\s*([A-Za-z_]\w*)", block)
        prefix = code[max(0, offset - 100):offset]
        property_match = re.search(r"\bproperty\s+Process\s+([A-Za-z_]\w*)\s*:\s*$", prefix)
        process_id = id_match.group(1) if id_match else property_match.group(1) if property_match else ""
        if process_id:
            processes[process_id] = offset
        running = re.search(r"\brunning\s*:\s*([^;\n}]+)", block)
        bound_start = bool(running and running.group(1).strip() not in {"false", "0"})
        completed_start = bool(re.search(r"Component\.onCompleted\s*:\s*running\s*=\s*true", block))
        if bound_start or completed_start:
            starts.append(marker_at(offset) or f"UNREGISTERED:{process_id}")

    functions = {}
    function_pattern = re.compile(r"\bfunction\s+([A-Za-z_]\w*)\s*\([^)]*\)\s*(?:\:[^{\n]+)?\{")
    for match in function_pattern.finditer(code):
        depth = 1
        cursor = match.end()
        while cursor < len(code) and depth:
            if code[cursor] == "{":
                depth += 1
            elif code[cursor] == "}":
                depth -= 1
            cursor += 1
        functions.setdefault(match.group(1), []).append(code[match.end():cursor - 1])

    completion_bodies = []
    for match in re.finditer(r"\bComponent\.onCompleted\s*:", code):
        cursor = match.end()
        while cursor < len(code) and code[cursor].isspace():
            cursor += 1
        if cursor < len(code) and code[cursor] == "{":
            depth = 1
            end = cursor + 1
            while end < len(code) and depth:
                if code[end] == "{":
                    depth += 1
                elif code[end] == "}":
                    depth -= 1
                end += 1
            completion_bodies.append((match.start(), code[cursor + 1:end - 1]))
        else:
            end = code.find("\n", cursor)
            completion_bodies.append((match.start(), code[cursor:end if end >= 0 else len(code)]))

    started_timers = set()
    timers = list(blocks("Timer"))
    timer_ids = {
        match.group(1)
        for _, block in timers
        if (match := re.search(r"\bid\s*:\s*([A-Za-z_]\w*)", block))
    }

    def directly_starts_process(body: str) -> bool:
        return bool(
            re.search(r"Quickshell\.execDetached\s*\(", body)
            or any(re.search(rf"\b{re.escape(process_id)}\.(?:exec\s*\(|running\s*=\s*true)", body)
                   for process_id in processes)
            or any(re.search(rf"\b{re.escape(timer_id)}\.(?:start\s*\(|running\s*=\s*true)", body)
                   for timer_id in timer_ids)
        )

    relevant_functions = {
        name for name, bodies in functions.items()
        if any(directly_starts_process(body) for body in bodies)
    }
    changed = True
    while changed:
        changed = False
        for name, bodies in functions.items():
            if name in relevant_functions:
                continue
            if any(any(re.search(rf"\b{re.escape(target)}\s*\(", body)
                       for target in relevant_functions) for body in bodies):
                relevant_functions.add(name)
                changed = True

    def expanded(body: str) -> str:
        seen = set()
        pending = [body]
        result = []
        while pending:
            current = pending.pop()
            result.append(current)
            for name in relevant_functions:
                if name not in seen and re.search(rf"\b{re.escape(name)}\s*\(", current):
                    seen.add(name)
                    pending.extend(functions[name])
        return "\n".join(result)

    for _, body in completion_bodies:
        body = expanded(body)
        for timer_offset, block in timers:
            timer_id = re.search(r"\bid\s*:\s*([A-Za-z_]\w*)", block)
            if timer_id and re.search(rf"\b{re.escape(timer_id.group(1))}\.(?:start\s*\(|running\s*=\s*true)", body):
                started_timers.add(timer_id.group(1))

    startup_callbacks = list(completion_bodies)
    for offset, block in timers:
        running = re.search(r"\brunning\s*:\s*([^;\n}]+)", block)
        timer_id = re.search(r"\bid\s*:\s*([A-Za-z_]\w*)", block)
        active = bool(running and running.group(1).strip() not in {"false", "0"})
        active = active or bool(timer_id and timer_id.group(1) in started_timers)
        if active and re.search(r"\bonTriggered\s*:", block):
            startup_callbacks.append((offset, expanded(block)))

    startup_callbacks = [(offset, expanded(body)) for offset, body in startup_callbacks]

    for callback_offset, body in startup_callbacks:
        for process_id, process_offset in processes.items():
            if re.search(rf"\b{re.escape(process_id)}\.(?:exec\s*\(|running\s*=\s*true)", body):
                starts.append(marker_at(process_offset) or f"UNREGISTERED:{process_id}")
        if re.search(r"Quickshell\.execDetached\s*\(", body):
            starts.append(marker_at(callback_offset) or "UNREGISTERED:execDetached")

    return list(dict.fromkeys(starts))


with tempfile.TemporaryDirectory(prefix="cortetsu-startup-test-") as temp:
    base = Path(temp)
    startup_forms = base / "startup-forms.qml"
    put(startup_forms, """Scope {
    property var indirectCommand: ["daemon", "--watch"]
    // startup inventory: cortetsu:fixture-bound
    Process { id: bound; command: indirectCommand; running: config.enabled }
    // startup inventory: cortetsu:fixture-completed
    Process { id: completed; command: indirectCommand }
    // startup inventory: cortetsu:fixture-timer
    Process { id: timerChild; command: indirectCommand }
    Timer { id: launchTimer; running: true; onTriggered: timerChild.exec() }
    // startup inventory: cortetsu:fixture-indirect
    Process { id: indirectProcess; command: indirectCommand }
    Timer { id: indirectTimer; onTriggered: launchIndirectProcess() }
    function launchIndirectProcess(): void { indirectProcess.exec(); }
    function armIndirectTimer(): void { indirectTimer.start(); }
    function launchFromHelper(): void { completed.exec(); }
    function onDemand(): void { completed.exec(); }
    // startup inventory: cortetsu:fixture-detached
    Component.onCompleted: {
        completed.running = true
        launchFromHelper()
        armIndirectTimer()
        Quickshell.execDetached(indirectCommand)
    }
}
""")
    assert sorted(qml_process_starts(startup_forms)) == sorted([
        "cortetsu:fixture-bound", "cortetsu:fixture-completed",
        "cortetsu:fixture-timer", "cortetsu:fixture-detached", "cortetsu:fixture-indirect",
    ]), f"startup drift checks missed a launch form: {qml_process_starts(startup_forms)}"
    home = base / "home"
    user_config = home / ".config"
    system_config = base / "etc/xdg"
    os.environ.update({
        "HOME": str(home), "XDG_CONFIG_HOME": str(user_config),
        "XDG_STATE_HOME": str(home / ".local/state"),
        "XDG_CONFIG_DIRS": str(system_config), "XDG_CURRENT_DESKTOP": "Hyprland",
    })
    put(user_config / "autostart/user.desktop", "[Desktop Entry]\nName=User App\nExec=user-app --background\nTryExec=/bin/sh\n")
    put(user_config / "autostart/hidden.desktop", "[Desktop Entry]\nName=Hidden\nExec=hidden\nHidden=true\n")
    put(user_config / "autostart/missing.desktop", "[Desktop Entry]\nName=Missing\nExec=missing\nTryExec=missing-cortetsu-test-binary\n")
    put(user_config / "autostart/only.desktop", "[Desktop Entry]\nName=Only GNOME\nExec=only\nOnlyShowIn=GNOME;\n")
    put(user_config / "autostart/not.desktop", "[Desktop Entry]\nName=Not Hyprland\nExec=not\nNotShowIn=Hyprland;\n")
    put(system_config / "autostart/global.desktop", "[Desktop Entry]\nName=Global\nExec=global\nTryExec=/bin/sh\n")
    put(user_config / "autostart/global.desktop", "[Desktop Entry]\nName=Global disabled\nExec=global\nHidden=true\n")
    put(user_config / "hypr/hyprland.lua", 'hl.on("hyprland.start", function()\n    hl.exec_cmd("user-app --background")\n    hl.exec_cmd("systemctl --user start enabled.service")\n    hl.exec_cmd("systemctl --user start work.service")\nend)\n')
    entries = {item["id"]: item for item in app.xdg_entries()}
    assert entries["xdg:user.desktop"]["configured"] is True
    assert entries["xdg:hidden.desktop"]["configured"] is False
    assert entries["xdg:missing.desktop"]["eligible"] is False
    assert entries["xdg:only.desktop"]["eligible"] is False
    assert entries["xdg:not.desktop"]["eligible"] is False
    assert entries["xdg:global.desktop"]["sourceType"] == "xdg-user"
    assert entries["xdg:global.desktop"]["configured"] is False
    assert app.duplicate_keys({"sourceType": "xdg-system", "configured": True, "eligible": False, "command": "user-app --background"}) == []
    lookup = app.user_unit_command_lookup([
        {"_unit": "audio.service", "_user": True, "command": "user-audio --start"},
        {"_unit": "audio.service", "_user": False, "command": "system-audio --start"},
    ])
    assert lookup["audio.service"] == [app.command_key("user-audio --start")]

    expected_states = {
        "enabled": ("persistent", True, True, True, False),
        "linked": ("special", False, False, False, False),
        "enabled-runtime": ("runtime", True, True, False, True),
        "linked-runtime": ("special", False, False, False, False),
        "disabled": ("disabled", False, True, False, False),
        "static": ("special", False, False, False, False),
        "indirect": ("special", False, False, False, False),
        "generated": ("special", False, False, False, False),
        "transient": ("special", False, False, False, False),
        "alias": ("special", False, False, False, False),
        "masked": ("special", False, False, False, False),
        "bad": ("special", False, False, False, False),
    }
    for unit_state, expected in expected_states.items():
        normalized = app.normalize_unit_state(unit_state)
        assert (normalized["category"], normalized["configured"], normalized["modifiable"],
                normalized["persistent"], normalized["runtime"]) == expected
    assert app.normalize_unit_state("linked")["label"] == "Enlazada; disponible, sin autoinicio"
    assert app.normalize_unit_state("linked-runtime")["label"] == (
        "Enlazada esta sesión; disponible, sin autoinicio")
    assert app.process_is_running(["find", "*", "-type", "f"]) is None
    assert app.process_is_running(["nmcli", "monitor"]) is None
    script_path = base / "bin/cortetsu-startup"
    script_path.parent.mkdir(parents=True)
    script_path.write_text("#!/usr/bin/env python3\n", encoding="utf-8")
    native_path = base / "native/cortetsu-startup"
    native_path.parent.mkdir(parents=True)
    native_path.symlink_to(os.path.realpath(shutil.which("sleep")))
    fake_proc = base / "proc"
    (fake_proc / "123").mkdir(parents=True)
    (fake_proc / "123/cmdline").write_bytes(os.fsencode(native_path) + b"\0scan\0")
    (fake_proc / "123/exe").symlink_to(os.path.realpath(shutil.which("sleep")))
    assert app.process_is_running(
        ["cortetsu-startup", "scan"], fake_proc, executable_path=native_path) is True
    assert app.process_is_running(
        ["cortetsu-startup", "scan"], fake_proc,
        executable_path=base / "other/cortetsu-startup") is False
    direct_spoof_proc = base / "direct-spoof-proc"
    (direct_spoof_proc / "125").mkdir(parents=True)
    (direct_spoof_proc / "125/cmdline").write_bytes(os.fsencode(native_path) + b"\0scan\0")
    (direct_spoof_proc / "125/exe").symlink_to(os.path.realpath(shutil.which("cat")))
    assert app.process_is_running(
        ["cortetsu-startup", "scan"], direct_spoof_proc, executable_path=native_path) is False
    assert app.process_is_running(
        ["cortetsu-startup", "stop"], fake_proc, executable_path=native_path) is False
    assert app.process_is_running(["cortetsu-startup", "scan"], fake_proc, unambiguous=False) is None
    fake_script_proc = base / "script-proc"
    (fake_script_proc / "124").mkdir(parents=True)
    (fake_script_proc / "124/cmdline").write_bytes(
        b"/usr/bin/python3\0" + os.fsencode(script_path) + b"\0scan\0")
    python_path = Path(shutil.which("python3")).resolve()
    (fake_script_proc / "124/exe").symlink_to(python_path)
    assert app.process_is_running(
        ["cortetsu-startup", "scan"], fake_script_proc, executable_path=script_path) is True
    assert app.process_is_running(
        ["cortetsu-startup", "scan"], fake_script_proc,
        executable_path=base / "other/cortetsu-startup") is False
    self_proc = base / "self-proc" / str(os.getpid())
    self_proc.mkdir(parents=True)
    (self_proc / "cmdline").write_bytes(
        b"/usr/bin/python3\0" + os.fsencode(script_path) + b"\0scan\0")
    (self_proc / "exe").symlink_to(python_path)
    assert app.process_is_running(
        ["cortetsu-startup", "scan"], self_proc.parent, executable_path=script_path) is False
    script_spoof_proc = base / "script-spoof-proc"
    (script_spoof_proc / "126").mkdir(parents=True)
    (script_spoof_proc / "126/cmdline").write_bytes(
        b"/usr/bin/python3\0" + os.fsencode(script_path) + b"\0scan\0")
    (script_spoof_proc / "126/exe").symlink_to(os.path.realpath(shutil.which("cat")))
    assert app.process_is_running(
        ["cortetsu-startup", "scan"], script_spoof_proc, executable_path=script_path) is False
    assert app.activation_reason("wanted.service", {"WantedBy": "default.target"}, "enabled") == (
        "Instalada para iniciarse con default.target", "target")
    assert app.activation_reason("socket.service", {"TriggeredBy": "foo.socket"}, "static") == (
        "Puede activarse por socket foo.socket; no se confirma que lo haya iniciado ahora.", "activator")
    assert app.activation_reason("timer.service", {"TriggeredBy": "foo.timer"}, "static") == (
        "Programada por timer foo.timer; no se confirma que lo haya iniciado ahora.", "activator")
    assert app.activation_reason("dependency.service", {"BoundBy": "consumer.service"}, "static") == (
        "Puede iniciarse por dependencia de consumer.service; la causalidad de esta ejecución no está confirmada.",
        "dependency")
    assert app.activation_reason("part-of.service", {"ConsistsOf": "parent.service"}, "static")[1] == "unknown"
    assert app.activation_reason("unknown.service", {}, "disabled")[1] == "unknown"
    assert app.activation_reason("manual.service", {"ActiveState": "active"}, "disabled") == (
        "Activa; inicio manual o activador exacto no determinado.", "unknown")
    assert app.activation_reason("linked.service", {"WantedBy": "default.target"}, "linked") == (
        "Unidad enlazada para disponibilidad; no está habilitada para inicio automático.", "unknown")
    assert {entry["startupPhase"] for entry in app.CORTETSU_STARTUP} == {"always-on", "conditional", "on-demand"}
    phases = {entry["id"]: entry["startupPhase"] for entry in app.CORTETSU_STARTUP}
    assert phases["cortetsu:pomodoro"] == "always-on"
    assert phases["cortetsu:spectrum"] == "conditional"
    assert phases["cortetsu:brightness-maximum"] == "conditional"
    assert phases["cortetsu:nmcli-monitor"] == phases["cortetsu:vpn-monitor"] == "on-demand"
    assert phases["cortetsu:wallpaper-scan"] == "always-on"
    assert phases["cortetsu:battery-notification"] == phases["cortetsu:battery-hibernate"] == "conditional"
    assert phases["cortetsu:hardware-startup-scan"] == "on-demand"
    startup_rows = {entry["id"]: entry for entry in app.cortetsu_entries()}
    assert all(entry["configured"] == (entry["startupPhase"] != "on-demand")
               for entry in startup_rows.values())
    assert all(entry["startupState"] == entry["startupPhase"] for entry in startup_rows.values())
    assert startup_rows["cortetsu:hardware-power-probe"]["running"] is None
    assert startup_rows["cortetsu:hardware-energy-probe"]["running"] is None
    assert all("eligible" not in entry for entry in startup_rows.values())
    assert '"configured": component["startupPhase"] != "on-demand"' in SCRIPT.read_text(encoding="utf-8")
    assert {entry["id"] for entry in app.CORTETSU_STARTUP} == {
        "cortetsu:pomodoro", "cortetsu:wallpaper-scan", "cortetsu:battery-notification",
        "cortetsu:battery-hibernate", "cortetsu:spectrum", "cortetsu:nmcli-monitor",
        "cortetsu:nmcli-command", "cortetsu:vpn-monitor", "cortetsu:vpn-status",
        "cortetsu:brightness-discovery", "cortetsu:brightness-maximum", "cortetsu:nvibrant-query",
        "cortetsu:settings-network-query", "cortetsu:settings-active-network-query",
        "cortetsu:cpu-temperature", "cortetsu:gpu-probe", "cortetsu:storage-probe",
        "cortetsu:network-usage-probe", "cortetsu:recorder-status", "cortetsu:lock-keyboard-probe",
        "cortetsu:about-quickshell-version", "cortetsu:about-cortetsu-version",
        "cortetsu:launcher-scheme-list", "cortetsu:launcher-scheme-current", "cortetsu:calendar-sync",
        "cortetsu:display-presets", "cortetsu:display-preview-status", "cortetsu:hardware-probe",
        "cortetsu:hardware-power-probe", "cortetsu:hardware-power-automation-status",
        "cortetsu:hardware-keybind-list", "cortetsu:hardware-energy-probe", "cortetsu:hardware-startup-scan",
        "cortetsu:display-calibration-control",
        "cortetsu:session-sleep-monitor",
    }
    for entry in app.CORTETSU_STARTUP:
        source = Path(__file__).resolve().parents[1] / entry["source"]
        source_text = source.read_text(encoding="utf-8")
        assert source.is_file()
        if entry["command"]:
            assert entry["command"][0] in source_text, entry["id"]
        else:
            assert entry["commandSource"] in source_text, entry["id"]
        if entry["qmlId"]:
            assert re.search(rf"\b(?:id\s*:\s*|property\s+Process\s+){re.escape(entry['qmlId'])}\b", source_text), entry["id"]
    repo_root = Path(__file__).resolve().parents[2]
    declarations = {}
    for source in (repo_root / "cortetsu").rglob("*.qml"):
        starts = qml_process_starts(source)
        if starts:
            declarations[source.relative_to(repo_root).as_posix()] = sorted(starts)
    registry = {}
    for entry in app.CORTETSU_STARTUP:
        registry.setdefault("cortetsu/" + entry["source"], []).append(entry["id"])
    registry = {source: sorted(ids) for source, ids in registry.items()}
    assert declarations == registry, (declarations, registry)
    startup_page = (repo_root / "cortetsu/modules/hardware/StartupPage.qml").read_text(encoding="utf-8")
    assert 'return entry.startupState ?? (entry.configured ? "persistent" : "disabled")' in startup_page
    assert "root.stateCategory(entry)" in startup_page
    assert "root.stateLabel(modelData)" in startup_page
    assert '"always-on", "conditional", "on-demand"' in startup_page
    assert 'root.stateCategory(entry) === "always-on"' in startup_page
    assert 'root.stateCategory(entry) === "conditional"' in startup_page
    assert 'root.stateCategory(entry) === "special"' in startup_page
    assert '["all", "persistent", "runtime", "disabled", "special", "always-on", "conditional", "on-demand"]' in startup_page
    assert "running: true" not in SCRIPT.read_text(encoding="utf-8")

    # A systemctl shim isolates all unit operations from the host.
    fake_bin = base / "bin"
    put(fake_bin / "systemctl", """#!/bin/sh
if [ "$1" = "--user" ]; then shift; fi
case "$1" in
  list-unit-files) cat "$UNIT_STATE" ;;
  list-units) printf 'transient.service loaded active running Temporary\\n' ;;
  show)
    shift
    for unit in "$@"; do
      case "$unit" in
        work.service)
          active=active
          [ ! -f "$STOPPED" ] || active=inactive
          printf 'Id=work.service\\nDescription=Worker\\nActiveState=%s\\nUnitFileState=disabled\\nFragmentPath=/tmp/work.service\\nWantedBy=default.target\\nExecStart={ path=user-app ; argv[]=user-app --background ; ignore_errors=no ; }\\n\\n' "$active"
          ;;
        enabled.service) printf 'Id=enabled.service\\nDescription=Enabled helper\\nActiveState=active\\nUnitFileState=enabled\\nExecStart={ path=user-app ; argv[]=user-app --background ; ignore_errors=no ; }\\n\\n' ;;
        runtime.service) printf 'Id=runtime.service\\nDescription=Runtime helper\\nActiveState=inactive\\nUnitFileState=enabled-runtime\\nWantedBy=default.target\\n\\n' ;;
        linked.service) printf 'Id=linked.service\\nDescription=Linked helper\\nActiveState=inactive\\nUnitFileState=linked\\nWantedBy=default.target\\n\\n' ;;
        linked-runtime.service) printf 'Id=linked-runtime.service\\nDescription=Linked runtime helper\\nActiveState=inactive\\nUnitFileState=linked-runtime\\nWantedBy=default.target\\n\\n' ;;
        target.service) printf 'Id=target.service\\nDescription=Target helper\\nActiveState=inactive\\nUnitFileState=enabled\\nWantedBy=default.target\\n\\n' ;;
        socket-activated.service) printf 'Id=socket-activated.service\\nDescription=Socket helper\\nActiveState=inactive\\nUnitFileState=static\\nTriggeredBy=fixture.socket\\n\\n' ;;
        timer-activated.service) printf 'Id=timer-activated.service\\nDescription=Timer helper\\nActiveState=inactive\\nUnitFileState=static\\nTriggeredBy=fixture.timer\\n\\n' ;;
        clock.timer) printf 'Id=clock.timer\\nDescription=Clock\\nActiveState=inactive\\nUnitFileState=static\\n\\n' ;;
        wait.socket) printf 'Id=wait.socket\\nDescription=Socket\\nActiveState=inactive\\nUnitFileState=disabled\\n\\n' ;;
        generated.service) printf 'Id=generated.service\\nDescription=Generated\\nActiveState=inactive\\nUnitFileState=generated\\n\\n' ;;
        alias.service) printf 'Id=alias.service\\nDescription=Alias\\nActiveState=inactive\\nUnitFileState=alias\\n\\n' ;;
        indirect.service) printf 'Id=indirect.service\\nDescription=Indirect\\nActiveState=inactive\\nUnitFileState=indirect\\n\\n' ;;
        transient.service) printf 'Id=transient.service\\nDescription=Transient\\nActiveState=active\\nUnitFileState=transient\\n\\n' ;;
      esac
    done
    ;;
  enable) sed -i 's/work.service disabled/work.service enabled/' "$UNIT_STATE" ;;
  disable) sed -i 's/work.service enabled/work.service disabled/' "$UNIT_STATE" ;;
  stop) touch "$STOPPED" ;;
esac
""")

    (fake_bin / "systemctl").chmod(0o755)
    state = base / "units"
    state.write_text("work.service disabled enabled\nenabled.service enabled enabled\nclock.timer static -\nwait.socket disabled enabled\ngenerated.service generated -\nalias.service alias -\nindirect.service indirect -\n", encoding="utf-8")
    with state.open("a", encoding="utf-8") as unit_file:
        unit_file.write("runtime.service enabled-runtime enabled\nlinked-runtime.service linked-runtime -\ntarget.service enabled enabled\nsocket-activated.service static -\ntimer-activated.service static -\n")
        unit_file.write("linked.service linked enabled\n")
    env_path = os.environ.get("PATH", "")
    os.environ["PATH"] = str(fake_bin) + os.pathsep + env_path
    os.environ["UNIT_STATE"] = str(state)
    stopped = base / "stopped"
    os.environ["STOPPED"] = str(stopped)
    outside = base / "outside.desktop"
    put(outside, "[Desktop Entry]\nName=Outside\nExec=outside\n")
    os.symlink(outside, user_config / "autostart/link.desktop")
    try:
        app.action("xdg:link.desktop", "disable")
        raise AssertionError("symlinked desktop file must be rejected")
    except ValueError as error:
        assert "enlaces simbólicos" in str(error)
    # Enabling and disabling a global entry uses a user override only.
    (user_config / "autostart/global.desktop").unlink()
    result = app.action("xdg:global.desktop", "disable")
    assert result["ok"] and result["entry"]["configured"] is False
    assert (system_config / "autostart/global.desktop").read_text().find("Hidden=") == -1
    app.action("xdg:global.desktop", "enable")
    assert {item["id"]: item for item in app.xdg_entries()}["xdg:global.desktop"]["configured"] is True
    units = {item["id"]: item for item in app.systemd_entries(True)}
    assert units["user-unit:runtime.service"]["startupState"] == "runtime"
    assert units["user-unit:runtime.service"]["configured"] is True
    assert units["user-unit:runtime.service"]["runtimeOnly"] is True
    for linked_id, linked_label in (("linked.service", "Enlazada; disponible, sin autoinicio"),
                                    ("linked-runtime.service", "Enlazada esta sesión; disponible, sin autoinicio")):
        linked = units["user-unit:" + linked_id]
        assert linked["startupState"] == "special"
        assert linked["configured"] is False
        assert linked["runtimeOnly"] is False
        assert linked["modifiable"] is False
        assert linked["startupLabel"] == linked_label
        assert linked["reason"] == (
            "Unidad enlazada para disponibilidad; no está habilitada para inicio automático.")
    assert units["user-unit:target.service"]["reason"] == "Instalada para iniciarse con default.target"
    assert units["user-unit:socket-activated.service"]["reason"] == (
        "Puede activarse por socket fixture.socket; no se confirma que lo haya iniciado ahora.")
    assert units["user-unit:timer-activated.service"]["reason"] == (
        "Programada por timer fixture.timer; no se confirma que lo haya iniciado ahora.")
    assert units["user-unit:work.service"]["configured"] is False
    assert units["user-unit:work.service"]["running"] is True
    assert units["user-unit:clock.timer"]["modifiable"] is False
    assert units["user-unit:wait.socket"]["modifiable"] is True
    assert units["user-unit:generated.service"]["modifiable"] is False
    assert units["user-unit:alias.service"]["modifiable"] is False
    assert units["user-unit:indirect.service"]["modifiable"] is False
    assert units["user-unit:transient.service"]["unitState"] == "transient"
    assert units["user-unit:transient.service"]["running"] is True
    assert units["user-unit:transient.service"]["modifiable"] is False
    assert len([item for item in units.values() if item["id"] == "user-unit:work.service"]) == 1
    scanned = {item["id"]: item for item in app.scan()}
    assert scanned["hyprland:" + str(home / ".config/hypr/hyprland.lua") + ":2"]["command"] == "user-app --background"
    assert scanned["hyprland:" + str(home / ".config/hypr/hyprland.lua") + ":2"]["modifiable"] is False
    assert scanned["hyprland:" + str(home / ".config/hypr/hyprland.lua") + ":3"]["duplicateCount"] == 5
    assert scanned["hyprland:" + str(home / ".config/hypr/hyprland.lua") + ":4"]["duplicateCount"] == 5
    assert scanned["user-unit:work.service"]["duplicateCount"] == 0
    assert scanned["user-unit:enabled.service"]["duplicateCount"] == 5
    assert scanned["xdg:user.desktop"]["duplicateCount"] == 5
    assert all(not item["modifiable"] for item in app.systemd_entries(False))
    stopped_result = app.action("user-unit:work.service", "stop")
    assert stopped_result["ok"] and stopped_result["entry"]["running"] is False
    assert stopped_result["entry"]["configured"] is False
    app.action("user-unit:work.service", "enable")
    assert {item["id"]: item for item in app.systemd_entries(True)}["user-unit:work.service"]["configured"] is True
    app.action("user-unit:work.service", "disable")
    assert {item["id"]: item for item in app.systemd_entries(True)}["user-unit:work.service"]["configured"] is False
    changes = [json.loads(line) for line in (home / ".local/state/cortetsu/startup/changes.jsonl").read_text().splitlines()]
    assert any(change.get("action") == "stop" and change.get("oldState") == "running" and change.get("newState") == "stopped" for change in changes)

print("PASS: XDG overrides and user systemd toggles use isolated fixtures")
