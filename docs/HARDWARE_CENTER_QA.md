# Hardware Center acceptance checklist

Run after `bash scripts/features/update-hardware-center.sh`.

## Automated

```fish
python3 scripts/features/validate-hardware-center.py
python3 scripts/features/diagnose-hardware-center.py
```

Expected: validator `status: OK`, live QML hashes `MATCH`, no Hardware Center QML errors.

## UI

- `Super+H` opens and toggles; `Esc`, close button and outside click close it.
- Empty space inside the panel never closes it.
- Keys `1` through `9` select the matching page and `0` opens Arranque.
- Tabs are as wide as their label; none is cut at 1280 px.
- Active Caelestia scheme recolours every page without hardcoded accents.

### 1 Resumen

- The verdict strip reads "Todo en orden" on an idle machine and shows the time of the reading.
- Under load (`stress-ng --cpu 0 --timeout 120`), CPU usage and its history move every 1.5 s without the page flickering.
- A flagged item appears as a row in the strip and opens its page on click or `Enter`.
- Every block shows its destination on hover and on `Tab` focus, and opens it.
- `Tab` goes header, tabs, then blocks top to bottom and left to right; `Shift+Tab` goes back.
- With the probe renamed (`mv ~/.local/bin/cortetsu-hardware-probe{,.off}`) and the panel reopened after a shell restart: error state with Reintentar. Renamed while open: "Lecturas detenidas", last reading dimmed. Restoring the file and pressing Reintentar recovers.
- On battery below 20 %: the battery row appears and opens Energía.
- Both monitors, and scale 1 and 1.25: nothing overlaps or is cut.

### 2 Rendimiento

- Histories fill only while Hardware Center is open.
- CPU cycles Total and every logical core.
- RAM toggles Cache/Swap.
- Network and disk auto-scale; graphs show min/avg/max and current scale.
- A history shorter than the window starts at the right edge.

### 3 Procesos

- Filter accepts multiple terms.
- CPU/RAM/PID sorting works.
- `123 / %` changes CPU/RAM representation.
- List pause freezes only the list.
- Pausar/Reanudar, Interrumpir and Terminar work on a disposable process; Forzar cierre asks for a second press within four seconds.
- `Up`/`Down`/`PageUp`/`PageDown` move the selection and the list follows it.

### 4 Sensores

- Per-core bars update.
- CPU/GPU temperature and power fields degrade cleanly when unavailable.
- Fan RPM values render without duplicate UI breakage.

### 5 E/S

- Root filesystem usage renders.
- Physical NVMe model/device and throughput/IOPS/totals render.
- Network interface, IPv4, MAC, SSID, signal and bitrate render when available.

### 6 Energía

- Available `powerprofilesctl` profiles are selectable.
- Selected profile is verified after change.
- CPU `amd-pstate`/governor/EPP/platform-profile state renders.
- AMD runtime power state and NVIDIA P-state/clocks/power render.

### 7 Automatización

- Starts disabled on first install.
- Updating Cortetsu never enables it automatically.
- AC, battery and low-battery profiles are configurable.
- Low threshold increments/decrements in 5% steps.
- `Apply current rule once` works while disabled without enabling the service.
- Enabling starts the user service; disabling stops and disables it.
- Recent rule/profile events appear and can be cleared.

### 8 Consumo

- Battery/CPU/AMD/NVIDIA power histories populate while the page exists.
- Battery energy and health render.
- Remaining or charge-time estimate appears only when the kernel exposes usable draw data.
- Missing CPU package power is shown as unavailable, not fabricated.

## Resource check

After closing Hardware Center:

```fish
ps -ef | grep -E 'cortetsu-hardware-(probe|power)' | grep -v grep
```

Expected: no persistent main/power probe processes.

If Auto is disabled:

```fish
systemctl --user is-active cortetsu-power-auto.service
```

Expected: `inactive`.
