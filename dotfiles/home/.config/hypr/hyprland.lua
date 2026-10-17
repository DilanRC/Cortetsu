local home = assert(os.getenv("HOME"), "HOME is not set")
local hypr = home .. "/.config/hypr"

-- Cortetsu-owned Lua module root.
--   require("variables")       -> ~/.config/hypr/variables.lua
--   require("utils.functions") -> ~/.config/hypr/utils/functions.lua
--   require("scheme.current")  -> ~/.config/hypr/scheme/current.lua
--   require("hyprland.env")    -> ~/.config/hypr/hyprland/env.lua
local cortetsu_path = table.concat({
    hypr .. "/?.lua",
    hypr .. "/?/init.lua",
}, ";")

package.path = cortetsu_path .. ";" .. package.path

local function file_exists(path)
    local f = io.open(path, "r")
    if f then
        f:close()
        return true
    end
    return false
end

local function maybe_copy(src, dst)
    if file_exists(dst) then
        return
    end

    local input = io.open(src, "r")
    if not input then
        return
    end

    local output = io.open(dst, "w")
    if output then
        output:write(input:read("*a"))
        output:close()
    end
    input:close()
end

-- Ensure a live scheme exists.
maybe_copy(hypr .. "/scheme/default.lua", hypr .. "/scheme/current.lua")

-- Keybinds edited with cortetsu-keybinds (Atajos y teclados). Plain data in a
-- mutable file outside the generations, so promotion and rollback keep it.
-- A broken file is skipped with a notice: losing the edits beats losing every
-- bind. Precedence: edits > hypr-user.lua > first-party defaults.
local keybind_edits = {}
local keybind_edits_path = hypr .. "/cortetsu-keybinds.lua"
if file_exists(keybind_edits_path) then
    local ok, data = pcall(dofile, keybind_edits_path)
    if ok and type(data) == "table" then
        keybind_edits = data
    else
        hl.exec_cmd("notify-send -a Cortetsu 'Atajos' 'cortetsu-keybinds.lua no es válido; se ignoraron los cambios'")
    end
end

-- Rebound variables land in the shared `variables` table before any
-- first-party module reads it. A one-chord list stays a string so modules
-- that concatenate it keep working.
package.loaded["variables"] = nil
local vars = require("variables")
local modifier_names = { SUPER = true, SHIFT = true, CTRL = true, CONTROL = true, ALT = true }
local function only_strings(list)
    for _, item in ipairs(list) do
        if type(item) ~= "string" then
            return false
        end
    end
    return true
end
-- A modifier prefix such as kbGoToWs ("SUPER") is joined with keys in Lua;
-- turning it into a list would break that, so it never changes here.
local function is_prefix(value)
    if type(value) ~= "string" then
        return false
    end
    for part in value:gmatch("[^+%s]+") do
        if not modifier_names[part:upper()] then
            return false
        end
    end
    return true
end
for name, chords in pairs(keybind_edits.variables or {}) do
    if type(name) == "string" and name:match("^kb") and vars[name] ~= nil and not is_prefix(vars[name])
        and type(chords) == "table" and only_strings(chords) then
        vars[name] = #chords == 1 and chords[1] or chords
    end
end

-- Required modules must fail loudly. Silently skipping one of these can
-- remove entire groups of Hyprland configuration/keybinds after reload.
local required_modules = {
    "hyprland.env",
    "hyprland.general",
    "hyprland.input",
    "hyprland.misc",
    "hyprland.animations",
    "hyprland.decoration",
    "hyprland.group",
    "hyprland.execs",
    "hyprland.rules",
    "hyprland.gestures",
    "hyprland.keybinds",
}

local failures = {}
for _, mod in ipairs(required_modules) do
    -- Hyprland's Lua runtime keeps package.loaded across config reloads.
    -- Drop first-party modules so keybind changes cannot leave stale
    -- __lua callbacks registered after a Cortetsu promotion.
    package.loaded[mod] = nil
    local ok, err = pcall(require, mod)
    if not ok then
        failures[#failures + 1] = mod .. ": " .. tostring(err)
    end
end

if #failures > 0 then
    error("[Cortetsu Hyprland] required module load failure:\n  " ..
          table.concat(failures, "\n  "))
end

-- Optional per-machine overrides. These are allowed to be absent, but if a
-- present file is broken we surface the error instead of swallowing it.
for _, name in ipairs({ "variables", "env", "general", "execs", "rules", "keybinds" }) do
    local path = hypr .. "/custom/" .. name .. ".lua"
    if file_exists(path) then
        local ok, err = pcall(dofile, path)
        if not ok then
            error("[Cortetsu Hyprland] custom/" .. name .. ".lua failed: " .. tostring(err))
        end
    end
end

-- User overrides. Cortetsu-owned only: the legacy Caelestia user-config path
-- is no longer read here. All installer scripts (wire_sad_shell.py,
-- install-*.sh/.py, apply-canonical-sad-wiring.sh) and dotfiles/manifest.toml
-- write to ~/.config/hypr/hypr-user.lua now. Do not add a legacy fallback
-- back here -- test-hyprland-self-contained.py gates against it.
local cortetsu_user = hypr .. "/hypr-user.lua"

if file_exists(cortetsu_user) then
    local ok, err = pcall(dofile, cortetsu_user)
    if not ok then
        error("[Cortetsu Hyprland] hypr-user.lua failed: " .. tostring(err))
    end
end

-- Edits that replace or remove binds from the layers above, applied last.
for _, chord in ipairs(keybind_edits.unbind or {}) do
    if type(chord) == "string" then
        hl.unbind(chord)
    end
end
for _, bind in ipairs(keybind_edits.binds or {}) do
    local action = type(bind.exec) == "string" and hl.dsp.exec_cmd(bind.exec)
        or type(bind.global) == "string" and hl.dsp.global(bind.global)
        or nil
    if action and type(bind.chord) == "string" and type(bind.id) == "string" then
        -- cortetsu-keybinds verifies this tag (EDIT_TAG there) after a reload.
        hl.bind(bind.chord, action, { description = "cortetsu-keybinds:" .. bind.id })
    end
end
