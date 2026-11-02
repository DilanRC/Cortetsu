#!/usr/bin/env bash
# Creates .venv with the pinned MCP SDK; touches nothing outside this checkout.
set -euo pipefail
cd "$(dirname "$0")/.."
if command -v uv >/dev/null; then
  uv venv -q .venv --python /usr/bin/python3
  uv pip install -q --python .venv/bin/python 'mcp==2.3.0'
else
  /usr/bin/python3 -m venv .venv
  .venv/bin/python -m pip install -q 'mcp==2.3.0'
fi
.venv/bin/python -c "import importlib.metadata as m; print('mcp', m.version('mcp'))"
