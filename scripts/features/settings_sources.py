"""Source text of the Settings pages that are split across several QML files."""
from pathlib import Path

SETTINGS = Path(__file__).resolve().parents[2] / "cortetsu/modules/settings"
SYSTEM_COMPONENTS = ("PreferenceToggle", "StatusCard", "DomainHero", "ActionCard", "ShortcutRow")


def system_page_text() -> str:
    """SystemPage.qml, its sections and the components they share, as one string."""
    files = [
        SETTINGS / "SystemPage.qml",
        *sorted((SETTINGS / "sections").glob("*.qml")),
        *(SETTINGS / f"{name}.qml" for name in SYSTEM_COMPONENTS),
    ]
    return "\n".join(path.read_text(encoding="utf-8") for path in files)


def network_page_text() -> str:
    """NetworkPage.qml and the panels under network/, as one string."""
    files = [SETTINGS / "NetworkPage.qml", *sorted((SETTINGS / "network").glob("*.qml"))]
    return "\n".join(path.read_text(encoding="utf-8") for path in files)
