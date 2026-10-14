#!/usr/bin/env python3
"""Every cortetsu:<name> global that Hyprland dispatches has exactly one QML receiver.

CortetsuShortcut and CustomShortcut are both GlobalShortcut with appid
"cortetsu", so either one receives a cortetsu:<name> dispatch.
"""
from __future__ import annotations

from collections import Counter
from pathlib import Path
import re

REPO = Path(__file__).resolve().parents[2]
LUA = [*sorted((REPO / "dotfiles/home/.config/hypr").rglob("*.lua")), REPO / "config/hypr-user.lua"]
EMIT = re.compile(r'hl\.dsp\.global\(\s*"cortetsu:([\w-]+)"\s*\)')
RECEIVER = re.compile(r'\b(?:CortetsuShortcut|CustomShortcut)\s*\{')
NAME = re.compile(r'\bname\s*:\s*"([\w-]+)"')
NAME_VALUE = re.compile(r'"[\w-]+"')


def strip_lua_comments(text: str) -> str:
    return re.sub(r"--[^\n]*", "", text)


def emitted() -> dict[str, list[str]]:
    found: dict[str, list[str]] = {}
    for path in LUA:
        for name in EMIT.findall(strip_lua_comments(path.read_text(encoding="utf-8"))):
            found.setdefault(name, []).append(str(path.relative_to(REPO)))
    return found


def strip_qml_comments_and_strings(text: str) -> str:
    """Blank comments and string contents so braces in them do not count."""
    pattern = re.compile(r'//[^\n]*|/\*.*?\*/|"(?:[^"\\\n]|\\.)*"', re.S)
    return pattern.sub(lambda match: match.group(0) if match.group(0).startswith('"') and
                       NAME_VALUE.fullmatch(match.group(0)) else " " * len(match.group(0)), text)


def top_level(text: str, start: int) -> str:
    """The block opened just before start, with nested blocks blanked out."""
    depth, body = 1, []
    for character in text[start:]:
        depth += character == "{"
        depth -= character == "}"
        if depth == 0:
            break
        body.append(character if depth == 1 else " ")
    return "".join(body)


def receivers() -> Counter:
    names: Counter = Counter()
    for path in (REPO / "cortetsu").rglob("*.qml"):
        if "tests" in path.parts:
            continue
        text = strip_qml_comments_and_strings(path.read_text(encoding="utf-8"))
        for block in RECEIVER.finditer(text):
            match = NAME.search(top_level(text, block.end()))
            if match:
                names[match.group(1)] += 1
    return names


if __name__ == "__main__":
    sent, received = emitted(), receivers()
    assert sent, "no cortetsu globals found; the Lua layout changed"
    missing = {name: files for name, files in sent.items() if received[name] == 0}
    duplicated = {name: received[name] for name in sent if received[name] > 1}
    assert not missing, f"Hyprland dispatches globals nobody receives: {missing}"
    assert not duplicated, f"dispatched globals with more than one receiver: {duplicated}"
    print(f"PASS: {len(sent)} dispatched cortetsu globals each have exactly one QML receiver")
