#!/usr/bin/env bash
# ============================================================================
# Campus access tunnel  (runs inside the codespace, from conda_post_start.sh)
# ----------------------------------------------------------------------------
# WHY: the campus firewall actively blocks GitHub's dev tunnels
# (*.devtunnels.ms), so a codespace opens but freezes the moment you try to run
# code. This publishes a browser build of VS Code (code-server) for THIS
# codespace at
#     https://<your-github-username>.149-165-155-34.sslip.io
# through a reverse tunnel to the class relay VM, on a domain the firewall does
# not block.
#
# No secrets and no student setup: the relay is keyless and there is no login to
# type. Access is controlled by an UNGUESSABLE per-codespace URL that is printed
# in the setup log — the student just clicks it. The public repo/image therefore
# never contains a shared secret.
# ============================================================================
set -u

# ---- relay settings (only change if the instructor moves the VM) -----------
RELAY_HOST="149.165.155.34"          # Jetstream relay VM
RELAY_PORT="2222"                    # sish SSH ingress (keyless)
RELAY_DOMAIN="149-165-155-34.sslip.io"
LOCAL_PORT="9999"                    # code-server port (avoids the 8080 used by the template)

WORKDIR="${1:-$PWD}"
log() { echo "[campus-tunnel] $*"; }

# ---- unguessable per-codespace subdomain (the URL IS the access key) --------
# Persisted so it stays the same across restarts of THIS codespace. A new
# codespace gets a new URL. Prefixed with the username so the instructor can tell
# whose it is, but the random suffix is what makes it unguessable.
SUBFILE="$HOME/.campus_subdomain"
if [ ! -s "$SUBFILE" ]; then
  BASE="$(printf '%s' "${GITHUB_USER:-cs}" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9-')"
  [ -n "$BASE" ] || BASE="cs"
  RAND="$(openssl rand -hex 8 2>/dev/null || (date +%s%N | sha1sum | cut -c1-16))"
  echo "${BASE}-${RAND}" > "$SUBFILE"
fi
SUB="$(cat "$SUBFILE")"

# ---- dependencies (safety net; can be baked into the image instead) --------
if ! command -v ssh >/dev/null 2>&1; then
  log "installing openssh-client..."
  sudo apt-get update -y >/dev/null 2>&1 && sudo apt-get install -y openssh-client >/dev/null 2>&1
fi
if ! command -v code-server >/dev/null 2>&1 && [ ! -x "$HOME/.local/bin/code-server" ]; then
  log "installing code-server (first start only, ~30s)..."
  curl -fsSL https://code-server.dev/install.sh | sh -s -- --method=standalone --prefix="$HOME/.local" \
    >/tmp/code-server-install.log 2>&1
fi
export PATH="$HOME/.local/bin:$PATH"

# ---- code-server config: no login (the unguessable URL is the key) ----------
mkdir -p "$HOME/.config/code-server"
cat > "$HOME/.config/code-server/config.yaml" <<EOF
bind-addr: 127.0.0.1:${LOCAL_PORT}
auth: none
cert: false
EOF

# ---- make code-server match the codespace's VS Code (extensions + settings) --
# Uses the Microsoft marketplace + this repo's devcontainer.json extension list
# so Python/Jupyter/R notebooks + kernels work. EXTENSIONS_GALLERY is exported so
# the code-server the supervisor starts (inherited env) also uses that marketplace.
export EXTENSIONS_GALLERY='{"serviceUrl":"https://marketplace.visualstudio.com/_apis/public/gallery","cacheUrl":"https://vscode.blob.core.windows.net/gallery/index","itemUrl":"https://marketplace.visualstudio.com/items"}'
bash "$(dirname "$0")/campus_vscode_setup.sh" "$WORKDIR" >/tmp/campus-vscode-setup.log 2>&1 || true

# ---- ephemeral SSH key so the keyless relay accepts our connection ----------
KEY="$HOME/.ssh/campus_tunnel_ephemeral"
mkdir -p "$HOME/.ssh"; chmod 700 "$HOME/.ssh"
[ -f "$KEY" ] || ssh-keygen -t ed25519 -f "$KEY" -N "" -q

URL="https://${SUB}.${RELAY_DOMAIN}"

# ---- print the access link to the setup log (visible in the Codespaces UI) ---
cat <<BANNER

==================================================================
  CAMPUS ACCESS — open your editor from any browser:

     https://go.${RELAY_DOMAIN}

  Sign in with GitHub and you land straight in your editor.
  (direct link for this codespace: ${URL})
==================================================================

BANNER
log "editor URL: ${URL}"

# ---- launch the supervisor FULLY DETACHED ----------------------------------
# setsid puts it in its own session so it is not reaped when postStart returns.
# (An earlier version backgrounded the loop in postStart's own session and it was
# killed the instant it connected.) Fall back to nohup if setsid is unavailable.
RUNNER="$(dirname "$0")/campus_tunnel_runner.sh"
if command -v setsid >/dev/null 2>&1; then
  setsid nohup bash "$RUNNER" "$SUB" "$KEY" "$LOCAL_PORT" "$RELAY_HOST" "$RELAY_PORT" "$WORKDIR" "$RELAY_DOMAIN" "${CODESPACE_NAME:-}" "${GITHUB_USER:-}" \
    </dev/null >/tmp/campus-tunnel-runner.log 2>&1 &
else
  nohup bash "$RUNNER" "$SUB" "$KEY" "$LOCAL_PORT" "$RELAY_HOST" "$RELAY_PORT" "$WORKDIR" "$RELAY_DOMAIN" "${CODESPACE_NAME:-}" "${GITHUB_USER:-}" \
    </dev/null >/tmp/campus-tunnel-runner.log 2>&1 &
fi
disown 2>/dev/null || true
log "tunnel supervisor launched (log: /tmp/campus-tunnel-runner.log)"
