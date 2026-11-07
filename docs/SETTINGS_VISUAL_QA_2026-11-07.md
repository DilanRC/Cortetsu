# Settings visual comparison — 2026-11-07

The screenshots compare end-4's real `settings.qml` at commit
[`2f2a376fdb2ad738bf55f693dd0b474b64bb0ab8`](https://github.com/end-4/dots-hyprland/tree/2f2a376fdb2ad738bf55f693dd0b474b64bb0ab8)
with Cortetsu's real Settings runtime. The upstream repository identifies its
license as GPL-3.0; Cortetsu's implementation remains its own QML and services.
These screenshots document the design reference and are not source-code reuse.

Both applications ran in isolated environments. end-4 ran under a private
headless Wayland compositor at 1352 × 884; Cortetsu's Quickshell runtime ran
under its QML test harness at 1368 × 900. The size difference comes from the
outer window frame and means this is a composition review, not a pixel-diff
claim. Cortetsu screenshots use fixture data and do not represent live hardware
or the user's active session.

## Page pairs

| Page | end-4 | Cortetsu |
| --- | --- | --- |
| Quick Settings | ![end-4 Quick Settings](evidence/settings-end4-20261107/end4-quick.png) | ![Cortetsu Quick Settings](evidence/settings-end4-20261107/cortetsu-quick.png) |
| General | ![end-4 General](evidence/settings-end4-20261107/end4-general.png) | ![Cortetsu General](evidence/settings-end4-20261107/cortetsu-general.png) |
| Bar | ![end-4 Bar](evidence/settings-end4-20261107/end4-bar.png) | ![Cortetsu Bar](evidence/settings-end4-20261107/cortetsu-bar.png) |
| Background | ![end-4 Background](evidence/settings-end4-20261107/end4-background.png) | ![Cortetsu Background](evidence/settings-end4-20261107/cortetsu-background.png) |
| Interface | ![end-4 Interface](evidence/settings-end4-20261107/end4-interface.png) | ![Cortetsu Interface](evidence/settings-end4-20261107/cortetsu-interface.png) |
| Services | ![end-4 Services](evidence/settings-end4-20261107/end4-services.png) | ![Cortetsu Services](evidence/settings-end4-20261107/cortetsu-services.png) |
| Advanced | ![end-4 Advanced](evidence/settings-end4-20261107/end4-advanced.png) | ![Cortetsu Advanced](evidence/settings-end4-20261107/cortetsu-advanced.png) |
| About | ![end-4 About](evidence/settings-end4-20261107/end4-about.png) | ![Cortetsu About](evidence/settings-end4-20261107/cortetsu-about.png) |

## Product themes

Ink is shown in the Quick Settings pair above. The isolated runtime also
captured both non-default themes after selecting each one:

![Washi theme in Settings](evidence/settings-end4-20261107/cortetsu-washi.png)

![Kurogane theme in Settings](evidence/settings-end4-20261107/cortetsu-kurogane.png)

These pairs show the navigation rail, page headings and the first visible
controls in each destination. The Services pair is only its first scroll
viewport: its fixture has no live hardware, and the later Bluetooth,
automation, weather, recorder and screenshot groups are below that viewport.
The runtime test exercises those existing service sections separately. Cortetsu
uses its ink-blue materials, grouped service rows and text hierarchy instead of
copying end-4's monochrome treatment. Theme captures show Washi's warm paper
surfaces and Kurogane's compact steel surfaces; theme selection and restoration
are covered separately by the native runtime tests in [`SETTINGS.md`](SETTINGS.md).

## Verification

`test-cortetsu-settings-runtime.py` passed in isolated HOME/XDG directories and
rendered all eight pages at three supported sizes/schemes, plus the two product
themes and error/empty states. The slow native theme commit scenario now holds
its state-file lock until QML confirms that the progress-notice state reached
the Settings theme row. This removes a start-up timing race from the test
itself. The full run reports that Settings retains objects across palette and
preference changes, handles pending, failed and unavailable states, and works
with keyboard input. It also opened, browsed and closed the surface under a
private Weston compositor.

The full `./scripts/cortetsu test` run also exposed a missing `setShown` root
method in the isolated Bottom Hub function harness. The harness now supplies
that method and asserts that opening an attached control leaves the hub shown;
the direct regression script passes after the change.

The comparison certifies navigation, first-viewport page hierarchy and theme
presentation. It does not certify physical Wi-Fi/Bluetooth hardware or the
user's running Wayland session.
