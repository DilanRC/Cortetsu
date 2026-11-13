# Inventario de QML de Cortetsu

Generado por `scripts/verification/qml-inventory.py`; no se edita a mano.
`usos` cuenta los QML que no son pruebas y nombran el tipo; `pruebas`, los archivos de
prueba que lo nombran. `dead` es un QML propio que nada referencia.

| Clase | Archivos |
| --- | --- |
| compat/upstream | 7 |
| dead | 7 |
| generated | 1 |
| harness/test | 64 |
| owned-first-party | 331 |

| Archivo | Clase | Superficie | Líneas | Usos | Servicios | Interacción | Estados | Pruebas |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `ConnectivityWifiFixture.qml` | harness/test | (raíz) | 45 | 0 | - | - | - | 1 |
| `ExclusionsFixture.qml` | harness/test | (raíz) | 35 | 0 | - | - | - | 0 |
| `ScreenShareFixture.qml` | harness/test | (raíz) | 101 | 0 | - | - | deshabilitado | 0 |
| `SecretPromptFixture.qml` | harness/test | (raíz) | 148 | 0 | - | - | - | 0 |
| `StartupPageFixture.qml` | harness/test | (raíz) | 54 | 0 | - | - | deshabilitado | 0 |
| `WallpaperFirstSelectFixture.qml` | harness/test | (raíz) | 100 | 0 | - | - | - | 1 |
| `base/modules/bar/popouts/Content.qml` | compat/upstream | base | 235 | 20 | CortetsuTokens | - | movimiento | 74 |
| `base/modules/bar/popouts/PopoutState.qml` | compat/upstream | base | 14 | 4 | - | - | - | 2 |
| `base/modules/bar/popouts/kblayout/KbLayoutModel.qml` | compat/upstream | base | 221 | 1 | - | - | - | 0 |
| `base/modules/lock/Pam.qml` | compat/upstream | base | 308 | 2 | - | - | deshabilitado | 5 |
| `base/services/VPN.qml` | compat/upstream | base | 961 | 1 | CortetsuToaster | - | - | 5 |
| `base/utils/Searcher.qml` | compat/upstream | base | 56 | 3 | - | - | - | 1 |
| `base/utils/Strings.qml` | compat/upstream | base | 27 | 3 | - | - | - | 2 |
| `components/Anim.qml` | owned-first-party | components | 14 | 1 | - | - | movimiento | 2 |
| `components/CAnim.qml` | dead | components | 9 | 0 | - | - | movimiento | 1 |
| `components/CortetsuActionRow.qml` | owned-first-party | components | 159 | 1 | - | teclado, ratón | deshabilitado, movimiento | 5 |
| `components/CortetsuActionTile.qml` | owned-first-party | components | 145 | 1 | - | teclado, ratón | deshabilitado, movimiento | 10 |
| `components/CortetsuBrushStroke.qml` | owned-first-party | components | 30 | 6 | - | - | - | 1 |
| `components/CortetsuButton.qml` | owned-first-party | components | 132 | 48 | - | teclado, ratón | deshabilitado, movimiento | 21 |
| `components/CortetsuChoiceCard.qml` | owned-first-party | components | 152 | 1 | - | teclado, ratón | deshabilitado, movimiento | 4 |
| `components/CortetsuDivider.qml` | owned-first-party | components | 15 | 3 | - | - | - | 1 |
| `components/CortetsuEnso.qml` | owned-first-party | components | 75 | 1 | - | - | movimiento | 0 |
| `components/CortetsuEvolvingMark.qml` | owned-first-party | components | 131 | 7 | - | - | deshabilitado, movimiento | 13 |
| `components/CortetsuFact.qml` | owned-first-party | components | 58 | 1 | - | - | - | 1 |
| `components/CortetsuGrain.qml` | owned-first-party | components | 39 | 3 | - | - | deshabilitado | 2 |
| `components/CortetsuHanko.qml` | owned-first-party | components | 58 | 3 | - | - | movimiento | 1 |
| `components/CortetsuHero.qml` | owned-first-party | components | 53 | 1 | - | - | - | 1 |
| `components/CortetsuIcon.qml` | owned-first-party | components | 34 | 69 | - | - | deshabilitado, movimiento | 8 |
| `components/CortetsuIconBadge.qml` | owned-first-party | components | 26 | 9 | - | - | - | 3 |
| `components/CortetsuInkLabel.qml` | owned-first-party | components | 31 | 1 | - | - | - | 2 |
| `components/CortetsuInkPanel.qml` | owned-first-party | components | 196 | 12 | - | - | - | 5 |
| `components/CortetsuInkWell.qml` | owned-first-party | components | 13 | 2 | - | - | - | 1 |
| `components/CortetsuListRow.qml` | owned-first-party | components | 162 | 11 | - | teclado, ratón | deshabilitado, movimiento | 12 |
| `components/CortetsuPopupSurface.qml` | owned-first-party | components | 30 | 13 | - | - | - | 7 |
| `components/CortetsuProgressBar.qml` | owned-first-party | components | 46 | 7 | - | - | movimiento | 7 |
| `components/CortetsuRoundedImage.qml` | owned-first-party | components | 38 | 2 | - | - | deshabilitado | 0 |
| `components/CortetsuSectionHeader.qml` | owned-first-party | components | 30 | 9 | - | - | - | 2 |
| `components/CortetsuSlider.qml` | owned-first-party | components | 190 | 3 | - | teclado, ratón | deshabilitado, movimiento | 12 |
| `components/CortetsuStateLayer.qml` | owned-first-party | components | 46 | 6 | - | ratón | deshabilitado, movimiento | 4 |
| `components/CortetsuStateMessage.qml` | owned-first-party | components | 60 | 24 | - | - | movimiento | 5 |
| `components/CortetsuSurface.qml` | owned-first-party | components | 50 | 54 | - | - | deshabilitado, movimiento | 16 |
| `components/CortetsuTab.qml` | owned-first-party | components | 114 | 4 | - | teclado, ratón | deshabilitado, movimiento | 5 |
| `components/CortetsuTabBar.qml` | owned-first-party | components | 73 | 1 | - | teclado | - | 1 |
| `components/CortetsuText.qml` | owned-first-party | components | 38 | 109 | - | - | deshabilitado, movimiento | 8 |
| `components/CortetsuToggle.qml` | owned-first-party | components | 110 | 8 | - | teclado, ratón | deshabilitado, movimiento | 8 |
| `components/CortetsuTooltip.qml` | owned-first-party | components | 114 | 11 | - | - | movimiento | 7 |
| `components/ScreenState.qml` | owned-first-party | components | 49 | 5 | - | - | - | 18 |
| `components/containers/CortetsuPopupHost.qml` | owned-first-party | components | 73 | 1 | - | teclado, ratón | deshabilitado, movimiento | 2 |
| `components/containers/StyledWindow.qml` | owned-first-party | components | 9 | 9 | - | - | - | 8 |
| `components/controls/CustomMouseArea.qml` | owned-first-party | components | 16 | 1 | - | ratón | - | 0 |
| `components/misc/CustomShortcut.qml` | owned-first-party | components | 8 | 3 | - | - | - | 5 |
| `modules/BatteryMonitor.qml` | owned-first-party | modules | 65 | 1 | CortetsuPower, CortetsuSession | - | - | 8 |
| `modules/BottomHub.qml` | owned-first-party | modules | 1021 | 10 | Apps, Connectivity, CortetsuPower, Time | - | deshabilitado | 56 |
| `modules/CalendarController.qml` | owned-first-party | modules | 10 | 1 | - | - | - | 2 |
| `modules/ClipboardController.qml` | owned-first-party | modules | 10 | 1 | - | - | - | 2 |
| `modules/CortetsuAnim.qml` | owned-first-party | modules | 23 | 2 | - | - | movimiento | 1 |
| `modules/CortetsuAppRail.qml` | owned-first-party | modules | 215 | 1 | - | teclado, ratón | deshabilitado, movimiento | 13 |
| `modules/CortetsuAudio.qml` | owned-first-party | modules | 71 | 9 | - | - | - | 9 |
| `modules/CortetsuBottomHubHoverTarget.qml` | owned-first-party | modules | 21 | 1 | - | ratón | deshabilitado | 1 |
| `modules/CortetsuBottomHubView.qml` | owned-first-party | modules | 244 | 1 | - | - | - | 8 |
| `modules/CortetsuBottomHubVisibility.qml` | owned-first-party | modules | 73 | 1 | - | - | - | 1 |
| `modules/CortetsuConfig.qml` | owned-first-party | modules | 880 | 78 | - | - | deshabilitado | 53 |
| `modules/CortetsuHoverSurfaceController.qml` | owned-first-party | modules | 129 | 1 | - | - | - | 5 |
| `modules/CortetsuHypr.qml` | owned-first-party | modules | 376 | 25 | CortetsuToaster | - | - | 16 |
| `modules/CortetsuIcon.qml` | owned-first-party | modules | 7 | 68 | - | - | - | 8 |
| `modules/CortetsuIdleInhibitor.qml` | owned-first-party | modules | 42 | 5 | - | - | deshabilitado | 10 |
| `modules/CortetsuIsland.qml` | owned-first-party | modules | 26 | 4 | - | - | - | 5 |
| `modules/CortetsuMask.qml` | owned-first-party | modules | 8 | 3 | - | - | - | 2 |
| `modules/CortetsuModeSegment.qml` | owned-first-party | modules | 74 | 1 | - | ratón | - | 10 |
| `modules/CortetsuNetwork.qml` | owned-first-party | modules | 16 | 7 | ConnectivityWifi | - | - | 11 |
| `modules/CortetsuNotifications.qml` | owned-first-party | modules | 148 | 8 | - | - | deshabilitado | 11 |
| `modules/CortetsuOverlayConfig.qml` | owned-first-party | modules | 38 | 3 | - | - | deshabilitado | 2 |
| `modules/CortetsuPolicyBridge.qml` | owned-first-party | modules | 345 | 1 | - | - | deshabilitado | 2 |
| `modules/CortetsuRecorder.qml` | owned-first-party | modules | 97 | 5 | - | - | - | 5 |
| `modules/CortetsuRegional.qml` | owned-first-party | modules | 88 | 10 | Weather | - | - | 5 |
| `modules/CortetsuScreenState.qml` | owned-first-party | modules | 106 | 1 | - | - | - | 9 |
| `modules/CortetsuScreens.qml` | owned-first-party | modules | 15 | 19 | - | - | - | 12 |
| `modules/CortetsuSearchBar.qml` | owned-first-party | modules | 99 | 11 | - | teclado, ratón | movimiento | 5 |
| `modules/CortetsuShellState.qml` | owned-first-party | modules | 80 | 31 | - | - | - | 34 |
| `modules/CortetsuShortcut.qml` | owned-first-party | modules | 8 | 7 | - | - | - | 8 |
| `modules/CortetsuStateLayer.qml` | owned-first-party | modules | 11 | 5 | - | ratón | deshabilitado | 4 |
| `modules/CortetsuStatusSegment.qml` | owned-first-party | modules | 320 | 1 | Time | teclado, ratón | deshabilitado | 17 |
| `modules/CortetsuSurface.qml` | owned-first-party | modules | 51 | 54 | - | - | deshabilitado, movimiento | 16 |
| `modules/CortetsuText.qml` | owned-first-party | modules | 28 | 109 | - | - | deshabilitado, movimiento | 8 |
| `modules/CortetsuTraySegment.qml` | owned-first-party | modules | 167 | 1 | - | teclado, ratón | deshabilitado | 14 |
| `modules/CortetsuWallpapers.qml` | owned-first-party | modules | 321 | 10 | CortetsuColours | - | - | 19 |
| `modules/CortetsuWorkspaceDots.qml` | owned-first-party | modules | 158 | 1 | - | teclado, ratón | deshabilitado, movimiento | 9 |
| `modules/DashboardHost.qml` | owned-first-party | modules | 65 | 4 | - | - | deshabilitado | 9 |
| `modules/DisplayController.qml` | owned-first-party | modules | 10 | 1 | - | - | - | 8 |
| `modules/HardwareController.qml` | owned-first-party | modules | 76 | 1 | - | - | - | 7 |
| `modules/HubButton.qml` | owned-first-party | modules | 196 | 2 | - | teclado, ratón | deshabilitado, movimiento | 12 |
| `modules/HubFlow.qml` | owned-first-party | modules | 13 | 6 | - | - | - | 0 |
| `modules/IdleMonitors.qml` | owned-first-party | modules | 141 | 2 | CortetsuPower, CortetsuSession, Players | - | deshabilitado | 5 |
| `modules/KeyboardsController.qml` | owned-first-party | modules | 10 | 1 | - | - | - | 0 |
| `modules/LauncherHost.qml` | owned-first-party | modules | 141 | 2 | - | ratón | deshabilitado, movimiento | 8 |
| `modules/OverviewController.qml` | owned-first-party | modules | 72 | 1 | - | - | - | 12 |
| `modules/PolkitHost.qml` | owned-first-party | modules | 83 | 1 | - | - | - | 1 |
| `modules/RetainedSurfaceController.qml` | owned-first-party | modules | 59 | 6 | - | - | - | 10 |
| `modules/RetainedSurfacesHost.qml` | owned-first-party | modules | 146 | 2 | - | ratón | deshabilitado | 12 |
| `modules/SecretPromptHost.qml` | owned-first-party | modules | 194 | 1 | - | - | - | 0 |
| `modules/ServiceLoader.qml` | owned-first-party | modules | 17 | 1 | - | - | - | 3 |
| `modules/SessionHost.qml` | owned-first-party | modules | 125 | 1 | - | - | deshabilitado | 12 |
| `modules/SettingsHost.qml` | owned-first-party | modules | 100 | 1 | - | - | - | 5 |
| `modules/ShellLifecycle.qml` | owned-first-party | modules | 172 | 1 | - | - | - | 3 |
| `modules/Shortcuts.qml` | owned-first-party | modules | 112 | 1 | CortetsuToaster | - | - | 20 |
| `modules/StatusPill.qml` | owned-first-party | modules | 221 | 1 | - | teclado, ratón | movimiento | 9 |
| `modules/WallpaperController.qml` | owned-first-party | modules | 14 | 2 | - | - | - | 10 |
| `modules/areapicker/AreaPicker.qml` | owned-first-party | modules/areapicker | 258 | 3 | CortetsuToaster | - | - | 2 |
| `modules/areapicker/Picker.qml` | owned-first-party | modules/areapicker | 270 | 1 | - | teclado, ratón | deshabilitado, movimiento | 3 |
| `modules/areapicker/ScreenshotPreview.qml` | owned-first-party | modules/areapicker | 112 | 1 | - | ratón | deshabilitado | 2 |
| `modules/background/Background.qml` | owned-first-party | modules/background | 80 | 2 | ShellState | - | - | 4 |
| `modules/background/DesktopClock.qml` | owned-first-party | modules/background | 138 | 2 | Time | - | - | 3 |
| `modules/background/Visualiser.qml` | owned-first-party | modules/background | 56 | 1 | CortetsuSpectrum | - | movimiento | 2 |
| `modules/background/Wallpaper.qml` | owned-first-party | modules/background | 33 | 6 | - | - | - | 24 |
| `modules/bar/BarWrapper.qml` | owned-first-party | modules/bar | 23 | 4 | - | - | deshabilitado | 7 |
| `modules/bar/components/Clock.qml` | dead | modules/bar/components | 42 | 0 | Time | - | - | 4 |
| `modules/bar/components/StatusIcons.qml` | dead | modules/bar/components | 63 | 0 | Connectivity, CortetsuPower | - | - | 2 |
| `modules/bar/popouts/ClipWrapper.qml` | owned-first-party | modules/bar/popouts | 78 | 2 | - | ratón | movimiento | 8 |
| `modules/bar/popouts/CortetsuActiveWindowPopup.qml` | owned-first-party | modules/bar/popouts | 53 | 1 | - | ratón | - | 1 |
| `modules/bar/popouts/CortetsuAudioPopup.qml` | owned-first-party | modules/bar/popouts | 127 | 2 | - | ratón | vacío/error, deshabilitado | 7 |
| `modules/bar/popouts/CortetsuBatteryPopup.qml` | owned-first-party | modules/bar/popouts | 234 | 2 | CortetsuPower | teclado, ratón | vacío/error | 10 |
| `modules/bar/popouts/CortetsuBluetoothPopup.qml` | owned-first-party | modules/bar/popouts | 149 | 2 | ConnectivityBluetooth | ratón | vacío/error, deshabilitado | 4 |
| `modules/bar/popouts/CortetsuDetachedPopup.qml` | owned-first-party | modules/bar/popouts | 49 | 1 | - | ratón | - | 2 |
| `modules/bar/popouts/CortetsuKeyboardPopup.qml` | owned-first-party | modules/bar/popouts | 44 | 2 | - | ratón | vacío/error, deshabilitado | 2 |
| `modules/bar/popouts/CortetsuLockStatusPopup.qml` | owned-first-party | modules/bar/popouts | 27 | 2 | Hypr | - | - | 1 |
| `modules/bar/popouts/CortetsuNetworkPopup.qml` | owned-first-party | modules/bar/popouts | 167 | 2 | Connectivity | ratón | vacío/error, deshabilitado | 4 |
| `modules/bar/popouts/CortetsuTrayMenu.qml` | owned-first-party | modules/bar/popouts | 353 | 1 | - | teclado, ratón | deshabilitado, movimiento | 6 |
| `modules/bar/popouts/CortetsuWifiPasswordPopup.qml` | owned-first-party | modules/bar/popouts | 141 | 1 | Connectivity | teclado, ratón | deshabilitado | 3 |
| `modules/bar/popouts/CortetsuWindowInfoPopup.qml` | owned-first-party | modules/bar/popouts | 184 | 1 | - | teclado, ratón | deshabilitado | 2 |
| `modules/bar/popouts/Wrapper.qml` | owned-first-party | modules/bar/popouts | 208 | 4 | - | teclado, ratón | deshabilitado, movimiento | 53 |
| `modules/calendar/CalendarService.qml` | owned-first-party | modules/calendar | 101 | 3 | - | - | deshabilitado | 8 |
| `modules/calendar/Content.qml` | owned-first-party | modules/calendar | 215 | 20 | - | teclado, ratón | deshabilitado | 74 |
| `modules/calendar/PomodoroCard.qml` | owned-first-party | modules/calendar | 95 | 1 | - | ratón | deshabilitado | 6 |
| `modules/calendar/Wrapper.qml` | owned-first-party | modules/calendar | 30 | 4 | - | teclado | movimiento | 53 |
| `modules/clipboard/ClipboardItem.qml` | owned-first-party | modules/clipboard | 422 | 1 | - | ratón | movimiento | 1 |
| `modules/clipboard/Content.qml` | owned-first-party | modules/clipboard | 859 | 20 | - | teclado, ratón | movimiento | 74 |
| `modules/clipboard/Wrapper.qml` | owned-first-party | modules/clipboard | 75 | 4 | - | - | movimiento | 53 |
| `modules/dashboard/Dash.qml` | owned-first-party | modules/dashboard | 473 | 2 | CortetsuPower, Cpu, Gpu, Lyrics, Memory, NetworkUsage, Storage, Time, Weather | teclado, ratón | deshabilitado, movimiento | 16 |
| `modules/dashboard/DashCover.qml` | owned-first-party | modules/dashboard | 46 | 1 | - | - | - | 0 |
| `modules/dashboard/DashGauge.qml` | owned-first-party | modules/dashboard | 52 | 1 | - | - | - | 1 |
| `modules/dashboard/DashHourChart.qml` | owned-first-party | modules/dashboard | 79 | 1 | - | - | - | 0 |
| `modules/dashboard/DashInk.qml` | owned-first-party | modules/dashboard | 19 | 9 | - | - | - | 2 |
| `modules/dashboard/DashLabel.qml` | owned-first-party | modules/dashboard | 21 | 5 | - | - | - | 1 |
| `modules/dashboard/DashLyricLines.qml` | owned-first-party | modules/dashboard | 44 | 1 | Lyrics | - | - | 1 |
| `modules/dashboard/DashLyrics.qml` | owned-first-party | modules/dashboard | 105 | 1 | Lyrics, Players | ratón | deshabilitado, movimiento | 1 |
| `modules/dashboard/DashMediaPlayer.qml` | owned-first-party | modules/dashboard | 178 | 1 | Players | ratón | - | 1 |
| `modules/dashboard/DashNote.qml` | owned-first-party | modules/dashboard | 42 | 3 | - | - | - | 0 |
| `modules/dashboard/DashRate.qml` | owned-first-party | modules/dashboard | 27 | 1 | NetworkUsage | - | - | 0 |
| `modules/dashboard/DashRule.qml` | owned-first-party | modules/dashboard | 20 | 2 | - | - | - | 0 |
| `modules/dashboard/DashTransport.qml` | owned-first-party | modules/dashboard | 23 | 1 | - | ratón | deshabilitado | 0 |
| `modules/dashboard/DashWeatherSummary.qml` | owned-first-party | modules/dashboard | 42 | 1 | Weather | - | - | 1 |
| `modules/dashboard/DashboardLayer.qml` | owned-first-party | modules/dashboard | 77 | 1 | - | teclado, ratón | deshabilitado, movimiento | 2 |
| `modules/dashboard/Focus.qml` | owned-first-party | modules/dashboard | 141 | 5 | - | ratón | deshabilitado | 8 |
| `modules/dashboard/Today.qml` | owned-first-party | modules/dashboard | 162 | 2 | - | ratón | - | 8 |
| `modules/dashboard/Wrapper.qml` | owned-first-party | modules/dashboard | 37 | 4 | - | - | movimiento | 53 |
| `modules/display/Wrapper.qml` | owned-first-party | modules/display | 30 | 4 | - | - | - | 53 |
| `modules/drawers/ContentWindow.qml` | owned-first-party | modules/drawers | 349 | 3 | Hypr, ShellState | - | deshabilitado, movimiento | 27 |
| `modules/drawers/Drawers.qml` | owned-first-party | modules/drawers | 25 | 1 | - | - | - | 1 |
| `modules/drawers/Exclusions.qml` | owned-first-party | modules/drawers | 32 | 1 | - | - | - | 0 |
| `modules/drawers/HoverPreviewTracker.qml` | owned-first-party | modules/drawers | 74 | 2 | - | ratón | deshabilitado | 0 |
| `modules/drawers/Interactions.qml` | owned-first-party | modules/drawers | 318 | 2 | - | ratón | deshabilitado | 10 |
| `modules/drawers/Panels.qml` | owned-first-party | modules/drawers | 145 | 7 | - | - | - | 23 |
| `modules/drawers/Regions.qml` | owned-first-party | modules/drawers | 86 | 1 | - | - | - | 4 |
| `modules/hardware/Content.qml` | owned-first-party | modules/hardware | 349 | 20 | - | teclado, ratón | - | 74 |
| `modules/hardware/EnergyPage.qml` | owned-first-party | modules/hardware | 269 | 1 | - | - | - | 1 |
| `modules/hardware/FactRow.qml` | owned-first-party | modules/hardware | 54 | 6 | - | ratón | deshabilitado | 0 |
| `modules/hardware/HardwareTelemetry.qml` | owned-first-party | modules/hardware | 197 | 1 | - | - | - | 2 |
| `modules/hardware/HistoryGraph.qml` | owned-first-party | modules/hardware | 328 | 2 | - | ratón | deshabilitado | 0 |
| `modules/hardware/IOPage.qml` | owned-first-party | modules/hardware | 235 | 1 | - | - | - | 0 |
| `modules/hardware/OverviewPage.qml` | owned-first-party | modules/hardware | 296 | 1 | - | ratón | vacío/error, deshabilitado | 0 |
| `modules/hardware/Panel.qml` | owned-first-party | modules/hardware | 27 | 13 | - | - | - | 2 |
| `modules/hardware/PerformancePage.qml` | owned-first-party | modules/hardware | 174 | 1 | - | - | - | 0 |
| `modules/hardware/PowerAutomationPage.qml` | owned-first-party | modules/hardware | 506 | 1 | - | ratón | deshabilitado | 1 |
| `modules/hardware/PowerPage.qml` | owned-first-party | modules/hardware | 294 | 1 | - | - | deshabilitado | 1 |
| `modules/hardware/ProcessesPage.qml` | owned-first-party | modules/hardware | 594 | 1 | - | teclado, ratón | vacío/error, deshabilitado | 1 |
| `modules/hardware/ProfileChoice.qml` | owned-first-party | modules/hardware | 122 | 2 | - | teclado, ratón | deshabilitado, movimiento | 1 |
| `modules/hardware/SensorsPage.qml` | owned-first-party | modules/hardware | 319 | 1 | - | - | - | 0 |
| `modules/hardware/StartupPage.qml` | owned-first-party | modules/hardware | 490 | 1 | - | teclado, ratón | vacío/error, deshabilitado | 3 |
| `modules/hardware/SystemPage.qml` | owned-first-party | modules/hardware | 189 | 1 | - | ratón | - | 0 |
| `modules/hardware/Wrapper.qml` | owned-first-party | modules/hardware | 53 | 4 | - | - | movimiento | 53 |
| `modules/hardware/summary/CapacityBlock.qml` | owned-first-party | modules/hardware | 80 | 1 | - | - | - | 2 |
| `modules/hardware/summary/ContextLink.qml` | owned-first-party | modules/hardware | 53 | 1 | - | - | - | 0 |
| `modules/hardware/summary/CpuBlock.qml` | owned-first-party | modules/hardware | 89 | 1 | - | - | - | 0 |
| `modules/hardware/summary/GpuRow.qml` | owned-first-party | modules/hardware | 72 | 1 | - | - | - | 0 |
| `modules/hardware/summary/HealthBanner.qml` | owned-first-party | modules/hardware | 220 | 1 | - | ratón | deshabilitado | 0 |
| `modules/hardware/summary/NavBlock.qml` | owned-first-party | modules/hardware | 94 | 6 | - | teclado, ratón | movimiento | 1 |
| `modules/hardware/summary/ProcessBlock.qml` | owned-first-party | modules/hardware | 124 | 1 | - | - | - | 0 |
| `modules/hardware/summary/SeverityIcon.qml` | owned-first-party | modules/hardware | 16 | 4 | - | - | - | 0 |
| `modules/hardware/summary/Sparkline.qml` | owned-first-party | modules/hardware | 55 | 1 | - | - | - | 0 |
| `modules/hardware/summary/SummaryFacts.qml` | owned-first-party | modules/hardware | 42 | 3 | - | - | - | 0 |
| `modules/hardware/summary/SummaryLabel.qml` | owned-first-party | modules/hardware | 47 | 10 | - | - | - | 0 |
| `modules/keyboards/Content.qml` | owned-first-party | modules/keyboards | 542 | 20 | - | teclado, ratón | vacío/error, deshabilitado, movimiento | 74 |
| `modules/keyboards/DeviceList.qml` | owned-first-party | modules/keyboards | 116 | 1 | - | ratón | - | 0 |
| `modules/keyboards/EditorPanel.qml` | owned-first-party | modules/keyboards | 486 | 1 | - | ratón | vacío/error, deshabilitado, movimiento | 0 |
| `modules/keyboards/KeyCaps.qml` | owned-first-party | modules/keyboards | 66 | 2 | - | - | - | 0 |
| `modules/keyboards/KeyboardsBackend.qml` | owned-first-party | modules/keyboards | 284 | 1 | - | - | - | 1 |
| `modules/keyboards/ProbeBar.qml` | owned-first-party | modules/keyboards | 78 | 1 | - | ratón | deshabilitado | 0 |
| `modules/keyboards/SelectableRow.qml` | owned-first-party | modules/keyboards | 117 | 1 | - | teclado, ratón | - | 0 |
| `modules/keyboards/Wrapper.qml` | owned-first-party | modules/keyboards | 46 | 4 | - | - | movimiento | 53 |
| `modules/launcher/AppList.qml` | owned-first-party | modules/launcher | 822 | 4 | Actions, Apps, CortetsuProcessLauncher, Emojis, M3Variants, Schemes | ratón | - | 11 |
| `modules/launcher/Content.qml` | owned-first-party | modules/launcher | 203 | 20 | Apps | teclado, ratón | - | 74 |
| `modules/launcher/ContentList.qml` | owned-first-party | modules/launcher | 153 | 1 | - | - | vacío/error, movimiento | 10 |
| `modules/launcher/WallpaperItem.qml` | owned-first-party | modules/launcher | 90 | 1 | - | ratón | deshabilitado, movimiento | 3 |
| `modules/launcher/WallpaperList.qml` | owned-first-party | modules/launcher | 90 | 1 | - | - | - | 5 |
| `modules/launcher/Wrapper.qml` | owned-first-party | modules/launcher | 64 | 4 | - | - | movimiento | 53 |
| `modules/launcher/services/Actions.qml` | owned-first-party | modules/launcher | 103 | 1 | CortetsuProcessLauncher, CortetsuSession | ratón | deshabilitado | 6 |
| `modules/launcher/services/Apps.qml` | owned-first-party | modules/launcher | 94 | 4 | CortetsuProcessLauncher | - | - | 5 |
| `modules/launcher/services/Emojis.qml` | owned-first-party | modules/launcher | 55 | 1 | CortetsuToaster | ratón | - | 0 |
| `modules/launcher/services/M3Variants.qml` | owned-first-party | modules/launcher | 93 | 3 | CortetsuColours | ratón | - | 5 |
| `modules/launcher/services/Schemes.qml` | owned-first-party | modules/launcher | 240 | 3 | CortetsuColours, CortetsuThemes, M3Variants | ratón | - | 5 |
| `modules/lock/Lock.qml` | owned-first-party | modules/lock | 40 | 5 | - | - | - | 10 |
| `modules/lock/LockCard.qml` | owned-first-party | modules/lock | 180 | 1 | CortetsuPower, Time | ratón | movimiento | 6 |
| `modules/lock/LockSurface.qml` | owned-first-party | modules/lock | 154 | 2 | CortetsuPower | teclado | - | 5 |
| `modules/lock/weather/Forecast.qml` | owned-first-party | modules/lock | 41 | 1 | Weather | - | - | 1 |
| `modules/notifications/Notification.qml` | owned-first-party | modules/notifications | 238 | 3 | - | teclado, ratón | movimiento | 9 |
| `modules/notifications/Wrapper.qml` | owned-first-party | modules/notifications | 58 | 4 | Notifs | - | movimiento | 53 |
| `modules/osd/Content.qml` | owned-first-party | modules/osd | 37 | 20 | - | ratón | - | 74 |
| `modules/osd/FullContent.qml` | owned-first-party | modules/osd | 331 | 1 | Brightness, Connectivity, CortetsuPower, GameMode | ratón | deshabilitado | 16 |
| `modules/osd/MiniSlider.qml` | owned-first-party | modules/osd | 92 | 1 | - | - | movimiento | 3 |
| `modules/osd/Wrapper.qml` | owned-first-party | modules/osd | 145 | 4 | Brightness | - | movimiento | 53 |
| `modules/overview/Content.qml` | owned-first-party | modules/overview | 1060 | 20 | - | teclado, ratón | vacío/error | 74 |
| `modules/overview/WindowCard.qml` | owned-first-party | modules/overview | 588 | 1 | - | teclado, ratón | movimiento | 5 |
| `modules/overview/Wrapper.qml` | owned-first-party | modules/overview | 48 | 4 | - | - | movimiento | 53 |
| `modules/polkit/PolkitDialog.qml` | owned-first-party | modules/polkit | 188 | 1 | - | teclado, ratón | deshabilitado | 3 |
| `modules/pomodoro/Pomodoro.qml` | owned-first-party | modules/pomodoro | 92 | 4 | CortetsuToaster | - | - | 14 |
| `modules/prompt/SecretPrompt.qml` | owned-first-party | modules/prompt | 295 | 1 | - | teclado, ratón | deshabilitado | 3 |
| `modules/screenshare/ScreenShare.qml` | owned-first-party | modules/screenshare | 139 | 1 | - | - | - | 0 |
| `modules/screenshare/ScreenSharePanel.qml` | owned-first-party | modules/screenshare | 344 | 1 | - | teclado, ratón | vacío/error, deshabilitado, movimiento | 2 |
| `modules/screenshare/ScreenSharePicker.qml` | owned-first-party | modules/screenshare | 52 | 1 | - | - | - | 1 |
| `modules/session/Content.qml` | owned-first-party | modules/session | 238 | 20 | CortetsuSession | ratón | deshabilitado | 74 |
| `modules/session/Wrapper.qml` | owned-first-party | modules/session | 33 | 4 | - | - | movimiento | 53 |
| `modules/settings/Content.qml` | owned-first-party | modules/settings | 369 | 20 | - | teclado, ratón | deshabilitado, movimiento | 74 |
| `modules/settings/NetworkPage.qml` | owned-first-party | modules/settings | 246 | 1 | Connectivity, CortetsuSettingsNetwork | ratón | deshabilitado | 3 |
| `modules/settings/Nexus.qml` | owned-first-party | modules/settings | 271 | 2 | - | teclado, ratón | vacío/error, movimiento | 5 |
| `modules/settings/NexusResult.qml` | owned-first-party | modules/settings | 83 | 1 | - | teclado, ratón | - | 0 |
| `modules/settings/NexusRow.qml` | owned-first-party | modules/settings | 128 | 1 | - | teclado, ratón | - | 0 |
| `modules/settings/PageRegistry.qml` | owned-first-party | modules/settings | 171 | 1 | - | - | - | 1 |
| `modules/settings/SettingsContext.qml` | owned-first-party | modules/settings | 175 | 1 | Brightness, Connectivity, CortetsuPower, CortetsuThemes, Hypr, Schemes, ShellState | - | - | 6 |
| `modules/settings/SettingsController.qml` | owned-first-party | modules/settings | 178 | 6 | - | - | - | 6 |
| `modules/settings/SettingsHeader.qml` | owned-first-party | modules/settings | 111 | 1 | - | teclado, ratón | - | 0 |
| `modules/settings/bluetooth/BluetoothPage.qml` | owned-first-party | modules/settings/bluetooth | 188 | 1 | - | - | vacío/error, deshabilitado | 2 |
| `modules/settings/bluetooth/DeviceDetailPanel.qml` | owned-first-party | modules/settings/bluetooth | 339 | 1 | - | ratón | vacío/error, deshabilitado | 0 |
| `modules/settings/bluetooth/DeviceListPanel.qml` | owned-first-party | modules/settings/bluetooth | 260 | 1 | - | teclado, ratón | vacío/error | 0 |
| `modules/settings/controls/ChoiceChip.qml` | owned-first-party | modules/settings/controls | 84 | 1 | - | teclado, ratón | deshabilitado | 0 |
| `modules/settings/controls/HubAnchorPicker.qml` | owned-first-party | modules/settings/controls | 153 | 1 | - | teclado, ratón | deshabilitado | 0 |
| `modules/settings/controls/SaveIndicator.qml` | owned-first-party | modules/settings/controls | 56 | 1 | - | - | movimiento | 0 |
| `modules/settings/controls/SettingActionRow.qml` | owned-first-party | modules/settings/controls | 63 | 13 | - | ratón | deshabilitado | 1 |
| `modules/settings/controls/SettingChoiceChips.qml` | owned-first-party | modules/settings/controls | 81 | 5 | - | teclado, ratón | deshabilitado | 0 |
| `modules/settings/controls/SettingNavRow.qml` | owned-first-party | modules/settings/controls | 49 | 5 | - | teclado, ratón | - | 0 |
| `modules/settings/controls/SettingRow.qml` | owned-first-party | modules/settings/controls | 139 | 6 | - | ratón | deshabilitado, movimiento | 0 |
| `modules/settings/controls/SettingSliderRow.qml` | owned-first-party | modules/settings/controls | 82 | 11 | - | - | deshabilitado | 1 |
| `modules/settings/controls/SettingTextRow.qml` | owned-first-party | modules/settings/controls | 57 | 7 | - | teclado | deshabilitado | 0 |
| `modules/settings/controls/SettingToggleRow.qml` | owned-first-party | modules/settings/controls | 56 | 21 | - | teclado, ratón | deshabilitado | 2 |
| `modules/settings/controls/SettingValueRow.qml` | owned-first-party | modules/settings/controls | 27 | 13 | - | - | - | 0 |
| `modules/settings/controls/SettingsColumns.qml` | owned-first-party | modules/settings/controls | 38 | 8 | - | - | - | 0 |
| `modules/settings/controls/SettingsGroup.qml` | owned-first-party | modules/settings/controls | 152 | 34 | - | teclado, ratón | deshabilitado, movimiento | 1 |
| `modules/settings/controls/SettingsPage.qml` | owned-first-party | modules/settings/controls | 32 | 4 | - | - | - | 0 |
| `modules/settings/controls/ThemePreview.qml` | owned-first-party | modules/settings/controls | 144 | 1 | - | - | - | 0 |
| `modules/settings/display/DisplayArrangement.qml` | owned-first-party | modules/settings/display | 154 | 1 | - | teclado, ratón | vacío/error | 2 |
| `modules/settings/display/DisplayColour.qml` | owned-first-party | modules/settings/display | 120 | 1 | DisplayCalibration, DisplayVibrance, Nvibrant | - | - | 0 |
| `modules/settings/display/DisplayPage.qml` | owned-first-party | modules/settings/display | 343 | 1 | Nvibrant | ratón | deshabilitado | 1 |
| `modules/settings/network/DetailRow.qml` | owned-first-party | modules/settings/network | 32 | 1 | - | - | - | 0 |
| `modules/settings/network/NetworkDetailPanel.qml` | owned-first-party | modules/settings/network | 220 | 1 | CortetsuSettingsNetwork | ratón | vacío/error, deshabilitado | 0 |
| `modules/settings/network/NetworkHero.qml` | owned-first-party | modules/settings/network | 132 | 1 | CortetsuSettingsNetwork | ratón | deshabilitado | 0 |
| `modules/settings/network/NetworkListPanel.qml` | owned-first-party | modules/settings/network | 244 | 1 | CortetsuSettingsNetwork | teclado, ratón | vacío/error, deshabilitado | 0 |
| `modules/settings/network/SignalBars.qml` | owned-first-party | modules/settings/network | 29 | 2 | - | - | - | 0 |
| `modules/settings/pages/AboutPage.qml` | owned-first-party | modules/settings/pages | 184 | 1 | - | - | - | 0 |
| `modules/settings/pages/CategoryPage.qml` | owned-first-party | modules/settings/pages | 35 | 1 | - | - | - | 0 |
| `modules/settings/pages/HomePage.qml` | owned-first-party | modules/settings/pages | 268 | 1 | - | teclado, ratón | - | 0 |
| `modules/settings/sections/AccessibilitySection.qml` | owned-first-party | modules/settings/sections | 53 | 1 | - | - | - | 0 |
| `modules/settings/sections/AudioSection.qml` | owned-first-party | modules/settings/sections | 204 | 1 | - | ratón | vacío/error, deshabilitado | 0 |
| `modules/settings/sections/AutomationSection.qml` | owned-first-party | modules/settings/sections | 166 | 1 | - | - | deshabilitado | 2 |
| `modules/settings/sections/BottomHubSection.qml` | owned-first-party | modules/settings/sections | 217 | 1 | - | - | - | 0 |
| `modules/settings/sections/ClockUnitsSection.qml` | owned-first-party | modules/settings/sections | 35 | 1 | - | - | - | 0 |
| `modules/settings/sections/DashboardSection.qml` | owned-first-party | modules/settings/sections | 150 | 1 | - | - | deshabilitado | 0 |
| `modules/settings/sections/DiagnosticsSection.qml` | owned-first-party | modules/settings/sections | 61 | 1 | - | - | - | 0 |
| `modules/settings/sections/InputSection.qml` | owned-first-party | modules/settings/sections | 37 | 1 | - | - | - | 0 |
| `modules/settings/sections/IntegrationsSection.qml` | owned-first-party | modules/settings/sections | 45 | 1 | CortetsuThemes | - | deshabilitado | 0 |
| `modules/settings/sections/LauncherSection.qml` | owned-first-party | modules/settings/sections | 111 | 1 | - | - | deshabilitado | 1 |
| `modules/settings/sections/NotificationsSection.qml` | owned-first-party | modules/settings/sections | 138 | 1 | - | - | deshabilitado | 0 |
| `modules/settings/sections/OsdSection.qml` | owned-first-party | modules/settings/sections | 23 | 1 | - | - | - | 0 |
| `modules/settings/sections/PowerSection.qml` | owned-first-party | modules/settings/sections | 167 | 1 | CortetsuPower, CortetsuSession | - | deshabilitado | 0 |
| `modules/settings/sections/RecorderSection.qml` | owned-first-party | modules/settings/sections | 35 | 1 | - | - | - | 0 |
| `modules/settings/sections/RelatedSection.qml` | owned-first-party | modules/settings/sections | 31 | 1 | - | - | - | 0 |
| `modules/settings/sections/SchemeSection.qml` | owned-first-party | modules/settings/sections | 223 | 1 | CortetsuColours, CortetsuThemes, M3Variants, Schemes | ratón | vacío/error, deshabilitado | 1 |
| `modules/settings/sections/ScreenshotSection.qml` | owned-first-party | modules/settings/sections | 35 | 1 | - | - | - | 0 |
| `modules/settings/sections/ShortcutsSection.qml` | owned-first-party | modules/settings/sections | 159 | 1 | - | ratón | vacío/error | 1 |
| `modules/settings/sections/ThemeGallery.qml` | owned-first-party | modules/settings/sections | 224 | 1 | CortetsuThemes | ratón | deshabilitado | 0 |
| `modules/settings/sections/ThemeGeometrySection.qml` | owned-first-party | modules/settings/sections | 52 | 1 | CortetsuThemes | - | deshabilitado | 0 |
| `modules/settings/sections/ThemeOptionsSection.qml` | owned-first-party | modules/settings/sections | 42 | 1 | CortetsuColours, CortetsuThemes | - | deshabilitado | 0 |
| `modules/settings/sections/ThemeProfileSection.qml` | owned-first-party | modules/settings/sections | 45 | 1 | CortetsuThemes | - | deshabilitado | 0 |
| `modules/settings/sections/ThemeResetSection.qml` | owned-first-party | modules/settings/sections | 20 | 1 | CortetsuThemes | - | - | 0 |
| `modules/settings/sections/VisualiserSection.qml` | owned-first-party | modules/settings/sections | 38 | 1 | - | - | deshabilitado | 0 |
| `modules/settings/sections/WallpaperSection.qml` | owned-first-party | modules/settings/sections | 276 | 1 | - | teclado, ratón | deshabilitado | 0 |
| `modules/settings/sections/WeatherSection.qml` | owned-first-party | modules/settings/sections | 65 | 1 | - | - | - | 0 |
| `modules/sidebar/Content.qml` | owned-first-party | modules/sidebar | 202 | 20 | Notifs | ratón | vacío/error, deshabilitado | 74 |
| `modules/sidebar/Wrapper.qml` | owned-first-party | modules/sidebar | 41 | 4 | - | - | movimiento | 53 |
| `modules/utilities/Content.qml` | owned-first-party | modules/utilities | 247 | 20 | - | teclado, ratón | - | 74 |
| `modules/utilities/Wrapper.qml` | owned-first-party | modules/utilities | 58 | 4 | - | - | movimiento | 53 |
| `modules/utilities/toasts/ToastItem.qml` | owned-first-party | modules/utilities | 110 | 1 | - | teclado, ratón | - | 4 |
| `modules/utilities/toasts/Toasts.qml` | owned-first-party | modules/utilities | 74 | 2 | CortetsuToaster | teclado | movimiento | 5 |
| `modules/wallpaper/Content.qml` | owned-first-party | modules/wallpaper | 833 | 20 | CortetsuColours, CortetsuToaster | teclado, ratón | deshabilitado, movimiento | 74 |
| `modules/wallpaper/OctagonFrame.qml` | owned-first-party | modules/wallpaper | 29 | 2 | - | - | - | 1 |
| `modules/wallpaper/WallpaperStage.qml` | owned-first-party | modules/wallpaper | 175 | 1 | - | - | deshabilitado | 2 |
| `modules/wallpaper/WallpaperTile.qml` | owned-first-party | modules/wallpaper | 81 | 2 | - | - | deshabilitado | 1 |
| `modules/wallpaper/Wrapper.qml` | owned-first-party | modules/wallpaper | 71 | 4 | - | - | movimiento | 53 |
| `modules/wallpaper/tests/tst_Orbit.qml` | harness/test | modules/wallpaper | 155 | 0 | - | - | - | 1 |
| `services/Audio.qml` | owned-first-party | services | 33 | 5 | - | - | - | 6 |
| `services/Brightness.qml` | owned-first-party | services | 270 | 5 | - | - | - | 6 |
| `services/Connectivity.qml` | owned-first-party | services | 32 | 8 | CortetsuToaster | - | - | 10 |
| `services/ConnectivityBluetooth.qml` | owned-first-party | services | 327 | 3 | - | - | deshabilitado | 3 |
| `services/ConnectivityNmAdapter.qml` | owned-first-party | services | 275 | 1 | - | - | - | 4 |
| `services/ConnectivityWifi.qml` | owned-first-party | services | 268 | 4 | - | - | deshabilitado | 8 |
| `services/CortetsuColours.qml` | owned-first-party | services | 189 | 9 | CortetsuThemes | - | - | 19 |
| `services/CortetsuPower.qml` | owned-first-party | services | 33 | 12 | - | - | - | 23 |
| `services/CortetsuProcessLauncher.qml` | owned-first-party | services | 20 | 3 | - | - | - | 1 |
| `services/CortetsuSession.qml` | owned-first-party | services | 115 | 6 | - | - | - | 8 |
| `services/CortetsuSettingsNetwork.qml` | owned-first-party | services | 168 | 4 | ConnectivityWifi | - | - | 2 |
| `services/CortetsuSpectrum.qml` | owned-first-party | services | 50 | 3 | - | - | deshabilitado | 3 |
| `services/CortetsuThemes.qml` | owned-first-party | services | 262 | 10 | CortetsuColours | - | deshabilitado | 2 |
| `services/CortetsuToaster.qml` | owned-first-party | services | 29 | 12 | - | - | - | 8 |
| `services/CortetsuTokens.qml` | owned-first-party | services | 182 | 1 | - | - | - | 3 |
| `services/Cpu.qml` | owned-first-party | services | 78 | 1 | - | - | - | 3 |
| `services/DisplayCalibration.qml` | owned-first-party | services | 122 | 2 | - | - | deshabilitado | 1 |
| `services/DisplayModel.qml` | owned-first-party | services | 179 | 1 | - | - | - | 0 |
| `services/DisplayPresetStore.qml` | owned-first-party | services | 68 | 1 | - | - | - | 0 |
| `services/DisplayTransaction.qml` | owned-first-party | services | 148 | 2 | - | - | - | 0 |
| `services/DisplayVibrance.qml` | owned-first-party | services | 120 | 1 | - | - | - | 3 |
| `services/GameMode.qml` | owned-first-party | services | 109 | 1 | - | - | deshabilitado | 3 |
| `services/Gpu.qml` | owned-first-party | services | 70 | 1 | - | - | - | 2 |
| `services/HelperWriteQueue.qml` | owned-first-party | services | 111 | 2 | - | - | - | 2 |
| `services/Hypr.qml` | owned-first-party | services | 55 | 3 | - | - | - | 7 |
| `services/Lyrics.qml` | owned-first-party | services | 169 | 4 | Players | - | - | 3 |
| `services/Memory.qml` | owned-first-party | services | 40 | 3 | - | - | - | 3 |
| `services/NetworkUsage.qml` | owned-first-party | services | 79 | 2 | - | - | - | 2 |
| `services/NotifData.qml` | owned-first-party | services | 92 | 1 | Notifs | - | - | 9 |
| `services/Notifs.qml` | owned-first-party | services | 308 | 4 | CortetsuToaster | - | deshabilitado | 14 |
| `services/Nvibrant.qml` | owned-first-party | services | 124 | 2 | - | - | - | 2 |
| `services/Players.qml` | owned-first-party | services | 72 | 5 | CortetsuToaster | - | - | 7 |
| `services/Requests.qml` | owned-first-party | services | 69 | 1 | - | - | - | 6 |
| `services/Screens.qml` | owned-first-party | services | 17 | 2 | - | - | - | 2 |
| `services/ShellState.qml` | owned-first-party | services | 95 | 4 | - | - | - | 12 |
| `services/Storage.qml` | owned-first-party | services | 50 | 2 | - | - | - | 3 |
| `services/Time.qml` | owned-first-party | services | 27 | 7 | - | - | deshabilitado | 7 |
| `services/UsageFmt.qml` | dead | services | 19 | 0 | - | - | - | 1 |
| `services/Weather.qml` | owned-first-party | services | 109 | 4 | Requests | - | - | 10 |
| `shell.qml` | owned-first-party | (raíz) | 69 | 32 | - | - | deshabilitado | 140 |
| `tests/qml/areapicker/tst_ScreenshotPreview.qml` | harness/test | tests | 80 | 0 | - | - | - | 0 |
| `tests/qml/bottomhub/fixture_ScriptModelIdentity.qml` | harness/test | tests | 51 | 0 | - | - | - | 0 |
| `tests/qml/bottomhub/tst_BottomHubDelegateChurn.qml` | harness/test | tests | 54 | 0 | - | - | - | 0 |
| `tests/qml/bottomhub/tst_BottomHubDelegates.qml` | harness/test | tests | 234 | 0 | - | teclado | deshabilitado | 0 |
| `tests/qml/bottomhub/tst_BottomHubResolver.qml` | harness/test | tests | 323 | 0 | - | - | - | 0 |
| `tests/qml/bottomhub/tst_BottomHubTrayPolicy.qml` | harness/test | tests | 64 | 0 | - | - | - | 0 |
| `tests/qml/bottomhub/tst_HubAnchor.qml` | harness/test | tests | 80 | 0 | - | - | - | 0 |
| `tests/qml/bottomhub/tst_HubControls.qml` | harness/test | tests | 129 | 0 | - | - | - | 0 |
| `tests/qml/bottomhub/tst_TrayNavigation.qml` | harness/test | tests | 77 | 0 | - | - | deshabilitado | 0 |
| `tests/qml/bottomhub/tst_TraySegment.qml` | harness/test | tests | 79 | 0 | - | - | - | 0 |
| `tests/qml/bottomhub/tst_TrayStackOwnership.qml` | harness/test | tests | 77 | 0 | - | - | - | 0 |
| `tests/qml/calendar/tst_CalendarModel.qml` | harness/test | tests | 123 | 0 | - | - | - | 0 |
| `tests/qml/components/tst_AccessibleControls.qml` | harness/test | tests | 159 | 0 | - | teclado, ratón | deshabilitado | 0 |
| `tests/qml/components/tst_IconParity.qml` | harness/test | tests | 50 | 0 | - | - | - | 0 |
| `tests/qml/components/tst_MotionTokens.qml` | harness/test | tests | 116 | 0 | - | - | - | 0 |
| `tests/qml/components/tst_PremiumSobria.qml` | harness/test | tests | 89 | 0 | - | teclado | - | 0 |
| `tests/qml/components/tst_ProgressBar.qml` | harness/test | tests | 58 | 0 | - | - | - | 0 |
| `tests/qml/components/tst_SchemeContrast.qml` | harness/test | tests | 69 | 0 | - | - | - | 0 |
| `tests/qml/components/tst_Slider.qml` | harness/test | tests | 112 | 0 | - | teclado | - | 0 |
| `tests/qml/components/tst_SpectrumLifecycle.qml` | harness/test | tests | 23 | 0 | CortetsuSpectrum | - | deshabilitado | 0 |
| `tests/qml/components/tst_StateLayer.qml` | harness/test | tests | 60 | 0 | - | ratón | deshabilitado | 0 |
| `tests/qml/components/tst_StateMessage.qml` | harness/test | tests | 60 | 0 | - | - | vacío/error | 0 |
| `tests/qml/focus/tst_DisabledControlFocus.qml` | harness/test | tests | 104 | 0 | - | teclado | deshabilitado | 0 |
| `tests/qml/hardware/tst_HardwareHealth.qml` | harness/test | tests | 96 | 0 | - | - | - | 0 |
| `tests/qml/hardware/tst_HardwareNavigation.qml` | harness/test | tests | 42 | 0 | - | - | - | 0 |
| `tests/qml/hardware/tst_NavBlock.qml` | harness/test | tests | 78 | 0 | - | teclado | - | 0 |
| `tests/qml/hardware/tst_OmenFullscreen.qml` | harness/test | tests | 33 | 0 | - | - | - | 0 |
| `tests/qml/hardware/tst_ProfileChoice.qml` | harness/test | tests | 54 | 0 | - | teclado | deshabilitado | 0 |
| `tests/qml/hardware/tst_SystemInfo.qml` | harness/test | tests | 38 | 0 | - | - | - | 0 |
| `tests/qml/hypr/tst_CortetsuHyprActions.qml` | harness/test | tests | 120 | 0 | - | - | - | 0 |
| `tests/qml/hypr/tst_CortetsuHyprEventPolicy.qml` | harness/test | tests | 60 | 0 | - | - | - | 0 |
| `tests/qml/hypr/tst_CortetsuToplevels.qml` | harness/test | tests | 45 | 0 | - | - | - | 0 |
| `tests/qml/keyboards/tst_CaptureFlow.qml` | harness/test | tests | 149 | 0 | - | - | - | 0 |
| `tests/qml/keyboards/tst_KeyCapture.qml` | harness/test | tests | 58 | 0 | - | - | - | 0 |
| `tests/qml/keyboards/tst_Model.qml` | harness/test | tests | 103 | 0 | - | - | - | 0 |
| `tests/qml/launcher/tst_EmojiSearch.qml` | harness/test | tests | 44 | 0 | - | - | - | 0 |
| `tests/qml/policy/tst_AudioProtection.qml` | harness/test | tests | 15 | 0 | - | - | - | 0 |
| `tests/qml/policy/tst_PolicyModel.qml` | harness/test | tests | 48 | 0 | - | - | deshabilitado | 0 |
| `tests/qml/polkit/tst_PolkitDialog.qml` | harness/test | tests | 179 | 0 | - | - | deshabilitado | 0 |
| `tests/qml/pomodoro/tst_PomodoroModel.qml` | harness/test | tests | 78 | 0 | - | - | - | 0 |
| `tests/qml/prompt/tst_SecretPrompt.qml` | harness/test | tests | 253 | 0 | - | teclado | deshabilitado | 0 |
| `tests/qml/services/fixture_CalendarPomodoroServices.qml` | harness/test | tests | 94 | 0 | CortetsuToaster | - | - | 1 |
| `tests/qml/services/fixture_WeatherRefresh.qml` | harness/test | tests | 128 | 0 | Requests, Weather | - | - | 1 |
| `tests/qml/services/mock_Requests.qml` | harness/test | tests | 19 | 0 | - | - | - | 1 |
| `tests/qml/settings/tst_SettingsConfirmation.qml` | harness/test | tests | 67 | 0 | - | - | deshabilitado | 0 |
| `tests/qml/settings/tst_SettingsNavigation.qml` | harness/test | tests | 79 | 0 | - | - | - | 0 |
| `tests/qml/surfaces/tst_BottomHubAutoHide.qml` | harness/test | tests | 84 | 0 | - | - | deshabilitado | 0 |
| `tests/qml/surfaces/tst_CortetsuShellInspect.qml` | harness/test | tests | 225 | 0 | - | - | - | 0 |
| `tests/qml/surfaces/tst_HoverEdges.qml` | harness/test | tests | 26 | 0 | - | - | - | 0 |
| `tests/qml/surfaces/tst_HoverPreview.qml` | harness/test | tests | 41 | 0 | - | - | - | 0 |
| `tests/qml/surfaces/tst_MiniSlider.qml` | harness/test | tests | 64 | 0 | - | - | - | 0 |
| `tests/qml/surfaces/tst_OsdEscape.qml` | harness/test | tests | 36 | 0 | - | teclado | deshabilitado | 0 |
| `tests/qml/surfaces/tst_OverlayTransitions.qml` | harness/test | tests | 197 | 0 | - | - | - | 1 |
| `tests/qml/surfaces/tst_ScrimHit.qml` | harness/test | tests | 86 | 0 | - | ratón | - | 0 |
| `tests/qml/surfaces/tst_SurfaceRegistry.qml` | harness/test | tests | 308 | 0 | - | - | - | 0 |
| `tests/qml/themes/tst_ThemeProfiles.qml` | harness/test | tests | 102 | 0 | - | - | - | 0 |
| `tests/realm/polkit-preview.qml` | harness/test | tests | 46 | 0 | - | - | - | 2 |
| `theme/CortetsuDesign.qml` | generated | theme | 174 | 210 | - | - | - | 62 |
| `utils/CortetsuUtils.qml` | dead | utils | 18 | 0 | - | - | - | 2 |
| `utils/Icons.qml` | owned-first-party | utils | 85 | 7 | - | - | - | 8 |
| `utils/NetworkConnection.qml` | dead | utils | 23 | 0 | Connectivity | - | - | 4 |
| `utils/Paths.qml` | owned-first-party | utils | 61 | 4 | - | - | - | 5 |
| `utils/SysInfo.qml` | dead | utils | 58 | 0 | - | - | - | 2 |
