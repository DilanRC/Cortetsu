pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import ".."
import "../../components"
import "../../theme"
import "../CortetsuTypography.js" as CortetsuTypography
import "CaptureFlow.js" as Flow
import "KeyCapture.js" as KeyCapture
import "Model.js" as Model

// «Atajos y teclados»: which keyboards are connected, what their keys do,
// which dedicated keys are free, and the editor that changes a shortcut
// through capture, review, apply and verification.
FocusScope {
    id: root

    required property ShellScreen screen
    required property var screenState
    required property bool surfaceVisible

    property int currentTab: 0
    property string deviceId: ""
    property string query: ""
    property var selectedBinding: null
    property var selectedKey: null
    property var flow: Flow.initial()
    property string lastKeyDetail: ""
    property real captureRemaining: 1

    readonly property alias backend: backend
    // Panel and column sizes: at most these, and smaller on a narrow screen.
    readonly property int panelMaxWidth: 1280
    readonly property int panelMaxHeight: 820
    readonly property int deviceColumnMax: 270
    readonly property int editorColumnMax: 380
    readonly property var tabs: [
        { label: qsTr("Atajos"), icon: "keyboard_command_key" },
        { label: qsTr("Teclas especiales"), icon: "keyboard_keys" },
        { label: qsTr("Por aprovechar"), icon: "add_circle" }
    ]
    readonly property var selectedKeyboard: backend.keyboards.find(k => k.id === deviceId) ?? null
    readonly property string targetLabel: selectedKeyboard?.label ?? qsTr("Todos los teclados")
    readonly property var shortcutRows: Model.shortcutsFor(backend.bindings, backend.deviceKeys, deviceId, query)
    readonly property var specialRows: Model.specialKeys(backend.deviceKeys, deviceId)
    readonly property var spareRows: Model.spareFor(backend.spare, deviceId)
    readonly property bool listening: Flow.holdsKeyboard(flow)

    function dispatch(event): void {
        const before = flow;
        flow = Flow.next(before, event);
        for (const effect of Flow.effects(before, event, flow))
            run(effect);
    }

    function run(effect): void {
        if (effect.do === "capture") {
            backend.capture(effect.verb);
            if (effect.verb === "begin")
                beginWatchdog.restart();
        } else if (effect.do === "countdown") {
            captureRemaining = 1;
            if (effect.run)
                captureCountdown.restart();
            else
                captureCountdown.stop();
        } else if (effect.do === "preview") {
            backend.preview(effect.args);
        } else if (effect.do === "apply") {
            backend.apply(effect.args, effect.version);
        }
    }

    // The desktop entry an application shortcut launches, or null.
    function appForBinding(binding): var {
        const match = Model.appMatch(binding, [...DesktopEntries.applications.values]);
        if (match.entry || !match.executable)
            return match.entry;
        return DesktopEntries.heuristicLookup(match.executable) ?? DesktopEntries.heuristicLookup(binding.command);
    }

    function startCapture(): void {
        if (!selectedBinding?.editable)
            return;
        lastKeyDetail = "";
        dispatch({ type: "start", change: { kind: "set", id: selectedBinding.id } });
    }

    function assignApp(app): void {
        if (!selectedKey?.keysym)
            return;
        dispatch({ type: "propose", chord: selectedKey.keysym,
                   change: { kind: "add-app", app: { id: app.id, name: app.name, execString: app.execString } } });
    }

    function runChange(args): void {
        if (!Flow.busy(flow))
            backend.apply(args, backend.version);
    }

    function cancel(message): void {
        dispatch({ type: "cancel", message: message });
    }

    function openSurface(): void {
        forceActiveFocus();
    }

    function closeSurface(): void {
        root.screenState.cortetsuState?.setRetained("keyboards", false);
    }

    function selectBinding(binding): void {
        if (Flow.busy(flow) || listening)
            return;
        selectedKey = null;
        selectedBinding = binding;
        dispatch({ type: "reset" });
    }

    function selectKey(key): void {
        if (Flow.busy(flow) || listening)
            return;
        selectedBinding = null;
        selectedKey = key;
        dispatch({ type: "reset" });
    }

    // While recording, every key belongs to the capture: Escape must not
    // close the surface (the host's Shortcut) and digits must not switch tabs.
    Keys.onShortcutOverride: event => event.accepted = root.listening
    // One key press while recording; true when the capture took it.
    function handleKey(key: int, modifiers: int, scanCode: int): bool {
        if (!listening)
            return false;
        if (key === Qt.Key_Escape && modifiers === Qt.NoModifier) {
            cancel(qsTr("Grabación cancelada; el atajo no cambió"));
            return true;
        }
        // Until Hyprland holds the global binds, keys are swallowed unread.
        if (!flow.armed)
            return true;
        const keysym = backend.keysymByScanCode[scanCode] ?? "";
        lastKeyDetail = scanCode > 0
            ? qsTr("Última tecla: código %1 · %2").arg(scanCode - 8).arg(keysym || qsTr("sin keysym"))
            : "";
        const result = KeyCapture.resolve(key, modifiers, keysym);
        if (result.kind === "chord") {
            dispatch({ type: "chord", chord: result.chord });
            return true;
        }
        dispatch({
            type: "held",
            held: result.held,
            message: result.kind === "bare" ? qsTr("Añade un modificador: Super, o Ctrl + Alt.")
                : result.kind === "altgr" ? qsTr("AltGr escribe caracteres en latam; no se usa en atajos.")
                : result.kind === "unsupported" ? qsTr("Esa tecla no tiene un nombre que Hyprland acepte.")
                : ""
        });
        return true;
    }

    Keys.onPressed: event => {
        if (root.handleKey(event.key, event.modifiers, event.nativeScanCode)) {
            event.accepted = true;
            return;
        }
        // R refreshes, unless a text field has the focus.
        if (event.key === Qt.Key_R && event.modifiers === Qt.NoModifier && root.Window.activeFocusItem?.text === undefined) {
            backend.refresh();
            event.accepted = true;
        }
    }
    Keys.onReleased: event => {
        if (!root.listening)
            return;
        event.accepted = true;
        if (KeyCapture.isModifierKey(event.key))
            root.dispatch({ type: "held", held: KeyCapture.modifiers(event.modifiers), message: "" });
    }

    onSurfaceVisibleChanged: {
        if (!surfaceVisible && listening)
            dispatch({ type: "closed", message: qsTr("Se cerró el editor; el atajo no cambió") });
    }
    // Focus left the surface (another window took the keyboard): stop.
    onActiveFocusChanged: {
        if (!activeFocus && listening && surfaceVisible)
            dispatch({ type: "cancel", message: qsTr("Se perdió el foco; la grabación se canceló") });
    }
    Component.onDestruction: {
        if (listening)
            backend.releaseDetached();
    }

    KeyboardsBackend {
        id: backend
        active: root.surfaceVisible

        onCaptureAnswered: (verb, result) => {
            if (verb === "begin") {
                beginWatchdog.stop();
                root.dispatch({ type: "begun", ok: !!result?.ok && !!result.active,
                                message: result?.error?.message ?? qsTr("Hyprland no entró en modo captura") });
                return;
            }
            root.dispatch({ type: "released", ok: !!result?.ok && !result.active,
                            message: result?.error?.message ?? qsTr("Hyprland sigue en modo captura; pulsa Super + Ctrl + Alt + Shift + Esc") });
        }
        onPreviewed: result => root.dispatch({ type: "previewed", preview: result })
        onApplied: result => {
            if (Flow.busy(root.flow))
                root.dispatch({ type: "applied", ok: !!result?.ok, stale: !!result?.stale,
                                message: result?.ok ? qsTr("Aplicado y comprobado en Hyprland · %1").arg(result.chord ?? result.message ?? "")
                                                    : result?.error ?? "" });
            else
                // Reset and delete apply straight from their buttons.
                root.dispatch({ type: "changed", ok: !!result?.ok,
                                message: result?.ok ? qsTr("%1 · comprobado en Hyprland").arg(result.message ?? "") : (result?.error ?? "") });
        }
        onBindingsChanged: {
            // Keep the selection on the same row after a refresh.
            if (root.selectedBinding)
                root.selectedBinding = backend.bindings.find(b => b.id === root.selectedBinding.id) ?? null;
        }
    }

    // A `capture begin` that never answers must not leave the editor
    // recording without the submap; a late answer is then ignored.
    Timer {
        id: beginWatchdog
        interval: 5000
        onTriggered: root.dispatch({ type: "begun", ok: false, message: qsTr("Hyprland no respondió al entrar en modo captura") })
    }

    NumberAnimation {
        id: captureCountdown
        target: root
        property: "captureRemaining"
        from: 1
        to: 0
        duration: backend.captureTimeoutMs
        onFinished: root.dispatch({ type: "timeout", message: qsTr("Tiempo agotado; el atajo no cambió") })
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onClicked: mouse => {
            const outside = mouse.x < panel.x || mouse.x >= panel.x + panel.width
                || mouse.y < panel.y || mouse.y >= panel.y + panel.height;
            if (outside && !root.listening && !Flow.busy(root.flow))
                root.closeSurface();
        }
    }

    Rectangle {
        id: panel
        width: Math.min(root.panelMaxWidth, parent.width - 96)
        height: Math.min(root.panelMaxHeight, parent.height - 72)
        x: Math.round((parent.width - width) / 2)
        y: Math.round((parent.height - height) / 2)
        radius: CortetsuDesign.radiusSurface
        color: Qt.alpha(CortetsuDesign.colorTetsu, 0.97)
        border.width: 1
        border.color: Qt.alpha(CortetsuDesign.colorOutlineVariant, 0.22)
        clip: true

        Item {
            anchors.fill: parent
            anchors.margins: CortetsuDesign.spacingComfortable

            Row {
                id: header
                width: parent.width
                height: 50
                spacing: CortetsuDesign.spacingStandard

                CortetsuIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "keyboard"
                    color: CortetsuDesign.colorPrimary
                    iconSize: CortetsuTypography.iconLargePx
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - x - refreshButton.width - closeButton.width - CortetsuDesign.spacingStandard * 2
                    spacing: 1

                    CortetsuText {
                        width: parent.width
                        text: qsTr("Atajos y teclados")
                        textSize: CortetsuTypography.titleLargePx
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }
                    CortetsuText {
                        width: parent.width
                        text: backend.bindingsError || backend.keysError
                            || (backend.inventory === null ? qsTr("Buscando teclados…")
                                : qsTr("%1 teclados · %2 atajos · %3 teclas libres")
                                    .arg(backend.keyboards.filter(k => k.kind !== "system-buttons").length)
                                    .arg(backend.bindings.length).arg(backend.spare.length))
                        color: backend.bindingsError || backend.keysError ? CortetsuDesign.colorWarning : CortetsuDesign.colorOnSurfaceVariant
                        textSize: CortetsuTypography.labelSmallPx
                        elide: Text.ElideRight
                    }
                }

                CortetsuButton {
                    id: refreshButton
                    objectName: "keyboardsRefresh"
                    anchors.verticalCenter: parent.verticalCenter
                    compact: true
                    icon: "refresh"
                    disabled: root.listening || backend.loading
                    tooltipText: qsTr("Actualizar (R)")
                    Accessible.name: qsTr("Actualizar")
                    onClicked: backend.refresh()
                }
                CortetsuButton {
                    id: closeButton
                    objectName: "keyboardsClose"
                    anchors.verticalCenter: parent.verticalCenter
                    compact: true
                    icon: "close"
                    disabled: Flow.busy(root.flow)
                    tooltipText: qsTr("Cerrar (Esc)")
                    Accessible.name: qsTr("Cerrar")
                    onClicked: root.closeSurface()
                }
            }

            Row {
                id: columns
                anchors.top: header.bottom
                anchors.topMargin: CortetsuDesign.spacingStandard
                anchors.bottom: parent.bottom
                width: parent.width
                spacing: CortetsuDesign.spacingStandard

                Flickable {
                    width: Math.min(root.deviceColumnMax, Math.round(columns.width * 0.22))
                    height: parent.height
                    contentHeight: devices.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    DeviceList {
                        id: devices
                        width: parent.width
                        implicitHeight: childrenRect.height
                        keyboards: backend.keyboards
                        loaded: backend.inventory !== null
                        error: backend.inventoryError
                        selectedId: root.deviceId
                        onSelected: id => { if (!root.listening) root.deviceId = id; }
                    }
                }

                Item {
                    id: center
                    width: columns.width - editor.width - Math.min(root.deviceColumnMax, Math.round(columns.width * 0.22)) - columns.spacing * 2
                    height: parent.height

                    Row {
                        id: tabRow
                        height: 40
                        spacing: CortetsuDesign.spacingUnit

                        Repeater {
                            model: root.tabs
                            delegate: Item {
                                id: tabDelegate
                                required property var modelData
                                required property int index
                                width: tab.implicitWidth
                                height: tabRow.height

                                CortetsuTab {
                                    id: tab
                                    anchors.fill: parent
                                    index: tabDelegate.index
                                    count: root.tabs.length
                                    label: tabDelegate.modelData.label
                                    icon: tabDelegate.modelData.icon
                                    selected: root.currentTab === tabDelegate.index
                                    disabled: root.listening
                                    onActivated: root.currentTab = tabDelegate.index
                                    onPreviousRequested: root.currentTab = Math.max(0, root.currentTab - 1)
                                    onNextRequested: root.currentTab = Math.min(root.tabs.length - 1, root.currentTab + 1)
                                }
                            }
                        }
                    }

                    CortetsuSearchBar {
                        id: search
                        anchors.top: tabRow.bottom
                        anchors.topMargin: CortetsuDesign.spacingCompact
                        width: parent.width
                        visible: root.currentTab === 0
                        compact: true
                        placeholderText: qsTr("Filtrar por acción o combinación")
                        onTextChanged: root.query = text
                    }

                    ListView {
                        id: list
                        anchors.top: root.currentTab === 0 ? search.bottom : tabRow.bottom
                        anchors.topMargin: CortetsuDesign.spacingCompact
                        anchors.bottom: parent.bottom
                        width: parent.width
                        clip: true
                        spacing: CortetsuDesign.spacingUnit
                        boundsBehavior: Flickable.StopAtBounds
                        model: root.currentTab === 0 ? root.shortcutRows : root.currentTab === 1 ? root.specialRows : root.spareRows

                        CortetsuStateMessage {
                            anchors.centerIn: parent
                            width: Math.min(parent.width - 32, 360)
                            visible: list.count === 0
                            kind: backend.loading && backend.bindings.length === 0 ? "loading"
                                : (backend.bindingsError || backend.keysError) ? "error" : "empty"
                            title: kind === "loading" ? qsTr("Leyendo atajos y teclas…")
                                : kind === "error" ? qsTr("No se pudo leer la configuración")
                                : root.currentTab === 2 ? qsTr("No hay teclas dedicadas libres")
                                : root.currentTab === 1 ? qsTr("Este teclado no declara teclas especiales")
                                : qsTr("Ningún atajo coincide")
                            detail: kind === "error" ? (backend.bindingsError || backend.keysError)
                                : root.currentTab === 2 ? qsTr("Las teclas de escritura no se proponen. Conecta otro teclado o elige otro.")
                                : ""
                        }

                        delegate: root.currentTab === 0 ? shortcutRow : keyRow

                        Component {
                            id: shortcutRow
                            SelectableRow {
                                id: row
                                required property var modelData
                                readonly property var appEntry: root.appForBinding(row.modelData)
                                readonly property bool shared: (row.modelData.conflicts ?? []).length > 0
                                width: list.width
                                image: row.appEntry ? Quickshell.iconPath(row.appEntry.icon, true) : ""
                                icon: row.modelData.command ? "terminal" : "keyboard_command_key"
                                title: row.appEntry?.name ?? row.modelData.label
                                detail: row.shared ? qsTr("También lo usa: %1").arg(row.modelData.conflicts.join(", "))
                                    : !row.modelData.active ? qsTr("Desactivado") : (row.modelData.description ?? "")
                                warning: row.shared
                                muted: !row.modelData.active
                                selected: root.selectedBinding?.id === row.modelData.id
                                onClicked: root.selectBinding(row.modelData)

                                KeyCaps {
                                    parts: Model.parts(row.modelData.chord ?? "")
                                    dim: !row.modelData.active
                                }
                            }
                        }

                        Component {
                            id: keyRow
                            SelectableRow {
                                id: keyItem
                                required property var modelData
                                readonly property var states: keyItem.modelData.states ?? []
                                width: list.width
                                icon: Model.kindIcon(backend.keyboards.find(k => k.id === keyItem.modelData.device)?.kind ?? "")
                                title: keyItem.modelData.label
                                detail: [keyItem.modelData.deviceLabel,
                                         `${keyItem.modelData.name} · ${keyItem.modelData.keysym ?? qsTr("sin keysym")}`,
                                         Model.confidenceLabel(keyItem.modelData.confidence)].join(" · ")
                                selected: root.selectedKey?.code === keyItem.modelData.code
                                    && root.selectedKey?.device === keyItem.modelData.device
                                onClicked: root.selectKey(keyItem.modelData)

                                CortetsuText {
                                    text: keyItem.states.filter(s => s !== "DECLARED").map(s => Model.stateLabel(s)).join(" · ")
                                    textSize: CortetsuTypography.labelSmallPx
                                    color: keyItem.states.indexOf("CANDIDATE") >= 0 ? CortetsuDesign.colorPrimary
                                        : CortetsuDesign.colorOnSurfaceVariant
                                }
                            }
                        }
                    }
                }

                EditorPanel {
                    id: editor
                    width: Math.min(root.editorColumnMax, Math.round(columns.width * 0.31))
                    height: parent.height
                    binding: root.selectedBinding
                    key: root.selectedKey
                    flow: root.flow
                    targetLabel: root.targetLabel
                    remaining: root.captureRemaining
                    lastKeyDetail: root.lastKeyDetail
                    busy: Flow.busy(root.flow) || backend.writing
                    onEditRequested: root.startCapture()
                    onConfirmRequested: root.dispatch({ type: "confirm" })
                    onCancelRequested: root.cancel(qsTr("Cambio cancelado; el atajo no cambió"))
                    onResetRequested: root.runChange(["reset", root.selectedBinding.id])
                    onDeleteRequested: root.runChange(["delete", root.selectedBinding.id])
                    onAssignRequested: app => root.assignApp(app)
                }
            }
        }
    }
}
