#!/usr/bin/env python3
"""Cortetsu QML design lint.

Static checks that adapt the Impeccable detector and Emil Kowalski's motion
rules to QML. Impeccable's own detector only reads HTML/CSS/JSX, so this is
the measurable version of docs/CORTETSU_DESIGN_SYSTEM.md for QML.

It reports and exits 0 by default. `--strict` exits 1 on any finding and is
meant for the per-surface gate of the redesign (phase 3).

A finding that is intended carries `// design-lint: allow <rule>: <reason>`
on its line or the line above. The reason is required; without it the
comment does not count.

Two rules are not statically decidable and stay manual: "keyboard-initiated
actions do not animate" and "no grey text on a coloured background".
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import asdict, dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
QML_ROOT = ROOT / "cortetsu"
DEFAULTS = QML_ROOT / "theme/CortetsuDesignDefaults.js"
# Tokens, generated files and tests are allowed to hold literals.
SKIP_DIRS = ("theme/", "tests/", "fixtures/")

DRAWER_HINT = re.compile(r"drawer|bottomhub|panel|sidebar|dashboard|wallpaper", re.I)
INTERACTIVE = {"MouseArea", "TapHandler"}
SIZE_PROPS = ("width", "height", "implicitWidth", "implicitHeight")
MIN_TARGET = 36
MIN_SCALE = 0.95
MAX_MS = 300
MAX_DRAWER_MS = 500

RULES = {
    "motion-bounce": "bounce/elastic/overshoot easing",
    "motion-ease-in": "ease-in curve (only valid on exits)",
    "motion-scale-from-zero": f"scale starts below {MIN_SCALE}",
    "motion-duration": f"duration above {MAX_MS} ms ({MAX_DRAWER_MS} ms for drawers)",
    "motion-layout-property": "animates width/height instead of opacity/scale/x/y",
    "color-untinted-neutral": "pure black/grey/white without a washi/sumi tint",
    "color-contrast": "token pair below WCAG AA",
    "layout-nested-surface": "CortetsuSurface nested inside another CortetsuSurface",
    "layout-small-target": f"click target smaller than {MIN_TARGET} px",
    "token-literal-color": "colour literal outside CortetsuDesign",
    "token-literal-radius": "radius literal outside CortetsuDesign",
    "token-literal-duration": "duration literal outside CortetsuDesign",
    "type-field-font": "text field without the shell font family (falls back to monospace)",
}


ALLOW = re.compile(r"//\s*design-lint:\s*allow\s+([a-z-]+)\s*:\s*\S")


@dataclass
class Finding:
    rule: str
    path: str
    line: int
    detail: str


def strip_comments(text: str) -> str:
    """Blank out comments while keeping offsets and string literals."""
    out, i, n = [], 0, len(text)
    while i < n:
        c = text[i]
        if c in "\"'`":
            j = i + 1
            while j < n and text[j] != c:
                j += 2 if text[j] == "\\" else 1
            out.append(text[i:j + 1])
            i = j + 1
        elif text.startswith("//", i):
            j = text.find("\n", i)
            j = n if j < 0 else j
            out.append(" " * (j - i))
            i = j
        elif text.startswith("/*", i):
            j = text.find("*/", i + 2)
            j = n if j < 0 else j + 2
            out.append(re.sub(r"[^\n]", " ", text[i:j]))
            i = j
        else:
            out.append(c)
            i += 1
    return "".join(out)


OBJECT_OPEN = re.compile(r"\b([A-Z][A-Za-z0-9_.]*)\s*\{")


@dataclass
class Obj:
    type: str
    start: int
    end: int
    depth: int
    parent: "Obj | None"


def objects(text: str) -> list[Obj]:
    """QML object blocks (`Type { ... }`) with their nesting. Braces of JS
    blocks are matched too, so only blocks opened by a capitalised type
    become objects."""
    opens = {m.end() - 1: m.group(1) for m in OBJECT_OPEN.finditer(text)}
    stack: list[tuple[int, Obj | None]] = []
    found: list[Obj] = []
    current: Obj | None = None
    in_str = None
    for i, c in enumerate(text):
        if in_str:
            if c == in_str and text[i - 1] != "\\":
                in_str = None
            continue
        if c in "\"'`":
            in_str = c
        elif c == "{":
            if i in opens:
                obj = Obj(opens[i], i, len(text), len(stack), current)
                found.append(obj)
                stack.append((i, current))
                current = obj
            else:
                stack.append((i, current))
        elif c == "}" and stack:
            _, previous = stack.pop()
            if current is not None and current.start == _:
                current.end = i
            current = previous
    return found


def own_text(text: str, obj: Obj, all_objs: list[Obj]) -> str:
    """Body of `obj` with child objects blanked, so a property belongs to it."""
    body = list(text[obj.start + 1:obj.end])
    for child in all_objs:
        if child.parent is obj:
            for k in range(child.start - obj.start - 1, child.end - obj.start):
                if 0 <= k < len(body) and body[k] != "\n":
                    body[k] = " "
    return "".join(body)


def line_of(text: str, offset: int) -> int:
    return text.count("\n", 0, offset) + 1


def neutral(hex_value: str) -> bool:
    h = hex_value.lstrip("#")
    if len(h) in (3, 4):
        h = "".join(ch * 2 for ch in h[-3:]) if len(h) == 4 else "".join(ch * 2 for ch in h)
    elif len(h) == 8:
        h = h[2:]
    if len(h) != 6:
        return False
    r, g, b = (int(h[k:k + 2], 16) for k in (0, 2, 4))
    return r == g == b


def lint_file(path: Path) -> list[Finding]:
    rel = path.relative_to(ROOT).as_posix()
    raw = path.read_text(encoding="utf-8", errors="replace")
    text = strip_comments(raw)
    found: list[Finding] = []

    def add(rule: str, offset: int, detail: str) -> None:
        found.append(Finding(rule, rel, line_of(text, offset), detail))

    for m in re.finditer(r"Easing\.(Out|In|InOut|OutIn)(Bounce|Elastic|Back)\b", text):
        add("motion-bounce", m.start(), m.group(0))
    for m in re.finditer(r"Easing\.In(Quad|Cubic|Quart|Quint|Sine|Expo|Circ)\b", text):
        add("motion-ease-in", m.start(), m.group(0))

    for m in re.finditer(r"\bscale\s*:\s*([^\n;]+)", text):
        for num in re.findall(r"(?<![\w.])(\d*\.?\d+)(?![\w.])", m.group(1)):
            if float(num) < MIN_SCALE:
                add("motion-scale-from-zero", m.start(), m.group(0).strip())
                break

    drawer = bool(DRAWER_HINT.search(rel))
    for m in re.finditer(r"\bduration\s*:\s*(\d+)\b", text):
        ms = int(m.group(1))
        if ms == 0:
            continue
        add("token-literal-duration", m.start(), f"{ms} ms")
        if ms > (MAX_DRAWER_MS if drawer else MAX_MS):
            add("motion-duration", m.start(), f"{ms} ms")

    for m in re.finditer(r"Behavior\s+on\s+(width|height|implicitWidth|implicitHeight)\b", text):
        add("motion-layout-property", m.start(), m.group(0))
    for m in re.finditer(r"\bpropert(?:y|ies)\s*:\s*\"([^\"]+)\"", text):
        props = {p.strip() for p in m.group(1).split(",")}
        hit = props & set(SIZE_PROPS)
        if hit:
            add("motion-layout-property", m.start(), ", ".join(sorted(hit)))

    for m in re.finditer(r"\"(#[0-9A-Fa-f]{3,8})\"", text):
        add("token-literal-color", m.start(), m.group(1))
        if neutral(m.group(1)):
            add("color-untinted-neutral", m.start(), m.group(1))
    for m in re.finditer(r"\"(black|white|gray|grey|darkgray|lightgray)\"", text):
        add("token-literal-color", m.start(), m.group(1))
        add("color-untinted-neutral", m.start(), m.group(1))
    for m in re.finditer(r"Qt\.rgba\(\s*([\d.]+)\s*,\s*([\d.]+)\s*,\s*([\d.]+)", text):
        add("token-literal-color", m.start(), m.group(0) + ")")
        if m.group(1) == m.group(2) == m.group(3):
            add("color-untinted-neutral", m.start(), m.group(0) + ")")

    for m in re.finditer(r"\bradius\s*:\s*(\d+(?:\.\d+)?)\s*$", text, re.M):
        if float(m.group(1)) != 0:
            add("token-literal-radius", m.start(), m.group(1))

    objs = objects(text)
    for obj in objs:
        if obj.type.endswith("CortetsuSurface"):
            p = obj.parent
            while p is not None and not p.type.endswith("CortetsuSurface"):
                p = p.parent
            if p is not None:
                add("layout-nested-surface", obj.start, f"inside the surface at line {line_of(text, p.start)}")
        if obj.type in ("TextField", "TextInput", "TextArea") and not re.search(
                r"\bfont\.family\s*:|\bfont\s*:", own_text(text, obj, objs)):
            add("type-field-font", obj.start, obj.type)
        if obj.type in INTERACTIVE:
            mine = own_text(text, obj, objs)
            target = obj
            if re.search(r"anchors\.fill\s*:\s*parent\b", mine) and obj.parent is not None:
                target = obj.parent
                mine = own_text(text, target, objs)
            for prop in SIZE_PROPS:
                m = re.search(rf"(?<![\w.]){prop}\s*:\s*(\d+(?:\.\d+)?)\s*$", mine, re.M)
                if m and 0 < float(m.group(1)) < MIN_TARGET:
                    add("layout-small-target", target.start, f"{target.type}.{prop}: {m.group(1)}")
                    break
    lines = raw.splitlines()

    def allowed(f: Finding) -> bool:
        near = lines[max(0, f.line - 2):f.line]
        return any(m.group(1) == f.rule for line in near for m in [ALLOW.search(line)] if m)

    return [f for f in found if not allowed(f)]


def contrast_findings() -> list[Finding]:
    tokens = dict(re.findall(r"^var (color\w+) = \"(#[0-9A-Fa-f]{6})\"", DEFAULTS.read_text(), re.M))
    aliases = dict(re.findall(r"^var (color\w+) = (color\w+)$", DEFAULTS.read_text(), re.M))
    for name, target in aliases.items():
        if target in tokens:
            tokens[name] = tokens[target]

    def lum(h: str) -> float:
        def ch(v: int) -> float:
            x = v / 255
            return x / 12.92 if x <= 0.03928 else ((x + 0.055) / 1.055) ** 2.4
        r, g, b = (int(h[k:k + 2], 16) for k in (1, 3, 5))
        return 0.2126 * ch(r) + 0.7152 * ch(g) + 0.0722 * ch(b)

    def ratio(a: str, b: str) -> float:
        la, lb = lum(a), lum(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)

    surfaces = ("colorSumi", "colorTetsu", "colorSurfaceHigh", "colorSurfaceGlass", "colorSurfaceGlassStrong")
    pairs = [(fg, bg, 4.5) for fg in ("colorOnSurface", "colorOnSurfaceVariant", "colorOnSurfaceMuted") for bg in surfaces]
    pairs += [
        ("colorOnPrimary", "colorPrimary", 4.5),
        ("colorOnPrimaryContainer", "colorPrimaryContainer", 4.5),
        ("colorOnSecondaryContainer", "colorSecondaryContainer", 4.5),
    ]
    # Non-text UI: 3:1 against the surfaces they sit on.
    pairs += [(fg, bg, 3.0) for fg in ("colorIndicator", "colorVermillion", "colorOutline") for bg in ("colorTetsu", "colorSurfaceHigh")]
    out = []
    rel = DEFAULTS.relative_to(ROOT).as_posix()
    for fg, bg, need in pairs:
        if fg in tokens and bg in tokens:
            r = ratio(tokens[fg], tokens[bg])
            if r < need:
                out.append(Finding("color-contrast", rel, 0, f"{fg} on {bg} = {r:.2f}:1 < {need}:1"))
    return out


def surface_of(path: str) -> str:
    parts = path.split("/")
    if parts[1] in ("modules", "base") and len(parts) > 3:
        return "/".join(parts[1:4] if parts[1] == "base" and len(parts) > 4 else parts[1:3])
    return "/".join(parts[1:2])


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("paths", nargs="*", help="QML files or directories (default: cortetsu/)")
    ap.add_argument("--json", action="store_true", help="print findings as JSON")
    ap.add_argument("--summary", action="store_true", help="print counts per rule and surface only")
    ap.add_argument("--strict", action="store_true", help="exit 1 when there are findings")
    ap.add_argument("--rule", action="append", help="only report these rules")
    args = ap.parse_args()

    targets = [Path(p).resolve() for p in args.paths] or [QML_ROOT]
    files: list[Path] = []
    for t in targets:
        files += [t] if t.is_file() else sorted(t.rglob("*.qml"))
    files = [f for f in files if not any(s in f.relative_to(QML_ROOT).as_posix() for s in SKIP_DIRS)]

    findings = [f for path in files for f in lint_file(path)]
    if not args.paths:
        findings += contrast_findings()
    if args.rule:
        unknown = set(args.rule) - set(RULES)
        if unknown:
            ap.error(f"unknown rule: {', '.join(sorted(unknown))}")
        findings = [f for f in findings if f.rule in args.rule]

    if args.json:
        print(json.dumps([asdict(f) for f in findings], indent=2))
    elif args.summary:
        by_rule: dict[str, int] = {}
        by_surface: dict[str, int] = {}
        for f in findings:
            by_rule[f.rule] = by_rule.get(f.rule, 0) + 1
            by_surface[surface_of(f.path)] = by_surface.get(surface_of(f.path), 0) + 1
        print(f"qml-design-lint: {len(findings)} findings in {len(files)} files")
        for rule in RULES:
            if rule in by_rule:
                print(f"  {by_rule[rule]:5d}  {rule}  ({RULES[rule]})")
        print("by surface:")
        for surface, count in sorted(by_surface.items(), key=lambda kv: -kv[1]):
            print(f"  {count:5d}  {surface}")
    else:
        for f in findings:
            print(f"{f.path}:{f.line}: {f.rule}: {f.detail}")
        print(f"qml-design-lint: {len(findings)} findings in {len(files)} files", file=sys.stderr)
    return 1 if args.strict and findings else 0


if __name__ == "__main__":
    sys.exit(main())
