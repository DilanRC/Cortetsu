local vars = require("variables")
local fn   = require("utils.functions")

local nvibrant_apply = os.getenv("HOME") .. "/.local/bin/cortetsu-nvibrant apply --default 128"

hl.on("hyprland.start", function()
    -- Keyring and auth
    hl.exec_cmd("gnome-keyring-daemon --start --components=secrets")
    hl.exec_cmd("/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1")

    -- Clipboard history
    hl.exec_cmd("clipse -listen")

    -- Auto delete trash 30 days old
    hl.exec_cmd("trash-empty 30")

    -- Cursors
    hl.exec_cmd("hyprctl setcursor " .. vars.cursorTheme .. " " .. vars.cursorSize)
    hl.exec_cmd("gsettings set org.gnome.desktop.interface cursor-theme " .. vars.cursorTheme)
    hl.exec_cmd("gsettings set org.gnome.desktop.interface cursor-size " .. vars.cursorSize)

    -- Location provider and night light
    hl.exec_cmd("/usr/lib/geoclue-2.0/demos/agent")
    hl.exec_cmd("sleep 1 && gammastep")

    -- Forward bluetooth media commands to MPRIS
    hl.exec_cmd("mpris-proxy")

    -- Start shell
    hl.exec_cmd("systemctl --user start cortetsu-shell.service")
    hl.exec_cmd("systemctl --user start cortetsu-wallpaper-color.service")

    -- Relaunch Wallpaper Engine renderer with per-monitor args and no fullscreen pause.
    hl.exec_cmd(os.getenv("HOME") .. "/.local/bin/wallpaper-engine-render-daemon")

    -- nvidia-modeset tarda en aceptar ioctls tras el login; la unit
    -- nvibrant.service anterior esperaba lo mismo.
    hl.exec_cmd("sleep 5 && " .. nvibrant_apply)
end)

-- Reaplica el perfil de vibrance NVIDIA que edita Ajustes al conectar un
-- monitor (el arranque lo cubre hyprland.start). Sin salida NVIDIA conectada
-- no ejecuta nvibrant y no despierta la dGPU; 128 solo vale sin perfil guardado.
hl.on("monitor.added", function()
    hl.exec_cmd(nvibrant_apply)
end)

-- Resizer listeners
local function apply_resizer_rules(win)
    local float_center = {
        hl.dsp.window.float({ action = "on", window = win }),
        hl.dsp.window.center({ window = win }),
    }
    local pip_actions = fn.move_actions(win) or {}

    -- Bitwarden
    fn.resizer(win, "Bitwarden", 20, 54, float_center, true, "class")                                       -- Native app
    fn.resizer(win, "^Extension: %(Bitwarden Password Manager%) %- Bitwarden", 20, 54, float_center, false) -- Firefox
    fn.resizer(win, "nngceckbapebfimnlniiiahkandclblb", 20, 54, float_center, true, "class")                -- Chromium

    -- Picture in picture
    fn.resizer(win, "Picture[- ]in[- ][Pp]icture", 0, 0, pip_actions, false)
end

hl.on("window.title", apply_resizer_rules)
hl.on("window.open", apply_resizer_rules)
