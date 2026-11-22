# Evidencias: cierre Premium sobria (2026-11-21)

Capturas del estado final. Origen de cada una:

- `*-realm.png`: Agent Realms (`cortetsu realm up .`, 1920×1080, escala 1,
  tema Ink), con el checkout de la revisión indicada en el registro. El realm
  no tiene NetworkManager, BlueZ, PipeWire ni backlight: esas superficies
  salen en sus estados «no disponible».
- `*-stage.png`: `scripts/verification/qml-stage.sh` (offscreen, bus y estado
  privados). Los avisos de `notifications-*` son reales, enviados con
  `notify-send` al servidor aislado. El render por software no pinta el
  Evolving Mark ni `MultiEffect` (carátulas).
- `settings-wifi-harness.png`: `test-cortetsu-settings-runtime.py` con
  `CORTETSU_RENDER_DIR`, datos de NetworkManager simulados por el arnés.

Reducidas a 960 px y 192 colores para el repositorio. Registro y estado de
cada requisito: `docs/roadmap/cortetsu-3.0/CIERRE_PREMIUM_SOBRIA.md`.
