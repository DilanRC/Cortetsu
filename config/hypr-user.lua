local fn = require("utils.functions")

-- ============================================================
-- MONITORES
-- HDMI externo a la izquierda, portátil a la derecha
-- ============================================================

-- "preferred" toma el modo nativo que cada pantalla anuncia en su propia
-- EDID (el DTD marcado preferred) — se adapta sola a lo que esté conectado
-- en el puerto: 4K@60 en la Smart TV, lo que sea nativo en cualquier otro
-- monitor/proyector. cm="hdredid" activa HDR solo si esa pantalla lo declara
-- soportar en su EDID; si no, queda en sRGB sin romper nada.
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

-- Clipboard QML nativo
hl.bind(
    "SUPER + V",
    -- Resolve the live systemd-owned Quickshell PID; `qs -p` cannot discover
    -- this foreground instance reliably on the installed Quickshell version.
    hl.dsp.exec_cmd("/home/dilan/.local/bin/cortetsu shell ipc clipboard toggle")
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

    -- SUPER+SHIFT+# is the direct window-to-workspace shortcut. Keep it
    -- explicit here so the user overlay cannot be shadowed by the grouped
    -- workspace callback from hyprland/keybinds.lua.
    local move_key = "SUPER + SHIFT + " .. key
    -- On the active latam layout, slash is Shift+7. Keep QSD on that
    -- product shortcut and give workspace 7 an explicit equivalent.
    if key == "7" then
        move_key = "SUPER + SHIFT + F7"
    end
    hl.bind(move_key, fn.wsaction("move", "", i))

    hl.bind(
        "SUPER + CTRL + SHIFT + " .. key,
        hl.dsp.window.move({
            workspace = workspace
        })
    )
end

-- ============================================================
-- HYPRGLASS
-- Desactivado globalmente; solo Kitty recibe el efecto.
-- ============================================================

if hl.plugin.hyprglass then
    local hyprglass = hl.plugin.hyprglass
    local scheme = dofile(os.getenv("HOME") .. "/.config/hypr/scheme/current.lua")
    local tint_source = scheme.background
    local rgb = tint_source and tint_source:match("%x%x%x%x%x%x") or "000000"
    local tint = tonumber(rgb, 16) * 0x100 + math.floor(0.35 * 0xff + 0.5)

    hyprglass.config({
        enabled = false,
        manage_window_blur = true,
        default_theme = "dark",
        default_preset = "terminal_glass",
    })

    hyprglass.preset("terminal_glass", {
        blur_strength = 1.5,
        blur_iterations = 2,
        refraction_strength = 2.2,
        chromatic_aberration = 0.18,
        fresnel_strength = 0.35,
        specular_strength = 0.45,
        glass_opacity = 1.0,
        edge_thickness = 0.03,
        tint_color = tint,
        lens_distortion = 0.08,
        brightness = 0.95,
        contrast = 1.12,
        saturation = 0.95,
        vibrancy = 0.35,
        vibrancy_darkness = 0.25,
        adaptive_dim = 0.22,
        adaptive_boost = 0.08,
    })

    hl.window_rule({
        match = { class = "kitty" },
        tag = "+hyprglass_enabled",
    })

    hl.window_rule({
        match = { class = "kitty", title = ".*nvim.*|.*NVIM.*|.*LazyVim.*" },
        tag = "+hyprglass_enabled",
    })
end

-- ============================================================
-- WINDOW OVERVIEW
-- SUPER+TAB -> all windows / workspaces / live previews
-- ============================================================

hl.bind(
    "SUPER + TAB",
    hl.dsp.global("cortetsu:overview")
)

-- Cortetsu app shortcut: The Witcher 3: Wild Hunt (The Witcher 3 Wild Hunt)
hl.bind(
    "CTRL + End",
    hl.dsp.exec_cmd([[steam steam://rungameid/292030]])
)

-- Cortetsu app shortcut: ChatGPT (chatgpt)
hl.bind(
    "CTRL + Down",
    hl.dsp.exec_cmd([[chatgpt]])
)
