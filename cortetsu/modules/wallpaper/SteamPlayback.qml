pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import ".."
import "../../services"
import "../../components"
import "../../theme"
import "../CortetsuTypography.js" as CortetsuTypography

// Playback controls for one Steam Workshop entry. Every verdict shown here
// comes from the Rust supervisor: compatibility from its backend inspection,
// state from its per-monitor snapshot. Nothing reads as applied until the
// supervisor reports the renderer's surface on screen.
Column {
    id: root

    required property var entry
    required property var assets
    property string monitor: Quickshell.screens.length ? Quickshell.screens[0].name : ""
    property int fps: 30
    property int volume: 15
    property bool muted: false
    property string scaling: "fill"
    property string gpu: "integrated"
    property bool battery: true
    property bool fullscreen: true
    property bool restore: true
    property var values: ({})

    readonly property var output: Orbital.output(monitor)
    readonly property string phase: output.state || "stopped"
    readonly property bool busy: phase === "preparing" || phase === "applying"
    readonly property var verdict: entry ? Orbital.inspections[entry.location] : undefined
    readonly property bool supported: verdict?.supported === true
    readonly property bool engineReady: (Orbital.backends.find(b => b.id === "almamu-wayland")?.available) === true
    readonly property bool showsThis: !!entry && output.selection?.location === entry.location
    readonly property var playlist: Orbital.preferences.playlists?.[monitor] || ({ entries: [], interval: 300, shuffle: false, enabled: false })
    readonly property var profiles: Orbital.preferences.profiles?.[monitor] || ({})
    readonly property var editable: Object.keys(entry?.properties || {})
        .filter(key => ["bool", "slider", "combo"].includes(entry.properties[key]?.type)).slice(0, 64)

    readonly property var phaseLabels: ({
        preparing: qsTr("Preparando"), applying: qsTr("Aplicando"), active: qsTr("Activo"),
        stopped: qsTr("Detenido · fondo estático"), paused: qsTr("En pausa · fondo estático"), error: qsTr("Error · fondo estático")
    })
    readonly property var pauseLabels: ({
        battery: qsTr("Con batería se mantiene el fondo estático."),
        "monitor-off": qsTr("El monitor está apagado."),
        context: qsTr("El contexto activo mantiene el fondo estático."),
        resume: qsTr("Volviendo de la suspensión; se reanuda en unos segundos.")
    })
    readonly property var errorLabels: ({
        busy: qsTr("Este monitor ya está cambiando de fondo."),
        disconnected: qsTr("El monitor se desconectó."),
        "foreign-owner": qsTr("Otro programa ya dibuja el fondo de este monitor. Ciérralo antes de aplicar."),
        unavailable: qsTr("Falta un recurso del motor."),
        invalid: qsTr("El proyecto o los ajustes no son válidos."),
        incompatible: qsTr("Este motor no admite el fondo."),
        missing: qsTr("No hay nada guardado que restaurar."),
        limit: qsTr("Se alcanzó un límite de la biblioteca."),
        persist: qsTr("No se pudo guardar la preferencia."),
        spawn: qsTr("El motor no pudo iniciarse."),
        "renderer-exited": qsTr("El motor se cerró."),
        "surface-lost": qsTr("El motor dejó de mostrarse en este monitor."),
        "transition-timeout": qsTr("El motor no mostró nada en 15 segundos."),
        restore: qsTr("No se pudo restaurar el fondo animado."),
        compositor: qsTr("Hyprland no respondió."),
        supervisor: qsTr("El supervisor de Orbital se cerró."),
        unavailable_supervisor: qsTr("El supervisor de Orbital no está disponible.")
    })

    function describe(error: var): string {
        if (!error) return "";
        const summary = errorLabels[error.code] || qsTr("Error");
        return error.message ? summary + "\n" + error.message : summary;
    }
    function typeLimits(): string {
        if (entry?.type === "scene")
            return qsTr("Escena con el renderizador OpenGL de Almamu. Algunos shaders, efectos, SceneScript y reacciones al audio pueden verse distinto que en Windows.");
        return qsTr("Vídeo con libmpv. Con la GPU integrada se decodifica por software.");
    }
    function compatibilityText(): string {
        if (!entry) return "";
        if (!Orbital.available) return qsTr("Iniciando el supervisor de Orbital…");
        if (!verdict) return qsTr("Comprobando compatibilidad…");
        if (!engineReady) return qsTr("El motor linux-wallpaperengine no está instalado en /opt/linux-wallpaperengine.");
        if (supported) return typeLimits();
        if (entry.type === "web")
            return qsTr("Incompatible: el CEF instalado se ejecuta sin sandbox y Orbital no abre páginas no confiables sin aislamiento.");
        if (entry.type === "image")
            return qsTr("Es una imagen: aplícala desde la biblioteca estática para conservar la paleta de colores.");
        return (verdict.code === "invalid" ? qsTr("Proyecto incompleto: ") : qsTr("Incompatible: ")) + verdict.message;
    }
    function loadPreferences(): void {
        const s = Orbital.preferences.monitors?.[monitor];
        fps = s?.fps || 30;
        volume = s?.volume ?? 15;
        muted = s?.muted || false;
        scaling = s?.scaling || "fill";
        gpu = s?.gpu || "integrated";
        battery = s?.pauseOnBattery ?? true;
        fullscreen = s?.pauseFullscreen ?? true;
        restore = s?.restoreOnStart ?? true;
        values = s && entry && s.location === entry.location ? (s.properties || {}) : ({});
    }
    function selection(): var {
        return { location: entry.location, backend: "almamu-wayland", assets: assets[0] || "", fps, volume, muted,
            scaling, gpu, properties: values, pauseOnBattery: battery, pauseFullscreen: fullscreen, restoreOnStart: restore };
    }
    function setValue(key: string, value: var): void {
        const next = Object.assign({}, values);
        next[key] = value;
        values = next;
    }
    function updatePlaylist(changes: var): void {
        Orbital.send({ op: "playlist", monitor, playlist: Object.assign({}, playlist, changes) });
    }

    onMonitorChanged: loadPreferences()
    onEntryChanged: { loadPreferences(); if (entry) Orbital.inspect(entry.location); }
    Component.onCompleted: Orbital.ensure()
    Connections {
        target: Orbital
        function onAvailableChanged(): void {
            if (!Orbital.available) return;
            root.loadPreferences();
            if (root.entry) Orbital.inspect(root.entry.location);
        }
    }

    spacing: CortetsuDesign.spacingStandard

    // --- Status of the chosen monitor ---------------------------------------
    Rectangle {
        width: parent.width
        height: statusColumn.implicitHeight + CortetsuDesign.spacingStandard * 2
        radius: CortetsuDesign.radiusSmall
        color: CortetsuDesign.colorSurfaceHigh
        border.width: 1
        border.color: root.phase === "error" ? CortetsuDesign.colorVermillion : CortetsuDesign.colorOutlineVariant

        Column {
            id: statusColumn
            x: CortetsuDesign.spacingStandard
            y: CortetsuDesign.spacingStandard
            width: parent.width - CortetsuDesign.spacingStandard * 2
            spacing: CortetsuDesign.spacingUnit

            Row {
                spacing: CortetsuDesign.spacingCompact
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 8; height: 8; radius: height / 2
                    color: root.phase === "active" ? CortetsuDesign.colorSuccess
                        : root.phase === "error" ? CortetsuDesign.colorVermillion
                        : root.busy ? CortetsuDesign.colorPrimary : CortetsuDesign.colorOutline
                }
                CortetsuText {
                    text: qsTr("%1 · %2").arg(root.monitor).arg(root.phaseLabels[root.phase] || root.phase)
                    font.weight: Font.DemiBold
                }
            }
            CortetsuText {
                width: parent.width
                visible: !!root.output.selection
                elide: Text.ElideMiddle
                text: (root.showsThis ? qsTr("Este fondo") : root.output.selection?.location.split("/").pop() || "")
                    + (root.output.restarts > 0 ? " · " + qsTr("reiniciado %n vez/veces", "", root.output.restarts) : "")
                color: CortetsuDesign.colorOnSurfaceVariant
                textSize: CortetsuTypography.bodySmallPx
            }
            CortetsuText {
                width: parent.width
                visible: root.phase === "paused" && !!root.output.pauseReason
                wrapMode: Text.Wrap
                text: root.pauseLabels[root.output.pauseReason] || ""
                color: CortetsuDesign.colorOnSurfaceVariant
                textSize: CortetsuTypography.bodySmallPx
            }
            CortetsuText {
                width: parent.width
                visible: text.length > 0
                wrapMode: Text.Wrap
                maximumLineCount: 6
                elide: Text.ElideRight
                text: root.describe(root.output.error) || (Orbital.error ? root.describe({ code: Orbital.errorCode === "unavailable" ? "unavailable_supervisor" : Orbital.errorCode, message: Orbital.error }) : "")
                color: CortetsuDesign.colorVermillion
                textSize: CortetsuTypography.bodySmallPx
            }
        }
    }

    CortetsuText {
        width: parent.width
        wrapMode: Text.Wrap
        text: root.compatibilityText()
        color: root.supported ? CortetsuDesign.colorOnSurfaceVariant : CortetsuDesign.colorOnSurface
        textSize: CortetsuTypography.bodySmallPx
    }

    // --- Monitor and actions -------------------------------------------------
    CortetsuSectionHeader { title: qsTr("Monitor"); detail: qsTr("Cada pantalla tiene su propio fondo") }
    Flow {
        width: parent.width
        spacing: CortetsuDesign.spacingCompact
        Repeater {
            model: Quickshell.screens
            delegate: CortetsuButton {
                required property var modelData
                compact: true
                icon: "monitor"
                label: modelData.name
                active: root.monitor === modelData.name
                tooltipText: Orbital.output(modelData.name).state === "active" ? qsTr("Fondo animado activo") : qsTr("Fondo estático")
                onClicked: root.monitor = modelData.name
            }
        }
    }
    Flow {
        width: parent.width
        spacing: CortetsuDesign.spacingCompact
        CortetsuButton {
            objectName: "orbitalApply"
            icon: root.busy ? "hourglass_top" : "play_arrow"
            label: root.busy ? root.phaseLabels[root.phase] + "…" : root.showsThis && root.phase === "active" ? qsTr("Aplicar cambios") : qsTr("Aplicar")
            active: true
            disabled: !Orbital.available || !root.supported || !root.engineReady || root.busy || !root.monitor || !root.assets.length
            tooltipText: !root.assets.length ? qsTr("No se encontraron los assets de Wallpaper Engine en Steam") : ""
            onClicked: Orbital.apply(root.monitor, root.selection())
        }
        CortetsuButton {
            icon: "stop"
            label: qsTr("Detener")
            disabled: !Orbital.available || root.phase === "stopped"
            tooltipText: qsTr("Vuelve al fondo estático en este monitor")
            onClicked: Orbital.send({ op: "stop", monitor: root.monitor })
        }
        CortetsuButton {
            icon: "history"
            label: qsTr("Restaurar anterior")
            disabled: !Orbital.available || root.busy || !Orbital.preferences.previous?.[root.monitor]
            tooltipText: Orbital.preferences.previous?.[root.monitor]?.location.split("/").pop() || ""
            onClicked: Orbital.send({ op: "restore", monitor: root.monitor })
        }
        // The scheme follows the animated wallpaper while it plays here. Off
        // the screen it would be overwritten by the static one, so only the
        // wallpaper active on this monitor offers it.
        CortetsuButton {
            objectName: "orbitalColours"
            icon: Orbital.colourState === "applied" ? "check" : "palette"
            label: Orbital.colourState === "busy" ? qsTr("Aplicando colores…") : qsTr("Usar sus colores")
            // Same condition as Ajustes → Colores → «Esquema según el fondo».
            readonly property bool followsWallpaper: CortetsuConfig.smartScheme && CortetsuColours.origin !== "manual"
            disabled: !root.showsThis || root.phase !== "active" || !root.entry?.preview
                || !followsWallpaper || Orbital.colourState === "busy"
            tooltipText: !followsWallpaper ? qsTr("Activa «Esquema según el fondo» en Ajustes → Colores")
                : !root.entry?.preview ? qsTr("Este fondo no trae imagen de portada")
                : root.phase !== "active" || !root.showsThis ? qsTr("Disponible con este fondo activo en el monitor")
                : Orbital.colourState === "refused" ? qsTr("Hay un esquema elegido a mano; vuelve al del fondo para usar este")
                : Orbital.colourState === "error" ? qsTr("No se pudieron extraer los colores: %1").arg(Orbital.colourError)
                : qsTr("Toma la paleta de su portada; al detenerlo vuelven los colores del fondo estático")
            onClicked: Orbital.adoptColours(root.entry.preview)
        }
        CortetsuButton {
            icon: "star"
            label: qsTr("Favorito")
            active: (Orbital.preferences.favorites || []).includes(root.entry?.location)
            disabled: !Orbital.available || !root.entry
            onClicked: Orbital.send({ op: "favorite", location: root.entry.location })
        }
    }

    // --- Playback settings ---------------------------------------------------
    CortetsuSectionHeader { title: qsTr("Reproducción"); detail: qsTr("Se aplican al pulsar Aplicar; el motor se reinicia solo en este monitor") }
    CortetsuText { text: qsTr("Límite de FPS: %1").arg(root.fps); textSize: CortetsuTypography.bodySmallPx }
    CortetsuSlider { width: parent.width; from: 1; to: 144; step: 1; value: root.fps; accessibleName: qsTr("Límite de FPS"); accessibleValue: root.fps + " FPS"; onMoved: value => root.fps = Math.round(value) }
    Flow {
        width: parent.width
        spacing: CortetsuDesign.spacingCompact
        Repeater {
            model: [15, 24, 30, 60]
            delegate: CortetsuButton { required property int modelData; compact: true; label: modelData + " FPS"; active: root.fps === modelData; onClicked: root.fps = modelData }
        }
    }
    CortetsuText { text: root.muted ? qsTr("Volumen: silenciado") : qsTr("Volumen: %1 %").arg(root.volume); textSize: CortetsuTypography.bodySmallPx }
    CortetsuSlider { width: parent.width; from: 0; to: 100; step: 1; value: root.volume; disabled: root.muted; accessibleName: qsTr("Volumen"); accessibleValue: root.volume + " %"; onMoved: value => root.volume = Math.round(value) }
    Flow {
        width: parent.width
        spacing: CortetsuDesign.spacingCompact
        CortetsuButton { compact: true; icon: root.muted ? "volume_off" : "volume_up"; label: qsTr("Silencio"); active: root.muted; onClicked: root.muted = !root.muted }
        Repeater {
            model: [{ key: "fill", label: qsTr("Rellenar") }, { key: "fit", label: qsTr("Ajustar") }, { key: "stretch", label: qsTr("Estirar") }]
            delegate: CortetsuButton {
                required property var modelData
                compact: true; label: modelData.label; active: root.scaling === modelData.key
                onClicked: root.scaling = modelData.key
            }
        }
    }

    CortetsuSectionHeader { title: qsTr("Energía") }
    Flow {
        width: parent.width
        spacing: CortetsuDesign.spacingCompact
        CortetsuButton { compact: true; icon: "memory"; label: qsTr("GPU integrada"); active: root.gpu === "integrated"; tooltipText: qsTr("Mesa EGL y decodificación por software: la RTX no se despierta"); onClicked: root.gpu = "integrated" }
        CortetsuButton { compact: true; label: qsTr("GPU del sistema"); active: root.gpu === "system"; tooltipText: qsTr("El controlador elige la GPU y el decodificador por hardware"); onClicked: root.gpu = "system" }
        CortetsuButton { compact: true; icon: "battery_saver"; label: qsTr("Pausar con batería"); active: root.battery; onClicked: root.battery = !root.battery }
        CortetsuButton { compact: true; icon: "fullscreen"; label: qsTr("Pausar con pantalla completa"); active: root.fullscreen; onClicked: root.fullscreen = !root.fullscreen }
        CortetsuButton { compact: true; icon: "login"; label: qsTr("Restaurar al iniciar sesión"); active: root.restore; onClicked: root.restore = !root.restore }
    }

    // --- Author properties ---------------------------------------------------
    CortetsuSectionHeader {
        visible: root.editable.length > 0
        title: qsTr("Propiedades del autor")
        detail: qsTr("Interruptores, deslizadores y listas")
    }
    Repeater {
        model: root.editable
        delegate: Column {
            id: authorProperty
            required property string modelData
            readonly property var definition: root.entry.properties[modelData]
            readonly property var current: root.values[modelData] ?? definition.value
            width: root.width
            spacing: CortetsuDesign.spacingUnit
            CortetsuText {
                width: parent.width
                wrapMode: Text.Wrap
                // Authors may write HTML in labels; it is shown as plain text.
                textFormat: Text.PlainText
                text: String(authorProperty.definition.text || authorProperty.modelData).replace(/<[^>]*>/g, "")
                textSize: CortetsuTypography.bodySmallPx
            }
            CortetsuButton {
                visible: authorProperty.definition.type === "bool"
                compact: true
                label: authorProperty.current === true || authorProperty.current === 1 || authorProperty.current === "1" ? qsTr("Activado") : qsTr("Desactivado")
                active: authorProperty.current === true || authorProperty.current === 1 || authorProperty.current === "1"
                onClicked: root.setValue(authorProperty.modelData, !active)
            }
            CortetsuSlider {
                width: parent.width
                visible: authorProperty.definition.type === "slider"
                from: Number(authorProperty.definition.min ?? 0)
                to: Number(authorProperty.definition.max ?? 1)
                step: Number(authorProperty.definition.step || 0.01)
                value: Number(authorProperty.current ?? 0)
                accessibleName: authorProperty.definition.text || authorProperty.modelData
                accessibleValue: Number(authorProperty.current ?? 0).toFixed(2)
                onMoved: value => root.setValue(authorProperty.modelData, value)
            }
            Flow {
                width: parent.width
                visible: authorProperty.definition.type === "combo"
                spacing: CortetsuDesign.spacingCompact
                Repeater {
                    model: authorProperty.definition.type === "combo" ? (authorProperty.definition.options || []).slice(0, 32) : []
                    delegate: CortetsuButton {
                        required property var modelData
                        compact: true
                        label: String(modelData.label ?? modelData.value)
                        active: String(authorProperty.current) === String(modelData.value)
                        onClicked: root.setValue(authorProperty.modelData, String(modelData.value))
                    }
                }
            }
        }
    }

    // --- Library: playlist, profiles, collections ----------------------------
    CortetsuSectionHeader { title: qsTr("Rotación de %1").arg(root.monitor); detail: qsTr("%n fondo(s)", "", root.playlist.entries.length) }
    Flow {
        width: parent.width
        spacing: CortetsuDesign.spacingCompact
        CortetsuButton {
            compact: true; icon: "playlist_add"
            label: (root.playlist.entries || []).some(s => s.location === root.entry?.location) ? qsTr("Actualizar en la lista") : qsTr("Añadir a la lista")
            disabled: !Orbital.available || !root.supported || root.playlist.entries.length >= 100
            onClicked: root.updatePlaylist({ entries: root.playlist.entries.filter(s => s.location !== root.entry.location).concat([root.selection()]) })
        }
        CortetsuButton {
            compact: true; icon: "playlist_remove"; label: qsTr("Quitar de la lista")
            visible: (root.playlist.entries || []).some(s => s.location === root.entry?.location)
            onClicked: root.updatePlaylist({ entries: root.playlist.entries.filter(s => s.location !== root.entry.location), enabled: root.playlist.enabled && root.playlist.entries.length > 2 })
        }
        CortetsuButton { compact: true; icon: "autorenew"; label: qsTr("Rotar"); active: root.playlist.enabled; disabled: root.playlist.entries.length < 2; onClicked: root.updatePlaylist({ enabled: !root.playlist.enabled }) }
        CortetsuButton { compact: true; icon: "shuffle"; label: qsTr("Aleatorio"); active: root.playlist.shuffle; disabled: root.playlist.entries.length < 3; onClicked: root.updatePlaylist({ shuffle: !root.playlist.shuffle }) }
    }
    Flow {
        width: parent.width
        spacing: CortetsuDesign.spacingCompact
        Repeater {
            model: [1, 5, 15, 30, 60, 240]
            delegate: CortetsuButton {
                required property int modelData
                compact: true
                label: modelData < 60 ? qsTr("%1 min").arg(modelData) : qsTr("%1 h").arg(modelData / 60)
                active: root.playlist.interval === modelData * 60
                disabled: !Orbital.available
                onClicked: root.updatePlaylist({ interval: modelData * 60 })
            }
        }
    }
    CortetsuText {
        width: parent.width
        wrapMode: Text.Wrap
        text: qsTr("La rotación avanza mientras el monitor tiene un fondo activo. Detener la desactiva.")
        color: CortetsuDesign.colorOnSurfaceVariant
        textSize: CortetsuTypography.bodySmallPx
    }

    CortetsuSectionHeader { title: qsTr("Perfiles de %1").arg(root.monitor); detail: qsTr("Guardan el fondo activo con sus ajustes") }
    Row {
        width: parent.width
        spacing: CortetsuDesign.spacingCompact
        OrbitalField {
            id: profileName
            width: parent.width - saveProfile.width - parent.spacing
            placeholderText: qsTr("Nombre del perfil")
            maximumLength: 80
            onAccepted: if (!saveProfile.disabled) saveProfile.clicked()
        }
        CortetsuButton {
            id: saveProfile
            compact: true; icon: "bookmark_add"; label: qsTr("Guardar")
            disabled: !Orbital.available || !profileName.text.trim() || !Orbital.preferences.monitors?.[root.monitor]
            tooltipText: qsTr("Guarda el último fondo confirmado en este monitor")
            onClicked: { Orbital.send({ op: "profile-save", monitor: root.monitor, name: profileName.text.trim() }); profileName.text = ""; }
        }
    }
    Flow {
        width: parent.width
        spacing: CortetsuDesign.spacingCompact
        Repeater {
            model: Object.keys(root.profiles)
            delegate: Row {
                id: profile
                required property string modelData
                spacing: 2
                CortetsuButton { compact: true; label: profile.modelData; disabled: root.busy || !Orbital.available; tooltipText: qsTr("Aplicar este perfil"); onClicked: Orbital.send({ op: "profile-apply", monitor: root.monitor, name: profile.modelData }) }
                CortetsuButton { compact: true; icon: "close"; label: ""; tooltipText: qsTr("Borrar el perfil %1").arg(profile.modelData); disabled: !Orbital.available; onClicked: Orbital.send({ op: "profile-delete", monitor: root.monitor, name: profile.modelData }) }
            }
        }
    }

    CortetsuSectionHeader { title: qsTr("Colecciones") }
    Row {
        width: parent.width
        spacing: CortetsuDesign.spacingCompact
        OrbitalField {
            id: collectionName
            width: parent.width - toggleCollection.width - parent.spacing
            placeholderText: qsTr("Nombre de la colección")
            maximumLength: 80
            onAccepted: if (!toggleCollection.disabled) toggleCollection.clicked()
        }
        CortetsuButton {
            id: toggleCollection
            compact: true; icon: "library_add"
            label: (Orbital.preferences.collections?.[collectionName.text.trim()] || []).includes(root.entry?.location) ? qsTr("Quitar") : qsTr("Añadir")
            disabled: !Orbital.available || !root.entry || !collectionName.text.trim()
            onClicked: Orbital.send({ op: "collection", name: collectionName.text.trim(), location: root.entry.location })
        }
    }
}
