# IPC del shell

Generado por `scripts/verification/ipc-inventory.py` a partir de los
`IpcHandler` del QML. No editar a mano: regenerar tras cambiar un destino.

Uso: `cortetsu shell ipc <destino> <función> [argumentos]`. Una función
llamada `show` exige `call --` (ver la memoria del proyecto). `qs ipc call`
sale con 0 aunque el destino no exista: comprobar la salida.

Destinos: 29. Un destino definido en varios archivos aparece una
vez por archivo; si dos están activos a la vez, la llamada llega a uno solo.

## `bottomHub`

- `cortetsu/modules/BottomHub.qml`
  - `toggle(): void`
  - `show(): void`
  - `hide(): void`
  - `isShown(): bool`
  - `notificationsButton(): string`
  - `trayButton(): string`
  - `apps(): string`
  - `appButton(key: string): string`
  - `inspect(): string`
  - `launcher(): void`
  - `anchor(monitor: string, id: string): bool`
  - `clearAnchor(monitor: string): void`
  - `editMode(monitor: string): bool`
  - `editTarget(id: string): bool`
  - `editSave(): bool`
  - `editCancel(): void`
  - `editState(): string`
  - `anchors(): string`
  - `notifications(): void`
  - `quickSettings(): void`
  - `control(mode: string): bool`
  - `closeControl(): void`
  - `detachedControl(mode: string): bool`

## `brightness`

- `cortetsu/services/Brightness.qml`
  - `get(): real`
  - `getFor(query: string): real`
  - `status(): string`
  - `set(value: string): string`
  - `setFor(query: string, value: string): string`

## `calendar`

- `cortetsu/modules/CalendarController.qml` (vía `cortetsu/modules/RetainedSurfaceController.qml`)
  - `toggle(): void`
  - `open(): void`
  - `close(): void`
  - `isOpen(): bool`

## `cheatsheet`

- `cortetsu/modules/CheatsheetController.qml` (vía `cortetsu/modules/RetainedSurfaceController.qml`)
  - `toggle(): void`
  - `open(): void`
  - `close(): void`
  - `isOpen(): bool`

## `clipboard`

- `cortetsu/modules/ClipboardController.qml` (vía `cortetsu/modules/RetainedSurfaceController.qml`)
  - `toggle(): void`
  - `open(): void`
  - `close(): void`
  - `isOpen(): bool`

## `contexts`

- `cortetsu/services/CortetsuContexts.qml`
  - `list(): string`
  - `active(): string`
  - `activate(id: string): bool`
  - `deactivate(): void`
  - `toggle(id: string): void`

## `cortetsu-notifications`

- `cortetsu/modules/CortetsuNotifications.qml`
  - `clear(): void`
  - `dismiss(id: string): void`
  - `setDnd(enabled: bool): void`
  - `toggleDnd(): void`
  - `isDndEnabled(): bool`
  - `count(): int`

## `cortetsu-shell`

- `cortetsu/modules/ShellLifecycle.qml`
  - `reload(): void`
  - `inspect(): string`

## `cortetsu-v2-bridge`

- `cortetsu/modules/CortetsuPolicyBridge.qml`
  - `inspect(): string`
  - `refresh(): void`

## `cortetsu-wallpaper`

- `cortetsu/modules/CortetsuWallpapers.qml`
  - `get(): string`
  - `set(path: string): void`
  - `list(): string`
  - `random(): void`

## `customDock`

- `cortetsu/modules/BottomHub.qml`
  - `toggle(): void`
  - `show(): void`
  - `hide(): void`
  - `isShown(): bool`
  - `launcher(): void`
  - `emoji(): void`

## `desktopWidgets`

- `cortetsu/modules/DesktopWidgetsController.qml` (vía `cortetsu/modules/RetainedSurfaceController.qml`)
  - `toggle(): void`
  - `open(): void`
  - `close(): void`
  - `isOpen(): bool`

## `display`

- `cortetsu/modules/DisplayController.qml` (vía `cortetsu/modules/RetainedSurfaceController.qml`)
  - `toggle(): void`
  - `open(): void`
  - `close(): void`
  - `isOpen(): bool`

## `drawers`

- `cortetsu/modules/Shortcuts.qml`
  - `toggle(drawer: string): void`
  - `list(): string`
  - `launcherScreens(): string`
  - `settingsPage(page: string): void`
  - `isOpen(drawer: string): string`

## `gameMode`

- `cortetsu/services/GameMode.qml`
  - `isEnabled(): bool`
  - `status(): string`
  - `toggle(): void`
  - `enable(): void`
  - `disable(): void`
  - `recover(): void`

## `hardware`

- `cortetsu/modules/HardwareController.qml` (vía `cortetsu/modules/RetainedSurfaceController.qml`)
  - `toggle(): void`
  - `open(): void`
  - `close(): void`
  - `isOpen(): bool`

## `hardwarePage`

- `cortetsu/modules/HardwareController.qml`
  - `show(target: string): void`
  - `current(): int`

## `keepAwake`

- `cortetsu/modules/CortetsuIdleInhibitor.qml`
  - `toggle(): bool`
  - `enable(): void`
  - `disable(): void`
  - `isEnabled(): bool`

## `keyboards`

- `cortetsu/modules/KeyboardsController.qml` (vía `cortetsu/modules/RetainedSurfaceController.qml`)
  - `toggle(): void`
  - `open(): void`
  - `close(): void`
  - `isOpen(): bool`

## `lock`

- `cortetsu/modules/lock/Lock.qml`
  - `lock(): void`
  - `isLocked(): bool`

## `lyrics`

- `cortetsu/services/Lyrics.qml`
  - `status(): string`

## `mpris`

- `cortetsu/services/Players.qml`
  - `getActive(prop: string): string`
  - `list(): string`
  - `play(): void`
  - `pause(): void`
  - `playPause(): void`
  - `previous(): void`
  - `next(): void`
  - `stop(): void`

## `notifs`

- `cortetsu/services/Notifs.qml`
  - `clear(): void`
  - `inspect(): string`
  - `isDndEnabled(): bool`
  - `toggleDnd(): void`
  - `enableDnd(): void`
  - `disableDnd(): void`

## `overview`

- `cortetsu/modules/OverviewController.qml`
  - `toggle(): void`
  - `open(): void`
  - `close(): void`
  - `isOpen(): bool`

## `picker`

- `cortetsu/modules/areapicker/AreaPicker.qml`
  - `open(): void`
  - `openFreeze(): void`
  - `openClip(): void`
  - `openFreezeClip(): void`
  - `record(): void`

## `screenshare`

- `cortetsu/modules/screenshare/ScreenShare.qml`
  - `request(socketPath: string, token: string): void`

## `secretprompt`

- `cortetsu/modules/SecretPromptHost.qml`
  - `ping(): string`
  - `request(socketPath: string, token: string): void`

## `toaster`

- `cortetsu/modules/Shortcuts.qml`
  - `info(title: string, message: string, icon: string): void`
  - `error(title: string, message: string): void`

## `wallpapermanager`

- `cortetsu/modules/WallpaperController.qml` (vía `cortetsu/modules/RetainedSurfaceController.qml`)
  - `toggle(): void`
  - `open(): void`
  - `close(): void`
  - `isOpen(): bool`
