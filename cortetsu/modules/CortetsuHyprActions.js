.pragma library

function luaString(value) {
    if (typeof value !== "string")
        return null;

    let result = '"';
    for (let index = 0; index < value.length; ++index) {
        const code = value.charCodeAt(index);
        const character = value[index];

        if (code === 0x5c) {
            result += "\\\\";
        } else if (code === 0x22) {
            result += "\\\"";
        } else if (code < 0x20 || code === 0x7f) {
            result += "\\" + ("00" + code).slice(-3);
        } else if (code >= 0xd800 && code <= 0xdbff) {
            const next = index + 1 < value.length ? value.charCodeAt(index + 1) : 0;
            if (next < 0xdc00 || next > 0xdfff)
                return null;
            result += character + value[index + 1];
            ++index;
        } else if (code >= 0xdc00 && code <= 0xdfff) {
            return null;
        } else {
            result += character;
        }
    }
    return result + '"';
}

function makeAction(lua, legacy) {
    return typeof lua === "string" && typeof legacy === "string"
        ? Object.freeze({ lua, legacy })
        : null;
}

function workspaceLuaValue(workspace) {
    if (typeof workspace === "number")
        return Number.isSafeInteger(workspace) && workspace > 0 ? String(workspace) : null;
    if (typeof workspace === "string" && workspace.length > 0)
        return luaString(workspace);
    return null;
}

function legacyWorkspaceNameSafe(workspace) {
    // Legacy dispatch arguments are raw text, so spaces and Unicode remain valid.
    // Reject controls, command separators, and quoting characters that can make
    // the workspace name ambiguous in the legacy parser.
    return typeof workspace === "string" && workspace.length > 0
        && !/[,;\x00-\x1f\x7f"'\\]/.test(workspace);
}

function workspaceLegacyValue(workspace) {
    if (typeof workspace === "number")
        return Number.isSafeInteger(workspace) && workspace > 0 ? String(workspace) : null;
    if (legacyWorkspaceNameSafe(workspace))
        return workspace;
    return null;
}

function normalizeAddress(address) {
    if (typeof address !== "string")
        return null;
    const hex = address.startsWith("0x") || address.startsWith("0X")
        ? address.slice(2) : address;
    return /^[0-9a-f]+$/i.test(hex) ? "0x" + hex : null;
}

function windowSelector(address) {
    const normalized = normalizeAddress(address);
    return normalized === null ? null : "address:" + normalized;
}

function windowLuaValue(address) {
    const selector = windowSelector(address);
    return selector === null ? null : luaString(selector);
}

function legacyAction(lua, legacy, selector) {
    return selector === null || typeof lua !== "string"
        ? null : makeAction(lua, typeof legacy === "string" ? legacy : "");
}

function focusWorkspace(workspace) {
    const luaValue = workspaceLuaValue(workspace);
    const legacyValue = workspaceLegacyValue(workspace);
    if (luaValue === null)
        return null;
    return makeAction(`hl.dsp.focus({ workspace = ${luaValue} })`,
        legacyValue === null ? "" : `workspace ${legacyValue}`);
}

function toggleSpecialWorkspace(name) {
    if (typeof name !== "string")
        return null;
    // Quickshell may expose the default special workspace as "special";
    // legacy call sites strip the prefix and can consequently pass an empty name.
    name = name.length === 0 ? "special" : name;
    const luaValue = luaString(name);
    return luaValue === null ? null
        : makeAction(`hl.dsp.workspace.toggle_special(${luaValue})`,
            legacyWorkspaceNameSafe(name) ? `togglespecialworkspace ${name}` : "");
}

function focusWindow(address) {
    const selector = windowSelector(address);
    const luaValue = windowLuaValue(address);
    return legacyAction(luaValue === null ? null : `hl.dsp.focus({ window = ${luaValue} })`,
        selector === null ? null : `focuswindow ${selector}`, selector);
}

function closeWindow(address) {
    const selector = windowSelector(address);
    const luaValue = windowLuaValue(address);
    return legacyAction(luaValue === null ? null : `hl.dsp.window.close({ window = ${luaValue} })`,
        selector === null ? null : `closewindow ${selector}`, selector);
}

function toggleFloat(address) {
    const selector = windowSelector(address);
    const luaValue = windowLuaValue(address);
    return legacyAction(luaValue === null ? null
        : `hl.dsp.window.float({ action = "toggle", window = ${luaValue} })`,
    selector === null ? null : `togglefloating ${selector}`, selector);
}

function togglePin(address) {
    const selector = windowSelector(address);
    const luaValue = windowLuaValue(address);
    return legacyAction(luaValue === null ? null
        : `hl.dsp.window.pin({ action = "toggle", window = ${luaValue} })`,
    selector === null ? null : `pin ${selector}`, selector);
}

function killWindow(address) {
    const selector = windowSelector(address);
    const luaValue = windowLuaValue(address);
    return legacyAction(luaValue === null ? null : `hl.dsp.window.kill({ window = ${luaValue} })`,
        selector === null ? null : `killwindow ${selector}`, selector);
}

function moveWindow(address, workspace, follow) {
    if (typeof follow !== "boolean")
        return null;
    const selector = windowSelector(address);
    const luaWindow = windowLuaValue(address);
    const luaWorkspace = workspaceLuaValue(workspace);
    const legacyWorkspace = workspaceLegacyValue(workspace);
    if (selector === null || luaWindow === null || luaWorkspace === null)
        return null;
    const legacyDispatcher = follow ? "movetoworkspace" : "movetoworkspacesilent";
    return makeAction(
        `hl.dsp.window.move({ window = ${luaWindow}, workspace = ${luaWorkspace}, follow = ${follow} })`,
        legacyWorkspace === null ? "" : `${legacyDispatcher} ${legacyWorkspace},${selector}`
    );
}

function luaNumber(value) {
    if (typeof value !== "number" || !Number.isFinite(value))
        return null;
    return String(Object.is(value, -0) ? 0 : value);
}

function moveCursor(x, y) {
    const luaX = luaNumber(x);
    const luaY = luaNumber(y);
    if (luaX === null || luaY === null)
        return null;
    const legacy = Number.isSafeInteger(x) && Number.isSafeInteger(y)
        ? `movecursor ${luaX} ${luaY}` : "";
    return makeAction(`hl.dsp.cursor.move({ x = ${luaX}, y = ${luaY} })`, legacy);
}

function dpms(on) {
    if (typeof on !== "boolean")
        return null;
    const action = on ? "on" : "off";
    return makeAction(`hl.dsp.dpms({ action = "${action}" })`, `dpms ${action}`);
}

function exit() {
    return makeAction("hl.dsp.exit()", "exit");
}
