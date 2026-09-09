#!/usr/bin/env python3
"""Eval the persisted preference payload against the declared config tree."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
config = (ROOT / "cortetsu/modules/CortetsuConfig.qml").read_text(encoding="utf-8")
save_body = config.split("function save(): void", 1)[1].split("function setFavouriteApps", 1)[0]

assert "bar: { persistent: bar.persistent" in save_body
assert "entries: bar.entries" in save_body
assert ", entries, scrollActions" not in save_body
print("PASS: persisted preferences reference the nested bar.entries property")
