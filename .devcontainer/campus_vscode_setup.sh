#!/usr/bin/env bash
# ============================================================================
# Make code-server match the codespace's VS Code setup.
#
# code-server ships with the open-source marketplace (Open VSX), which lacks
# Microsoft's Python/Jupyter extensions — so notebooks and kernels don't light
# up. This points code-server at the Microsoft marketplace and installs the
# extension list + settings straight from devcontainer.json (one source of
# truth). Runs once per codespace (guarded by a marker file).
#
# NOTE: using the Microsoft marketplace from a non-Microsoft product is against
# Microsoft's marketplace terms; enabled here deliberately for classroom use.
# ============================================================================
set -u
WORKDIR="${1:-$PWD}"
export PATH="$HOME/.local/bin:$PATH"
CS_BIN="$(command -v code-server 2>/dev/null || echo "$HOME/.local/bin/code-server")"
MARKER="$HOME/.campus_vscode_ready"
DC="$WORKDIR/.devcontainer/devcontainer.json"

# Microsoft marketplace so proprietary Python/Jupyter extensions are installable.
export EXTENSIONS_GALLERY='{"serviceUrl":"https://marketplace.visualstudio.com/_apis/public/gallery","cacheUrl":"https://vscode.blob.core.windows.net/gallery/index","itemUrl":"https://marketplace.visualstudio.com/items"}'

# Pull the extension list + settings out of devcontainer.json (JSONC: strip
# comments + trailing commas) and write code-server's user settings.json.
python3 - "$DC" <<'PY'
import json, sys, re, os
try:
    src = open(sys.argv[1]).read()
except Exception:
    open('/tmp/cs-ext.txt', 'w').write(''); sys.exit(0)
src = re.sub(r'/\*.*?\*/', '', src, flags=re.S)       # /* block */ comments
src = re.sub(r'(?m)^\s*//.*$', '', src)                # // line comments
src = re.sub(r',(\s*[}\]])', r'\1', src)               # trailing commas
try:
    d = json.loads(src)
except Exception:
    open('/tmp/cs-ext.txt', 'w').write(''); sys.exit(0)
vs = d.get('customizations', {}).get('vscode', {})
userdir = os.path.expanduser('~/.local/share/code-server/User')
os.makedirs(userdir, exist_ok=True)
settings = vs.get('settings', {})
# Campus-only overrides: the new "Python Environments" extension otherwise
# auto-picks the empty system interpreter (/usr/bin/python3, no pip/ipykernel)
# for notebooks and hangs trying to install ipykernel. Pin conda as the default
# and hide the system pythons from the kernel picker so students always land on
# /opt/conda (which has ipykernel + all packages). Applied to code-server only,
# not the repo's devcontainer.json.
settings['python.defaultInterpreterPath'] = '/opt/conda/bin/python'
settings['python-envs.defaultEnvManager'] = 'ms-python.python:conda'
settings['jupyter.kernels.filter'] = [
    {'path': '/usr/bin/python3', 'type': 'pythonEnvironment'},
    {'path': '/usr/bin/python3.12', 'type': 'pythonEnvironment'},
    {'path': '/bin/python3', 'type': 'pythonEnvironment'},
]
json.dump(settings, open(userdir + '/settings.json', 'w'), indent=2)
open('/tmp/cs-ext.txt', 'w').write('\n'.join(vs.get('extensions', [])))
PY

# Install each extension once (idempotent; tolerate individual failures, e.g.
# Copilot which needs interactive auth code-server can't do).
if [ ! -f "$MARKER" ]; then
  while IFS= read -r ext; do
    [ -n "$ext" ] || continue
    echo "[campus-vscode] installing $ext"
    "$CS_BIN" --install-extension "$ext" --force >/dev/null 2>&1 || echo "[campus-vscode] (skipped $ext)"
  done < /tmp/cs-ext.txt
  touch "$MARKER"
fi
echo "[campus-vscode] extensions + settings applied"
