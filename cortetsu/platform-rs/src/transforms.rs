use crate::util::*;
use serde_json::{Value, json};
use std::{
    collections::BTreeMap,
    fs,
    path::{Path, PathBuf},
};
fn data() -> Value {
    serde_json::from_str(include_str!("../templates/build-transforms.json"))
        .expect("transform constants")
}
fn replace_once(text: &str, old: &str, new: &str, marker: &str) -> Result<String> {
    if text.contains(marker) {
        return Ok(text.into());
    }
    if text.matches(old).count() != 1 {
        return fail(format!("expected unique recognised anchor for {marker}"));
    }
    Ok(text.replacen(old, new, 1))
}
fn ensure(text: &str, anchor: &str, tail: &str, statement: &str) -> Result<String> {
    let start = text.find(anchor).ok_or("missing anchor")? + anchor.len();
    let end = text[start..].find(tail).ok_or("missing tail")? + start;
    if text[start..end].contains(statement.trim()) {
        return Ok(text.into());
    }
    Ok(format!("{}{}{}", &text[..end], statement, &text[end..]))
}
fn qml_block(text: &str, component: &str, id: &str) -> Result<(usize, usize)> {
    let marker = format!("    {component} {{");
    let mut from = 0;
    while let Some(start) = text[from..].find(&marker).map(|n| n + from) {
        let open = text[start..].find('{').ok_or("missing brace")? + start;
        let mut depth = 0;
        let mut end = None;
        for (off, ch) in text[open..].char_indices() {
            if ch == '{' {
                depth += 1;
            } else if ch == '}' {
                depth -= 1;
                if depth == 0 {
                    end = Some(open + off + 1);
                    break;
                }
            }
        }
        let e = end.ok_or("unclosed QML block")?;
        if text[start..e].contains(&format!("id: {id}")) {
            return Ok((start, e));
        }
        from = e;
    }
    fail(format!("missing {component} block {id}"))
}
fn block_text<'a>(text: &'a str, component: &str, id: &str) -> &'a str {
    qml_block(text, component, id)
        .map(|(s, e)| &text[s..e])
        .unwrap_or("")
}
fn edit_block(
    text: &str,
    component: &str,
    id: &str,
    f: impl FnOnce(&str) -> Result<String>,
) -> Result<String> {
    let (s, e) = qml_block(text, component, id)?;
    Ok(format!("{}{}{}", &text[..s], f(&text[s..e])?, &text[e..]))
}
fn replacements(mut text: String, key: &str) -> Result<String> {
    for pair in data()["bottom"][key]
        .as_array()
        .ok_or("unknown transform")?
    {
        let old = pair[0].as_str().ok_or("old value")?;
        let new = pair[1].as_str().ok_or("new value")?;
        text = if let Some(n) = pair[2].as_u64() {
            text.replacen(old, new, n as usize)
        } else {
            text.replace(old, new)
        };
    }
    Ok(text)
}
fn write_changed(path: &Path, before: &str, after: &str) -> Result<bool> {
    if before == after {
        return Ok(false);
    }
    atomic_write(path, after, 0o644)?;
    Ok(true)
}
fn normalize_shell(root: &Path) -> Result<bool> {
    let p = root.join("shell.qml");
    let before = fs::read_to_string(&p)?;
    for m in ["ShellRoot {", "    Background {}\n", "    Shortcuts {}\n"] {
        if !before.contains(m) {
            return fail(format!("shell.qml incompatible: missing {m}"));
        }
    }
    if before.contains("    ConfigToasts {}") {
        return fail("legacy ConfigToasts cannot be normalized");
    }
    let mut after = before.clone();
    if after.contains("    settings.watchFiles: true") {
        after = after.replacen(
            "    settings.watchFiles: true",
            "    settings.watchFiles: false",
            1,
        );
    } else if !after.contains("    settings.watchFiles: false") {
        return fail("unrecognized settings.watchFiles");
    }
    for (anchor, line) in [
        ("    Background {}\n", "    BottomHub {}\n"),
        ("    Shortcuts {}\n", "    OverviewController {}\n"),
    ] {
        after = replace_once(&after, anchor, &format!("{anchor}{line}"), line)?;
    }
    write_changed(&p, &before, &after)
}
fn normalize_content(root: &Path) -> Result<bool> {
    let p = root.join("modules/drawers/ContentWindow.qml");
    let before = fs::read_to_string(&p)?;
    for m in [
        "StyledWindow {",
        "    onHasFullscreenChanged: {",
        "    HyprlandFocusGrab {",
        "        onCleared: {",
        "        panels.popouts.close();",
        "            panels.popouts.hasCurrent = false;",
    ] {
        if !before.contains(m) {
            return fail(format!("ContentWindow.qml incompatible: missing {m}"));
        }
    }
    let mut after = ensure(
        &before,
        "    onHasFullscreenChanged: {",
        "        panels.popouts.close();",
        "        screenState.overview = false;\n",
    )?;
    let d = data();
    for (old, new, marker) in [
        (
            "LAYER_UPSTREAM",
            "LAYER_TARGET",
            "screenState.overview ? WlrLayer.Overlay",
        ),
        (
            "KEYBOARD_UPSTREAM",
            "KEYBOARD_TARGET",
            "WlrLayershell.keyboardFocus: screenState.overview",
        ),
        (
            "MASK_UPSTREAM",
            "MASK_TARGET",
            "mask: screenState.overview ? null",
        ),
        (
            "SCRIM_UPSTREAM",
            "SCRIM_TARGET",
            "opacity: root.screenState.overview ? CortetsuDesign.scrimOpacity",
        ),
    ] {
        after = replace_once(
            &after,
            d["content"][old].as_str().ok_or("source line")?,
            d["content"][new].as_str().ok_or("target line")?,
            marker,
        )?;
    }
    let start = after
        .find("    HyprlandFocusGrab {")
        .ok_or("missing focus block")?;
    let end = after[start..]
        .find("        windows: [root]")
        .ok_or("missing focus tail")?
        + start;
    if !after[start..end].contains("if (s.overview") {
        let anchor = "            const conf = root.contentItem.Config;\n";
        let pos = after[start..end]
            .find(anchor)
            .ok_or("missing focus config")?
            + start
            + anchor.len();
        after.insert_str(
            pos,
            "            if (s.overview)\n                return true;\n",
        );
    }
    after = ensure(
        &after,
        "        onCleared: {",
        "            panels.popouts.hasCurrent = false;",
        "            root.screenState.overview = false;\n",
    )?;
    write_changed(&p, &before, &after)
}
fn compose(root: &Path) -> Result<()> {
    let p = root.join("modules/drawers/Panels.qml");
    let host = fs::read_to_string(root.join("modules/RetainedSurfacesHost.qml"))?;
    let text = fs::read_to_string(&p)?;
    if !text.lines().any(|l| l == "import \"../../theme\"") {
        return fail("missing import: theme");
    }
    for name in [
        "Overview",
        "Clipboard",
        "Hardware",
        "Display",
        "Wallpaper",
        "Calendar",
    ] {
        if text.contains(&format!("{name}.Wrapper"))
            || host.matches(&format!("{name}.Wrapper {{")).count() != 1
        {
            return fail(format!(
                "{name} must be hosted once by RetainedSurfacesHost"
            ));
        }
    }
    atomic_write(&p, text.replace("        sidebar: sidebar\n", ""), 0o644)?;
    println!("PASS: drawer panels composed; retained surfaces hosted once");
    Ok(())
}
fn migrate_bottom(root: &Path) -> Result<()> {
    let paths = [
        ("shell.qml", "shell"),
        ("modules/Shortcuts.qml", "shortcuts"),
        ("modules/drawers/Panels.qml", "panels"),
        ("modules/sidebar/Wrapper.qml", "sidebar"),
        ("modules/utilities/Wrapper.qml", "utilities"),
        ("modules/bar/BarWrapper.qml", "bar"),
        ("modules/bar/popouts/Wrapper.qml", "popout_wrapper"),
        ("modules/bar/popouts/ClipWrapper.qml", "popout_clip"),
        ("modules/drawers/Interactions.qml", "interactions"),
    ];
    let mut updates = Vec::new();
    for (rel, key) in paths {
        let path = root.join(rel);
        if !path.is_file() {
            continue;
        }
        let before = fs::read_to_string(&path)?;
        let mut after = before.clone();
        match key {
            "panels" => {
                if !before.contains("import qs.modules.overview as Overview") {
                    continue;
                }
                for (component, id, anchors) in [
                    (
                        "Launcher.Wrapper",
                        "launcher",
                        vec![
                            "        anchors.horizontalCenter: parent.horizontalCenter",
                            "        anchors.bottom: parent.bottom",
                        ],
                    ),
                    (
                        "Sidebar.Wrapper",
                        "sidebar",
                        vec![
                            "        anchors.bottom: parent.bottom",
                            "        anchors.right: root.screenState.utilities ? utilities.left : parent.right",
                            "        anchors.rightMargin: root.screenState.utilities ? Tokens.padding.medium : 0",
                        ],
                    ),
                ] {
                    after = edit_block(&after, component, id, |b| {
                        let mut lines: Vec<_> = b
                            .lines()
                            .filter(|l| !l.trim().starts_with("anchors."))
                            .map(str::to_owned)
                            .collect();
                        let n = lines.len() - 1;
                        for (i, a) in anchors.iter().enumerate() {
                            lines.insert(n + i, (*a).into());
                        }
                        Ok(lines.join("\n"))
                    })?;
                }
                after = edit_block(&after, "Utilities.Wrapper", "utilities", |b| {
                    Ok(b.replace("        sidebar: sidebar\n", ""))
                })?;
                for (component, id, rep) in [
                    (
                        "Item",
                        "osdWrapper",
                        vec![
                            (
                                "clip: sidebar.visible || session.visible",
                                "clip: session.visible",
                            ),
                            (
                                "sidebarOrSessionVisible: sidebar.visible || session.visible",
                                "sidebarOrSessionVisible: session.visible",
                            ),
                        ],
                    ),
                    (
                        "Item",
                        "sessionWrapper",
                        vec![
                            (
                                "anchors.rightMargin: sidebar.width * (1 - sidebar.offsetScale)",
                                "anchors.rightMargin: 0",
                            ),
                            ("clip: sidebar.visible", "clip: false"),
                        ],
                    ),
                    (
                        "Toasts.Toasts",
                        "toasts",
                        vec![
                            (
                                "anchors.bottom: sidebar.visible ? parent.bottom : utilities.top",
                                "anchors.bottom: utilities.top",
                            ),
                            (
                                "anchors.bottom: sidebar.visible ? sidebar.top : utilities.top",
                                "anchors.bottom: utilities.top",
                            ),
                            ("anchors.right: sidebar.left", "anchors.right: parent.right"),
                        ],
                    ),
                ] {
                    after = edit_block(&after, component, id, |b| {
                        let mut t = b.to_owned();
                        for (o, n) in rep {
                            t = t.replace(o, n);
                        }
                        Ok(t)
                    })?;
                }
            }
            "sidebar" => {
                after = after.replace(
                    "objectName: \"cortetsuNativeSidebar\"",
                    "objectName: \"cortetsuBottomNotificationCenter\"",
                );
                if !after.contains("objectName:") {
                    after = after.replacen(
                        "    id: root\n",
                        "    id: root\n    objectName: \"cortetsuBottomNotificationCenter\"\n",
                        1,
                    );
                }
                after=after.replace("readonly property bool shouldBeActive: screenState.sidebar && Config.sidebar.enabled","readonly property bool shouldBeActive: screenState.sidebar");
                if !after.contains("readonly property bool shouldBeActive:") {
                    after=after.replacen("    objectName: \"cortetsuBottomNotificationCenter\"\n","    objectName: \"cortetsuBottomNotificationCenter\"\n\n    readonly property bool shouldBeActive: screenState.sidebar\n",1);
                }
                let start = after
                    .find("    visible: offsetScale < 1")
                    .ok_or("sidebar geometry start")?;
                let end = after[start..]
                    .find("    opacity: 1 - offsetScale")
                    .ok_or("sidebar geometry end")?
                    + start;
                after.replace_range(start..end,"    visible: offsetScale < 1\n    anchors.bottomMargin: 66 + (-implicitHeight - 5 - 66) * offsetScale\n\n    implicitWidth: Math.min(520, parent.width - 16)\n    implicitHeight: Math.min(430, parent.height * 0.55)\n");
                after = edit_block(&after, "Loader", "content", |b| {
                    let s = b.find("        anchors.").ok_or("sidebar loader anchors")?;
                    let e = b[s..]
                        .find("        active:")
                        .ok_or("sidebar loader active")?
                        + s;
                    Ok(format!("{}        anchors.fill: parent\n\n{}",&b[..s],&b[e..]).replace("implicitWidth: Tokens.sizes.sidebar.width - content.anchors.leftMargin - content.anchors.margins","implicitWidth: root.implicitWidth"))
                })?;
            }
            "utilities" => {
                after = replacements(after, key)?;
                if let Some(s) = after.find("    states: State {") {
                    let e = after[s..]
                        .find("    Behavior on offsetScale {")
                        .ok_or("utilities animation")?
                        + s;
                    after.replace_range(s..e, "");
                }
                let s = after
                    .find("    visible: offsetScale < 1")
                    .ok_or("utilities geometry")?;
                let e = after[s..]
                    .find("    opacity: 1 - offsetScale")
                    .ok_or("utilities opacity")?
                    + s;
                after.replace_range(s..e,"    visible: offsetScale < 1\n    anchors.bottomMargin: 66 + (-implicitHeight - 5 - 66) * offsetScale\n    implicitHeight: content.implicitHeight + totalPadding\n    implicitWidth: Math.min(Tokens.sizes.utilities.width, parent.width - 16)\n");
            }
            "popout_wrapper" => {
                let d = data();
                for pair in d["bottom"][key].as_array().ok_or("popout transforms")? {
                    let o = pair[0].as_str().unwrap();
                    let n = pair[1].as_str().unwrap();
                    if o.contains("property real bottomRightMargin")
                        && after.contains("property real bottomAnchorCenter:")
                    {
                        continue;
                    }
                    after = after.replacen(o, n, 1);
                }
            }
            "popout_clip" => {
                after = replacements(after, key)?;
                for marker in ["    Behavior on x {\n", "    Behavior on y {\n"] {
                    if let Some(start) = after.find(marker) {
                        let brace = start + after[start..].find('{').ok_or("behavior brace")?;
                        let mut depth = 0;
                        let mut end = None;
                        for (i, c) in after[brace..].char_indices() {
                            if c == '{' {
                                depth += 1;
                            } else if c == '}' {
                                depth -= 1;
                                if depth == 0 {
                                    end = Some(brace + i + 1);
                                    break;
                                }
                            }
                        }
                        let mut end = end.ok_or("behavior unclosed")?;
                        if after[end..].starts_with('\n') {
                            end += 1;
                        }
                        after.replace_range(start..end, "");
                    }
                }
            }
            _ => after = replacements(after, key)?,
        }
        if after != before {
            updates.push((path, rel.to_owned(), after));
        }
    }
    let changed: Vec<_> = updates.iter().map(|(_, rel, _)| rel.clone()).collect();
    for (path, _, text) in updates {
        atomic_write(&path, text, 0o644)?;
    }
    println!(
        "{}",
        if changed.is_empty() {
            "MIGRATION no-op".into()
        } else {
            format!("MIGRATED {}", changed.join(", "))
        }
    );
    Ok(())
}
fn between<'a>(text: &'a str, start: &str, end: &str) -> Option<&'a str> {
    let s = text.find(start)?;
    let e = text[s + start.len()..].find(end)? + s + start.len();
    Some(&text[s..e])
}
fn all(text: &str, needles: &[&str]) -> bool {
    needles.iter().all(|n| text.contains(n))
}
fn check_bottom(root: &Path, rel: &str) -> Result<i32> {
    let path = root.join(safe_relative(rel)?);
    let text = match fs::read_to_string(path) {
        Ok(t) => t,
        Err(_) => return Ok(1),
    };
    let valid = match rel {
        "shell.qml" => {
            all(
                &text,
                &[
                    "settings.watchFiles: false",
                    "    BottomHub {}",
                    "    OverviewController {}",
                ],
            ) && !text.contains("    CustomDock {}")
        }
        "components/ScreenState.qml" => text.contains("property bool overview"),
        "modules/Shortcuts.qml" => all(
            &text,
            &[
                "\"customDock\", \"launcher\"",
                "const open = !(screenState.sidebar || screenState.utilities);",
                "screenState.sidebar = open;",
                "screenState.utilities = open;",
            ],
        ),
        "modules/drawers/ContentWindow.qml" => {
            let screen =
                fs::read_to_string(root.join("components/ScreenState.qml")).unwrap_or_default();
            let mut flags = vec!["overview"];
            for f in ["clipboard", "hardware", "displayManager"] {
                if screen.contains(&format!("property bool {f}")) {
                    flags.push(f);
                }
            }
            let line = |p: &str| text.lines().find(|l| l.trim().starts_with(p)).unwrap_or("");
            let layer = line("WlrLayershell.layer:");
            let keyboard = line("WlrLayershell.keyboardFocus:");
            let mask = line("mask:");
            let focus = between(&text, "HyprlandFocusGrab {", "windows: [root]").unwrap_or("");
            let cleared =
                between(&text, "onCleared: {", "panels.popouts.hasCurrent = false;").unwrap_or("");
            let fullscreen = between(
                &text,
                "onHasFullscreenChanged: {",
                "panels.popouts.close();",
            )
            .unwrap_or("");
            all(layer, &["WlrLayer.Overlay"])
                && all(
                    keyboard,
                    &[
                        "WlrKeyboardFocus.OnDemand",
                        "screenState.launcher",
                        "screenState.session",
                    ],
                )
                && all(mask, &["? null", "hasFullscreen ? emptyRegion : regions"])
                && focus.contains("return true;")
                && flags.iter().all(|f| {
                    layer.contains(&format!("screenState.{f}"))
                        && keyboard.contains(&format!("screenState.{f}"))
                        && mask.contains(&format!("screenState.{f}"))
                        && focus.contains(&format!("s.{f}"))
                        && fullscreen.contains(&format!("screenState.{f} = false;"))
                        && cleared.contains(&format!("root.screenState.{f} = false;"))
                })
                && text.contains("opacity: root.screenState.overview ? CortetsuDesign.scrimOpacity")
                && (!flags.contains(&"clipboard")
                    || text.contains("root.screenState.clipboard ? 0.48"))
        }
        "modules/drawers/Panels.qml" => {
            let launcher = block_text(&text, "Launcher.Wrapper", "launcher");
            let utilities = block_text(&text, "Utilities.Wrapper", "utilities");
            let sidebar = block_text(&text, "Sidebar.Wrapper", "sidebar");
            let session = block_text(&text, "Item", "sessionWrapper");
            all(
                &text,
                &[
                    "import qs.modules.overview as Overview",
                    "readonly property alias overview: overview",
                    "Overview.Wrapper {",
                ],
            ) && all(
                launcher,
                &[
                    "anchors.horizontalCenter: parent.horizontalCenter",
                    "anchors.bottom: parent.bottom",
                ],
            ) && !launcher.contains("anchors.top: notifications.bottom")
                && !utilities.contains("sidebar: sidebar")
                && all(
                    sidebar,
                    &[
                        "anchors.bottom: parent.bottom",
                        "anchors.right: root.screenState.utilities ? utilities.left : parent.right",
                        "anchors.rightMargin: root.screenState.utilities ? Tokens.padding.medium : 0",
                    ],
                )
                && !session.contains("sidebar.width")
        }
        "modules/drawers/Regions.qml" => {
            all(
                &text,
                &[
                    "y: root.win.height - height - panel.dockOffset",
                    "width: panel.width * (1 - root.panels.session.offsetScale) + root.borderThickness + sidebarRegion.width",
                    "panel: root.panels.sidebar",
                    "x: root.win.width - width\n        width: panel.width * (1 - root.panels.sidebar.offsetScale) + root.borderThickness",
                ],
            ) && !text.contains("panel: root.panels.utilities\n        y: root.win.height - height")
        }
        "modules/sidebar/Wrapper.qml" => {
            all(
                &text,
                &[
                    "objectName: \"cortetsuBottomNotificationCenter\"",
                    "readonly property bool shouldBeActive: screenState.sidebar",
                    "anchors.bottomMargin: 66 + (-implicitHeight - 5 - 66) * offsetScale",
                    "implicitWidth: Math.min(520, parent.width - 16)",
                    "implicitHeight: Math.min(430, parent.height * 0.55)",
                    "anchors.fill: parent",
                ],
            ) && !text.contains("anchors.rightMargin:")
                && !text.contains("screenState.sidebar && Config.sidebar.enabled")
        }
        "modules/bar/popouts/Wrapper.qml" => all(
            &text,
            &[
                "property bool bottomAttached",
                "property real bottomOffset: 54",
                "property real bottomRightMargin: 4",
                "property real bottomAnchorCenter: -1",
                "bottomAttached = false;",
                "onHasCurrentChanged:",
            ],
        ),
        "modules/bar/popouts/ClipWrapper.qml" => {
            all(
                &text,
                &[
                    "content.bottomAttached",
                    "content.bottomAnchorCenter >= 0",
                    "content.bottomAnchorCenter - content.nonAnimWidth / 2",
                    "parent.width - content.nonAnimWidth - content.bottomRightMargin",
                    "parent.height - content.nonAnimHeight - content.bottomOffset",
                ],
            ) && !text.contains("Behavior on x")
                && !text.contains("Behavior on y")
        }
        "modules/drawers/Interactions.qml" => {
            all(
                &text,
                &[
                    "function insidePanel(panel: Item, x: real, y: real): bool",
                    "popouts.bottomAttached",
                    "insidePanel(panels.popoutsWrapper, x, y)",
                    "const showSidebar = false;",
                    "if (false && Config.sidebar.showOnHover)",
                ],
            ) && !text.contains("const showUtilities =")
        }
        "modules/utilities/Wrapper.qml" => {
            all(
                &text,
                &[
                    "readonly property bool shouldBeActive: screenState.utilities",
                    "anchors.bottomMargin: 66 + (-implicitHeight - 5 - 66) * offsetScale",
                    "implicitWidth: Math.min(Tokens.sizes.utilities.width, parent.width - 16)",
                ],
            ) && !text.contains("Sidebar.Wrapper")
                && !text.contains("screenState.sidebar")
        }
        "modules/bar/BarWrapper.qml" => all(
            &text,
            &[
                "readonly property bool disabled: true",
                "readonly property int clampedWidth: 0",
                "readonly property int exclusiveZone: 0",
                "readonly property bool shouldBeVisible: false",
                "visible: false",
                "implicitWidth: 0",
            ],
        ),
        _ => return Ok(2),
    };
    Ok(if valid { 0 } else { 1 })
}
fn retire(texts: &mut BTreeMap<String, String>) -> Result<bool> {
    let before = texts.clone();
    for (flag, controller, module, alias, key, target, comment) in [
        (
            "gamingCenter",
            "GamingController",
            "gaming",
            "Gaming",
            "SUPER + SHIFT + G",
            "cortetsu:gamingcenter",
            "Gaming Center QML nativo",
        ),
        (
            "updaterCenter",
            "UpdaterController",
            "updater",
            "Updater",
            "SUPER + SHIFT + U",
            "cortetsu:updatercenter",
            "Cortetsu Updater QML nativo",
        ),
    ] {
        for (part, pattern) in [
            ("screen", format!(r"(?m)^\s*property bool {flag}\s*\n")),
            ("shell", format!(r"(?m)^\s*{controller} \{{\}}\s*\n")),
            (
                "panels",
                format!(r"(?m)^\s*import qs\.modules\.{module} as {alias}\s*\n"),
            ),
            (
                "panels",
                format!(r"(?m)^\s*readonly property alias {flag}: {flag}\s*\n"),
            ),
            (
                "content",
                format!(r"(?m)^\s*(?:root\.)?screenState\.{flag}\s*=\s*false;\s*\n"),
            ),
        ] {
            let re = regex::Regex::new(&pattern)?;
            texts.insert(part.into(), re.replace_all(&texts[part], "").into_owned());
        }
        for blank in ["", "\n"] {
            let block = format!(
                "    {alias}.Wrapper {{\n        id: {flag}\n{blank}        screen: root.screen\n        screenState: root.screenState\n{blank}        anchors.fill: parent\n    }}\n\n"
            );
            texts.insert("panels".into(), texts["panels"].replace(&block, ""));
        }
        for marker in [
            format!(" || screenState.{flag}"),
            format!("screenState.{flag} || "),
            format!(" || s.{flag}"),
            format!("s.{flag} || "),
        ] {
            texts.insert("content".into(), texts["content"].replace(&marker, ""));
        }
        let bind = format!("hl.bind(\n    \"{key}\",\n    hl.dsp.global(\"{target}\")\n)");
        for block in [
            format!("-- {comment}\n{bind}\n"),
            format!("-- {comment}\n{bind}"),
            format!("{bind}\n"),
            bind,
        ] {
            texts.insert("user".into(), texts["user"].replace(&block, ""));
        }
    }
    for (part, markers) in [
        ("screen", vec!["gamingCenter", "updaterCenter"]),
        ("shell", vec!["GamingController", "UpdaterController"]),
        (
            "panels",
            vec![
                "qs.modules.gaming",
                "qs.modules.updater",
                "gamingCenter",
                "updaterCenter",
                "Gaming.Wrapper",
                "Updater.Wrapper",
            ],
        ),
        ("content", vec!["gamingCenter", "updaterCenter"]),
        (
            "user",
            vec!["cortetsu:gamingcenter", "cortetsu:updatercenter"],
        ),
    ] {
        if markers.iter().any(|m| texts[part].contains(m)) {
            return fail(format!(
                "RETIREMENT ERROR [{part}]: legacy Gaming/Updater markers remain"
            ));
        }
    }
    Ok(*texts != before)
}
fn wire(a: &Args) -> Result<i32> {
    a.check(&["live", "usercfg", "stage", "features"])?;
    let live = a
        .get("live")
        .map(PathBuf::from)
        .or_else(|| std::env::var_os("CORTETSU_LIVE_ROOT").map(PathBuf::from))
        .unwrap_or(runtime_root()?.join("current"));
    let user = a
        .get("usercfg")
        .map(PathBuf::from)
        .unwrap_or(home()?.join(".config/hypr/hypr-user.lua"));
    let stage = PathBuf::from(a.get("stage").ok_or("--stage required")?);
    let features = a
        .get("features")
        .unwrap_or("display,wallpaper")
        .split(',')
        .filter(|s| !s.is_empty())
        .collect::<Vec<_>>();
    if features
        .iter()
        .any(|s| !["display", "wallpaper"].contains(s))
    {
        return fail("unknown feature");
    }
    let paths = [
        ("screen", "components/ScreenState.qml"),
        ("shell", "shell.qml"),
        ("panels", "modules/drawers/Panels.qml"),
        ("content", "modules/drawers/ContentWindow.qml"),
        ("user", "user-config/hypr-user.lua"),
    ];
    let mut texts = BTreeMap::new();
    for (part, rel) in paths {
        texts.insert(
            part.to_owned(),
            fs::read_to_string(if part == "user" {
                user.clone()
            } else {
                live.join(rel)
            })?,
        );
    }
    let mut changed = json!({"retired":retire(&mut texts)?});
    let d = data();
    for feature in ["display", "wallpaper"] {
        if !features.contains(&feature) {
            continue;
        }
        let before = texts.clone();
        for op in d["wire"][feature].as_array().ok_or("wire ops")? {
            let args = strings(&op["args"]);
            match op["op"].as_str().ok_or("wire operation")? {
                "replace_once" => {
                    let key = &args[0];
                    if !texts[key].contains(&args[3]) {
                        if !texts[key].contains(&args[1]) {
                            return fail(format!("PREFLIGHT ERROR [{key}]: missing context"));
                        }
                        texts.insert(key.clone(), texts[key].replacen(&args[1], &args[2], 1));
                    }
                }
                "ensure_statement" | "ensure_or_member" => {
                    let key = &args[0];
                    let t = &texts[key];
                    let start = t.find(&args[1]).ok_or("missing wire anchor")? + args[1].len();
                    let end = t[start..].find(&args[2]).ok_or("missing wire tail")? + start;
                    if !t[start..end].contains(&args[3]) {
                        let insert = format!(
                            "{}{}",
                            if op["op"] == "ensure_statement" {
                                "\n"
                            } else {
                                " || "
                            },
                            args[3]
                        );
                        texts.insert(key.clone(), format!("{}{}{}", &t[..end], insert, &t[end..]));
                    }
                }
                "insert_wrapper" => {
                    let t = &texts["panels"];
                    if !t.contains(&format!("id: {}", args[0])) {
                        let anchor = "    Dashboard.Wrapper {";
                        if !t.contains(anchor) {
                            return fail("missing Dashboard.Wrapper anchor");
                        }
                        texts.insert(
                            "panels".into(),
                            t.replacen(anchor, &format!("{}{anchor}", args[1]), 1),
                        );
                    }
                }
                "insert_bind" => {
                    let t = &texts["user"];
                    if !t.contains(&args[0]) {
                        if !t.contains(&args[1]) {
                            return fail("missing bind anchor");
                        }
                        texts.insert(
                            "user".into(),
                            t.replacen(
                                &args[1],
                                &format!("{}\n\n-- {}\n{}", args[1], args[2], args[0]),
                                1,
                            ),
                        );
                    }
                }
                _ => return fail("invalid wire operation"),
            }
        }
        changed[feature] = json!(texts != before);
    }
    for (part, rel) in paths {
        atomic_write(&stage.join(rel), &texts[part], 0o644)?;
    }
    println!("{}", json!({"ok":true,"changed":changed}));
    Ok(0)
}
fn retire_theme() -> Result<i32> {
    let h = home()?;
    let backup = data_root()?
        .join("migrations")
        .join(unique())
        .join("retired-theme");
    let mut count = 0;
    for rel in [
        ".config/kitty/caelestia-theme.conf",
        ".config/caelestia/templates/kitty-cortetsu.conf",
        ".local/state/caelestia/theme/kitty-cortetsu.conf",
    ] {
        let p = h.join(rel);
        if !p.exists() && !p.is_symlink() {
            continue;
        }
        if !p.is_file() && !p.is_symlink() {
            return fail(format!(
                "no se retira directorio u objeto especial: {}",
                p.display()
            ));
        }
        let source = if p.is_symlink() {
            fs::canonicalize(&p)
                .ok()
                .filter(|x| x.is_file())
                .unwrap_or(p.clone())
        } else {
            p.clone()
        };
        copy_path(&source, &backup.join(rel))?;
        fs::remove_file(&p)?;
        count += 1;
        println!("RETIRED legacy-theme={}", p.display());
    }
    if count == 0 {
        println!("Cortetsu legacy theme: already retired");
    } else {
        println!(
            "BACKUP retired-theme={}\nCortetsu legacy theme: retired={count}",
            backup.display()
        );
    }
    Ok(0)
}
pub fn run(command: &str, a: &Args) -> Result<i32> {
    if command == "wire_sad_shell" {
        return wire(a);
    }
    if command == "retire_legacy_theme" {
        return retire_theme();
    }
    a.check(&[])?;
    let root = PathBuf::from(a.positional.first().ok_or("runtime root required")?);
    match command {
        "normalize-shell-24" => {
            let changed = normalize_shell(&root)?;
            println!(
                "{} shell.qml",
                if changed { "NORMALIZED" } else { "ALREADY" }
            );
        }
        "normalize-contentwindow-overview-24" => {
            let changed = normalize_content(&root)?;
            println!(
                "{} modules/drawers/ContentWindow.qml",
                if changed { "NORMALIZED" } else { "ALREADY" }
            );
        }
        "compose-panels" => compose(&root)?,
        "migrate-bottom-hub-from-main" => migrate_bottom(&root)?,
        "check-bottom-hub-target" => {
            return check_bottom(
                &root,
                a.positional.get(1).ok_or("relative target required")?,
            );
        }
        _ => return fail("unknown transform"),
    };
    Ok(0)
}
