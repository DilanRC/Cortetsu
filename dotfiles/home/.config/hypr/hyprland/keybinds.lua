local vars = require("variables")
local fn   = require("utils.functions")


-- Flags
local locked           = { locked = true }
local mouse            = { mouse = true }
local release          = { release = true }
local repeating        = { repeating = true }
local locked_repeating = { locked = true, repeating = true }

local function normalise_keybind(key)
    return key:gsub("%s+", ""):lower()
end

local function repeating_unless_mouse(key)
    return not normalise_keybind(key):find("mouse", 1, true) and repeating or nil
end

local function flatten_keybinds(keybinds, keys)
    keys = keys or {}

    if type(keybinds) == "table" then
        for _, keybind in ipairs(keybinds) do
            flatten_keybinds(keybind, keys)
        end
    elseif keybinds ~= nil then
        keys[#keys + 1] = keybinds
    end

    return keys
end

-- A bind created from a kb* variable carries its name as description, so
-- `hyprctl binds -j` shows which action owns a chord. cortetsu-keybinds checks
-- its edits by these tags (VAR_TAG there). Only an exact match to one
-- variable's value is tagged: a shared or literal chord stays untagged.
local function variable_for(keybinds)
    local found
    for name, value in pairs(vars) do
        if type(name) == "string" and name:match("^kb") and rawequal(value, keybinds) then
            if found then
                return nil
            end
            found = name
        end
    end
    return found
end

local function create_bind(keybinds, action, flags)
    local get_flags = type(flags) == "function" and flags or function()
        return flags
    end

    local variable = variable_for(keybinds)
    for _, key in ipairs(flatten_keybinds(keybinds)) do
        local options = {}
        for option, value in pairs(get_flags(key) or {}) do
            options[option] = value
        end
        if variable and not options.description then
            options.description = "cortetsu:" .. variable
        end
        hl.bind(key, action, options)
    end
end

-- Launcher
local launcher_default = normalise_keybind("SUPER + SUPER_L")
create_bind(
    vars.kbLauncher,
    hl.dsp.global("cortetsu:launcher"),
    function(key)
        return normalise_keybind(key) == launcher_default and release or nil
    end
)

-- Misc
create_bind(vars.kbSession, hl.dsp.global("cortetsu:session"))
create_bind(vars.kbShowSidebar, hl.dsp.global("cortetsu:sidebar"))
create_bind(vars.kbFocusToast, hl.dsp.global("cortetsu:focusToast"))
create_bind(vars.kbClearNotifs, hl.dsp.global("cortetsu:clearNotifs"), locked)
create_bind(vars.kbShowPanels, hl.dsp.global("cortetsu:showall"))
create_bind(vars.kbLock, hl.dsp.global("cortetsu:lock"))
create_bind(
    { "SUPER + SLASH", "SUPER + SHIFT + 7" },
    hl.dsp.global("cortetsu:osd")
)
create_bind("SUPER + I", hl.dsp.global("cortetsu:settings"))
-- Restore lock
create_bind(vars.kbRestoreLock, function()
    hl.dispatch(hl.dsp.exec_cmd("systemctl --user start cortetsu-shell.service"))
    hl.dispatch(hl.dsp.global("cortetsu:lock"))
end)

-- Kill/restart
create_bind("CTRL + SUPER + SHIFT + R", hl.dsp.exec_cmd("systemctl --user stop cortetsu-shell.service"), release)
create_bind(
    "CTRL + SUPER + ALT + R",
    hl.dsp.exec_cmd("systemctl --user restart cortetsu-shell.service"),
    release
)

for i = 1, 10 do
    local key = i % 10 -- 10 maps to key 0
    create_bind(vars.kbGoToWs .. " + " .. key, fn.wsaction("focus", "", i))
    create_bind(vars.kbMoveWinToWs .. " + " .. key, fn.wsaction("move", "", i))
    create_bind(vars.kbGoToWsGroup .. " + " .. key, fn.wsaction("focus", "group", i))
    create_bind(vars.kbMoveWinToWsGroup .. " + " .. key, fn.wsaction("move", "group", i))
end

-- Go to workspace -1/+1
create_bind(vars.kbPrevWs, hl.dsp.focus({ workspace = "-1" }), repeating_unless_mouse)
create_bind(vars.kbNextWs, hl.dsp.focus({ workspace = "+1" }), repeating_unless_mouse)

-- Go to workspace group -1/+1
create_bind(vars.kbPrevWsGroup, hl.dsp.focus({ workspace = "-10" }), repeating_unless_mouse)
create_bind(vars.kbNextWsGroup, hl.dsp.focus({ workspace = "+10" }), repeating_unless_mouse)

-- Move window to workspace -1/+1
create_bind(vars.kbMoveWinToWsNext, hl.dsp.window.move({ workspace = "+1" }), repeating_unless_mouse)
create_bind(vars.kbMoveWinToWsPrev, hl.dsp.window.move({ workspace = "-1" }), repeating_unless_mouse)

-- Move window to/from special workspace
create_bind(vars.kbMoveWinToWsSpecial, hl.dsp.window.move({ workspace = "special:special" }))
create_bind(vars.kbMoveWinFromWsSpecial, hl.dsp.window.move({ workspace = "e+0" }))

-- Window groups
create_bind(vars.kbWindowCycleNext, hl.dsp.window.cycle_next(), repeating)
create_bind(vars.kbWindowCyclePrev, hl.dsp.window.cycle_next({ next = false }), repeating)
create_bind(vars.kbWindowGroupCycleNext, hl.dsp.group.next(), repeating)
create_bind(vars.kbWindowGroupCyclePrev, hl.dsp.group.prev(), repeating)
create_bind(vars.kbToggleGroup, hl.dsp.group.toggle())
create_bind(vars.kbUngroup, hl.dsp.window.move({ out_of_group = true }))
create_bind(vars.kbGroupLockActive, hl.dsp.group.lock_active())

-- Window actions
for _, dir in ipairs({ "left", "right", "up", "down" }) do
    create_bind("SUPER + " .. dir, hl.dsp.focus({ direction = dir }))
    create_bind("SUPER + SHIFT + " .. dir, hl.dsp.window.move({ direction = dir }))
end

create_bind(vars.kbWindowDecreaseWidth, fn.resize_active_window(-10, 0), repeating)
create_bind(vars.kbWindowIncreaseWidth, fn.resize_active_window(10, 0), repeating)
create_bind(vars.kbWindowDecreaseHeight, fn.resize_active_window(0, -10), repeating)
create_bind(vars.kbWindowIncreaseHeight, fn.resize_active_window(0, 10), repeating)

create_bind({ vars.kbMoveWindow, "SUPER + mouse:272" }, hl.dsp.window.drag(), mouse)
create_bind({ vars.kbResizeWindow, "SUPER + mouse:273" }, hl.dsp.window.resize(), mouse)
create_bind(vars.kbCenterWindow, hl.dsp.window.center())
create_bind(vars.kbNormalizeWindow, function()
    hl.dispatch(hl.dsp.window.resize(fn.resize_by_screen(55, 70)))
    hl.dispatch(hl.dsp.window.center())
end)
create_bind(vars.kbWindowPip, function()
    local a = hl.get_active_window()
    if a then
        local pip = fn.move_actions(a) or {}
        if not a.floating then table.insert(pip, 1, hl.dsp.window.float()) end
        table.insert(pip, hl.dsp.window.pin({ action = "on", window = "address:" .. a.address }))

        for _, x in ipairs(pip) do
            hl.dispatch(x)
        end
    end
end)
create_bind(vars.kbPinWindow, hl.dsp.window.pin())
create_bind(vars.kbWindowFullscreen, hl.dsp.window.fullscreen({ mode = "fullscreen" }))
create_bind(vars.kbWindowBorderedFullscreen, hl.dsp.window.fullscreen({ mode = "maximized" }))
create_bind(vars.kbToggleWindowFloating, hl.dsp.window.float())
create_bind(vars.kbCloseWindow, hl.dsp.window.close())

-- Special workspace toggles
create_bind(vars.kbSpecialWs, fn.toggle("specialws"))
create_bind(vars.kbSystemMonitorWs, fn.toggle("sysmon"))
create_bind(vars.kbMusicWs, fn.toggle("music"))
create_bind(vars.kbCommunicationWs, fn.toggle("communication"))
create_bind(vars.kbTodoWs, fn.toggle("todo"))

-- Apps
create_bind(vars.kbTerminal, hl.dsp.exec_cmd(vars.terminal))
create_bind(vars.kbBrowser, hl.dsp.exec_cmd(vars.browser))
create_bind(vars.kbEditor, hl.dsp.exec_cmd(vars.editor))
create_bind(vars.kbFileExplorer, hl.dsp.exec_cmd(vars.fileExplorer))
create_bind(vars.kbAudioSettings, hl.dsp.exec_cmd(vars.audioSettings))

-- Utilities
-- Print keeps the existing frozen-region behavior; all screenshot ownership
-- remains in this canonical keybind module. Not `locked`: nothing behind the
-- lock screen should be captured.
create_bind(vars.kbScreenshot, hl.dsp.exec_cmd("cortetsu screenshot -r -f"))
-- Freeze and region shortcuts target the first-party AreaPicker receiver.
-- The Cortetsu runtime exposes both names through its picker IPC handler.
create_bind(vars.kbScreenshotFreeze, hl.dsp.global("cortetsu:screenshotFreeze"))
create_bind(vars.kbScreenshotRegion, hl.dsp.global("cortetsu:screenshot"))
create_bind(vars.kbRecord, hl.dsp.exec_cmd("cortetsu-record start"))
create_bind(vars.kbRecordSound, hl.dsp.exec_cmd("cortetsu-record start -s"))
create_bind(vars.kbRecordRegion, hl.dsp.exec_cmd("cortetsu-record start -r"))
create_bind(vars.kbColorPicker, hl.dsp.exec_cmd("hyprpicker -a"))

-- Brightness
create_bind("XF86MonBrightnessUp", hl.dsp.global("cortetsu:brightnessUp"), locked)
create_bind("XF86MonBrightnessDown", hl.dsp.global("cortetsu:brightnessDown"), locked)

-- Media
create_bind({ vars.kbMediaToggle, "XF86AudioPlay", "XF86AudioPause" }, hl.dsp.global("cortetsu:mediaToggle"), locked)
create_bind({ vars.kbMediaNext, "XF86AudioNext" }, hl.dsp.global("cortetsu:mediaNext"), locked)
create_bind({ vars.kbMediaPrev, "XF86AudioPrev" }, hl.dsp.global("cortetsu:mediaPrev"), locked)
create_bind({ vars.kbMediaStop, "XF86AudioStop" }, hl.dsp.global("cortetsu:mediaStop"), locked)

-- Volume
create_bind({ vars.kbVolumeMute, "XF86AudioMute" }, hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"), locked)
create_bind("XF86AudioMicMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"), locked)
create_bind(
    "XF86AudioRaiseVolume",
    hl.dsp.exec_cmd(
        "wpctl set-mute @DEFAULT_AUDIO_SINK@ 0; wpctl set-volume -l " ..
        (vars.volumeMax / 100) .. " @DEFAULT_AUDIO_SINK@ " .. vars.volumeStep .. "%+"
    ),
    locked_repeating
)
create_bind(
    "XF86AudioLowerVolume",
    hl.dsp.exec_cmd(
        "wpctl set-mute @DEFAULT_AUDIO_SINK@ 0; wpctl set-volume @DEFAULT_AUDIO_SINK@ " .. vars.volumeStep .. "%-"
    ),
    locked_repeating
)

-- Sleep and keep-awake
create_bind(vars.kbSleep, hl.dsp.exec_cmd(vars.sleepCmd), locked)
create_bind(vars.kbKeepAwake, hl.dsp.global("cortetsu:keepAwake"))

-- Clipboard and emoji picker
create_bind(vars.kbEmoji, hl.dsp.exec_cmd("pkill fuzzel || cortetsu emoji -p"))
create_bind(
    vars.kbClipboardPasteLatest,
    -- Not `locked`: it would type the last clipboard entry into the lock
    -- screen's password field.
    hl.dsp.exec_cmd([[sleep 0.5s && ydotool type -d 1 "$(jq -r '.clipboardHistory[0].value // empty' "$HOME/.config/clipse/clipboard_history.json")"]])
)

-- Testing
create_bind(
    "SUPER + ALT + F12",
    hl.dsp.exec_cmd(
        "notify-send -u low -i dialog-information-symbolic 'Test notification' " ..
        [["Here's a really long message to test truncation and wrapping\nYou can middle click or flick this notification to dismiss it!"]] ..
        " -a 'Shell' -A 'Test1=I got it!' -A 'Test2=Another action'"
    )
)

-- Shortcut capture («Atajos y teclados»). While the editor records a chord,
-- Hyprland sits in this submap and no global bind fires, so SUPER + I reaches
-- the editor instead of opening Settings. cortetsu-keybinds capture enters and
-- leaves it; the timer leaves it on its own if the editor dies, so a crash
-- never strands the keyboard. The token lives in _G so a timer from an older
-- capture, or from before a reload, cannot end a newer one.
-- SUPER + CTRL + ALT + SHIFT + Escape is the manual way out.
local CAPTURE = "cortetsu-capture"
hl.define_submap(CAPTURE, function()
    hl.bind("SUPER + CTRL + ALT + SHIFT + Escape", hl.dsp.submap("reset"), { description = "cortetsu-capture:exit" })
end)
_G.cortetsu_capture_token = _G.cortetsu_capture_token or 0
-- A reload drops pending timers but keeps the current submap: a capture
-- running now would lose its fail-safe, so the reload ends it.
if hl.get_current_submap() == CAPTURE then
    _G.cortetsu_capture_token = _G.cortetsu_capture_token + 1
    hl.dispatch(hl.dsp.submap("reset"))
end

function _G.cortetsu_capture_begin(ms)
    ms = math.max(1000, math.min(tonumber(ms) or 15000, 60000))
    _G.cortetsu_capture_token = _G.cortetsu_capture_token + 1
    local token = _G.cortetsu_capture_token
    hl.dispatch(hl.dsp.submap(CAPTURE))
    hl.timer(function()
        if token == _G.cortetsu_capture_token and hl.get_current_submap() == CAPTURE then
            hl.dispatch(hl.dsp.submap("reset"))
        end
    end, { timeout = ms, type = "oneshot" })
end

function _G.cortetsu_capture_end()
    _G.cortetsu_capture_token = _G.cortetsu_capture_token + 1
    if hl.get_current_submap() == CAPTURE then
        hl.dispatch(hl.dsp.submap("reset"))
    end
end

-- Key test («Probar teclas»). cortetsu-keybinds probe binds each spare key of
-- one keyboard, by keycode and on that keyboard alone, to a function that
-- only records the press. The binds go on end, on the timer if the editor
-- dies, or with a reload, which starts a new Lua state without them.
-- Unbound by keycode: Hyprland 0.56.2 crashes when HL.Keybind:remove() runs
-- on a bind that has fired. The keys under test have no other bind. A test
-- the timer stopped stays in _G.cortetsu_probe_last until `end` reads it.
local function probe_stop()
    local probe = _G.cortetsu_probe
    _G.cortetsu_probe = nil
    for _, code in ipairs(probe and probe.codes or {}) do
        hl.unbind("code:" .. (code + 8))
    end
    _G.cortetsu_probe_last = probe or _G.cortetsu_probe_last
end

-- "A=1 H=code,code": whether a test is running and the codes pressed.
local function probe_report(probe, active)
    local hits = {}
    for code in pairs(probe and probe.hits or {}) do
        hits[#hits + 1] = code
    end
    table.sort(hits)
    return "A=" .. (active and "1" or "0") .. " H=" .. table.concat(hits, ",")
end

-- devices: Hyprland names of the keyboard; codes: evdev codes to test.
function _G.cortetsu_probe_begin(devices, codes, ms)
    ms = math.max(1000, math.min(tonumber(ms) or 30000, 120000))
    probe_stop()
    _G.cortetsu_probe_last = nil
    _G.cortetsu_probe_token = (_G.cortetsu_probe_token or 0) + 1
    local token = _G.cortetsu_probe_token
    -- Registered, with its timer, before binding: if a bind fails midway,
    -- end and the timer still remove the ones already made.
    local probe = { codes = codes, hits = {} }
    _G.cortetsu_probe = probe
    hl.timer(function()
        if token == _G.cortetsu_probe_token then
            probe_stop()
        end
    end, { timeout = ms, type = "oneshot" })
    for _, code in ipairs(codes) do
        local function hit()
            probe.hits[code] = true
        end
        local options = { device = { inclusive = true, list = devices }, description = "cortetsu-probe:" .. code }
        hl.bind("code:" .. (code + 8), hit, options)
    end
    return probe_report(probe, true)
end

function _G.cortetsu_probe_status()
    return probe_report(_G.cortetsu_probe, _G.cortetsu_probe ~= nil)
end

function _G.cortetsu_probe_end()
    _G.cortetsu_probe_token = (_G.cortetsu_probe_token or 0) + 1
    probe_stop()
    local last = _G.cortetsu_probe_last
    _G.cortetsu_probe_last = nil
    return probe_report(last, false)
end
