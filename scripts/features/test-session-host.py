from pathlib import Path

repo = Path(__file__).resolve().parents[2]
for name in ("Wrapper.qml", "Content.qml"):
    source = (repo / "cortetsu/modules/session" / name).read_text(encoding="utf-8")
    for legacy in ("Caelestia", "GlobalConfig", "SessionManager", "qs.services", "qs.components", "Tokens", "Colours"):
        assert legacy not in source, f"{name}: {legacy}"
assert "systemctl" in (repo / "cortetsu/modules/session/Content.qml").read_text(encoding="utf-8")
content = (repo / "cortetsu/modules/session/Content.qml").read_text(encoding="utf-8")
assert "pendingAction" in content and "confirmTimer" in content
assert "Confirm %1" in content
print("PASS: session host uses first-party commands and state")
