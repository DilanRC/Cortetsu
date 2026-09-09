local fn = require("utils.functions")

-- ============================================================
-- MONITORES
-- HDMI externo a la izquierda, portátil a la derecha
-- ============================================================

-- "preferred" toma el modo nativo que cada pantalla anuncia en su propia
-- EDID (el DTD marcado preferred) — se adapta sola a lo que esté conectado
-- en el puerto: 4K@60 en la Smart TV, lo que sea nativo en cualquier otro
-- monitor/proyector. cm="hdredid" activa HDR solo si esa pantalla lo declara
-- soportado en su EDID; si no, queda en sRGB sin romper nada.
hl.monitor({
    output = "HDMI-A-1",
    mode = "1920x1080@60",
    position = "0x0",
    scale = 1,
    bitdepth = 8,
    cm = "srgb",
    sdr_eotf = "gamma22",
    supports_hdr = -1,
    supports_wide_color = -1,
})

hl.monitor({
    output = "eDP-1",
    mode = "1920x1080@144",
    -- Queda en 0x0 cuando está solo y a la derecha cuando existe HDMI-A-1.
    position = "auto-right",
    scale = 1,
    cm = "srgb",
    sdr_eotf = "gamma22",
})

-- BOE0CFD: compensación moderada para su cobertura limitada (62.5% sRGB).
-- El shader conserva los extremos 0/1 y evita saturar colores que ya son vivos.
hl.config({
    decoration = {
        screen_shader = "/home/dilan/.config/hypr/shaders/vibrance-contrast.glsl",
    },
    render = {
    cm_enabled = true,
    cm_sdr_eotf = "gamma22",
    cm_auto_hdr = 0,
},
})

-- ============================================================
-- APLICACIONES PERSONALIZADAS
-- Recuperadas del antiguo keybinds-user.conf
-- ============================================================

hl.bind(
    "SUPER + G",
    hl.dsp.exec_cmd("github-desktop")
)

hl.bind(
    "SUPER + A",
    hl.dsp.exec_cmd("claude-desktop")
)

-- ============================================================
-- Cortetsu shell bindings
-- ============================================================

-- Dock personalizado
hl.bind(
    "SUPER + D",
    hl.dsp.exec_cmd("qs -p ~/.config/quickshell/cortetsu/current ipc call customDock toggle")
)

-- Dashboard del shell
hl.bind(
    "SUPER + SHIFT + D",
    hl.dsp.global("cortetsu:dashboard")
)

-- Quick Settings Drawer. Keep this aligned with the first-party global bind
-- so the user override cannot open Utilities and QSD at the same time.
hl.bind(
    "SUPER + Slash",
    hl.dsp.global("cortetsu:qsd")
)

-- Settings Center
hl.bind(
    "SUPER + I",
    hl.dsp.global("cortetsu:settings")
)

-- Clipboard QML nativo
hl.bind(
    "SUPER + V",
    hl.dsp.global("cortetsu:clipboard")
)

hl.bind(
    "SUPER + H",
    hl.dsp.global("cortetsu:hardware")
)

hl.bind(
    "SUPER + SHIFT + C",
    hl.dsp.global("cortetsu:calendar")
)

-- Display Manager QML nativo
hl.bind(
    "SUPER + SHIFT + O",
    hl.dsp.global("cortetsu:displaymanager")
)

-- Wallpaper Manager QML nativo
hl.bind(
    "SUPER + SHIFT + W",
    hl.dsp.global("cortetsu:wallpapermanager")
)


-- ============================================================
-- BLOQUEO / SESIÓN
-- ============================================================



hl.bind(
    "SUPER + SHIFT + Q",
    -- SDDM corre en VT1; forzar el regreso evita la pantalla negra con NVIDIA.
    hl.dsp.exec_cmd("hyprshutdown --vt 1")
)

-- ============================================================
-- SCREENSHOTS
-- ============================================================

hl.bind(
    "Print",
    hl.dsp.exec_cmd("cortetsu screenshot -r -f")
)


hl.bind(
    "CTRL + Print",
    hl.dsp.exec_cmd("grimblast copy area")
)

hl.bind(
    "SUPER + Print",
    hl.dsp.exec_cmd([[sh -c 'grimblast save area - | swappy -f -']])
)

hl.bind(
    "SUPER + SHIFT + Print",
    hl.dsp.exec_cmd("/home/dilan/.local/bin/warframe-capture-inventory quick inventario")
)

hl.bind(
    "ALT + Print",
    hl.dsp.exec_cmd(
        [[sh -c 'mkdir -p "$HOME/Imagenes/Screenshots"; grimblast save active "$HOME/Imagenes/Screenshots/$(date +%Y%m%d-%H%M%S).png"']]
    )
)


-- ============================================================
-- KEYBINDS RESERVADOS PARA MODULOS QML
-- SUPER+V       -> Clipboard
-- SUPER+H       -> Hardware Center
-- SUPER+SHIFT+O -> Display Manager
-- SUPER+SHIFT+W -> Wallpaper Manager
-- SUPER+SHIFT+C -> Calendar
-- ============================================================

-- ============================================================
-- WALLPAPER ENGINE
-- ============================================================

hl.bind(
    "SUPER + W",
    hl.dsp.exec_cmd(os.getenv("HOME") .. "/.local/bin/linux-wallpaper-engine-once")
)

-- Overwolf exposes its dock as a separate blank XWayland window. Keep the
-- AlecaFrame and Warframe windows visible while parking only that dock.
hl.window_rule({
    name = "hide-overwolf-dock",
    match = {
        class = "^steam_app_230410$",
        initial_class = "^steam_app_230410$",
        title = "^$",
        initial_title = "^$",
        xwayland = true,
    },
    workspace = "special:overwolf-dock silent",
    no_initial_focus = true,
})

hl.window_rule({
    name = "hide-overwolf-exclusive-mode",
    match = {
        class = "^steam_app_230410$",
        title = "^owingameosr_Exclusive mode - index$",
        xwayland = true,
    },
    workspace = "special:overwolf-dock silent",
    no_initial_focus = true,
})

-- ============================================================
-- DWINDLE
-- ============================================================

hl.bind(
    "SUPER + J",
    hl.dsp.exec_cmd("hyprctl dispatch layoutmsg togglesplit")
)

-- ============================================================
-- WORKSPACES POR MONITOR
--
-- eDP-1:    1-10
-- HDMI-A-1: 11-20
--
-- SUPER+CTRL+1      -> 11
-- SUPER+CTRL+2      -> 12
-- ...
-- SUPER+CTRL+0      -> 20
--
-- SUPER+CTRL+SHIFT+# mueve la ventana
-- ============================================================

for i = 1, 10 do
    hl.workspace_rule({
        workspace = tostring(i),
        monitor = "eDP-1",
        default = i == 1,
        persistent = true,
    })

    hl.workspace_rule({
        workspace = tostring(i + 10),
        monitor = "HDMI-A-1",
        default = i == 1,
        persistent = true,
    })
end

-- ============================================================
-- TECLADO
-- ============================================================

hl.config({
    input = {
        kb_layout = "latam",
    },
})



for i = 1, 10 do
    local key = tostring(i % 10)
    local workspace = i + 10

    hl.bind(
        "SUPER + CTRL + " .. key,
        fn.focusws(workspace)
    )

    hl.bind(
        "SUPER + CTRL + SHIFT + " .. key,
        fn.movetows(workspace)
    )
end
