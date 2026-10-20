#!/usr/bin/env python3
"""Strip personal paths from published evidence, or check that none are left.

    python3 -I sanitize_evidence.py [--check] DIR...

Rewrites, in every .json/.txt/.log/.jsonl file under each DIR:

  <the checkout this script lives in>                         -> <repo>
  /tmp/claude-<uid>/<project>/<session>/scratchpad/main-wt    -> <main-worktree>
  /tmp/claude-<uid>/<project>/<session>/scratchpad/<rest>     -> <scratch>/<rest>

Only string values change. For JSON files it then reloads both versions and
fails if any number, boolean, key or list length differs, so a measurement can
never be edited by accident. --check rewrites nothing and exits 1 if a file
still holds a home directory, a Claude scratchpad, /run/user/<uid>, this host's
name or this user's login.
"""
import getpass, json, re, socket, sys
from pathlib import Path

REPO = str(Path(__file__).resolve().parents[4])
SCRATCH = r"/tmp/claude-\d+/[^/\s\"']+/[0-9a-f-]{36}/scratchpad"
RULES = [(re.compile(re.escape(REPO)), "<repo>"),
         (re.compile(SCRATCH + r"/main-wt"), "<main-worktree>"),
         (re.compile(SCRATCH), "<scratch>")]
LEAKS = re.compile("|".join([r"/home/[a-z_][^/\s\"']*/", r"/tmp/claude-\d+", r"/run/user/\d+",
                             re.escape(socket.gethostname()), r"\b" + re.escape(getpass.getuser()) + r"\b"]))


def skeleton(value):
    """Everything but the text of strings: keys, numbers, booleans, nulls, shape."""
    if isinstance(value, dict):
        return {k: skeleton(v) for k, v in value.items()}
    if isinstance(value, list):
        return [skeleton(v) for v in value]
    return "<str>" if isinstance(value, str) else value


check = sys.argv[1:2] == ["--check"]
files = [p for d in sys.argv[1 + check:] for p in sorted(Path(d).rglob("*"))
         if p.suffix in {".json", ".jsonl", ".txt", ".log"} and p.is_file()]
leaks = 0
for path in files:
    text = path.read_text()
    if check:
        for n, line in enumerate(text.splitlines(), 1):
            for m in LEAKS.finditer(line):
                print(f"{path}:{n}: {m.group(0)}")
                leaks += 1
        continue
    new = text
    for pattern, repl in RULES:
        new = pattern.sub(repl, new)
    if new == text:
        continue
    if path.suffix == ".json":
        assert skeleton(json.loads(text)) == skeleton(json.loads(new)), f"{path}: a non-text value changed"
    elif path.suffix == ".jsonl":
        for a, b in zip(text.splitlines(), new.splitlines(), strict=True):
            assert skeleton(json.loads(a)) == skeleton(json.loads(b)), f"{path}: a non-text value changed"
    path.write_text(new)
    print(f"sanitized {path}")
sys.exit(1 if leaks else 0)
