#!/usr/bin/env python3
"""Guard the import boundary of Cortetsu's visible overlay hosts."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HOSTS = {
    "QsdHost.qml": ("../components", "../components/containers", "../services", "."),
    "SettingsHost.qml": ("../components", "../components/containers", "../services", "."),
    "LauncherHost.qml": ("../components/containers", "../services", "."),
    "DashboardHost.qml": ("../components", "../components/containers", "../services", "."),
    "SessionHost.qml": ("../components", "../components/containers", ".", "session"),
    "RetainedSurfacesHost.qml": (
        "../components",
        "../components/containers",
        ".",
        "overview",
        "clipboard",
        "hardware",
        "display",
        "wallpaper",
        "calendar",
    ),
}

for name, imports in HOSTS.items():
    path = ROOT / "cortetsu/modules" / name
    source = path.read_text(encoding="utf-8")
    assert "import qs." not in source, f"{name} reintroduced a compatibility import"
    assert "import Caelestia" not in source, f"{name} imports legacy ownership"
    for directory in imports:
        assert f'import "{directory}"' in source, f"{name} missing relative boundary {directory}"
    for marker in ("Variants {", "model: CortetsuScreens.screens", "WlrLayer.Overlay"):
        assert marker in source, f"{name} lost monitor-local overlay ownership: {marker}"

print(f"PASS: {len(HOSTS)} visible overlay hosts use explicit Cortetsu import boundaries")
