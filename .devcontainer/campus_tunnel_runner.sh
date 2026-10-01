#!/usr/bin/env bash
# ============================================================================
# Campus tunnel supervisor — long-running, launched DETACHED (setsid) by
# campus_tunnel.sh so it survives postStartCommand completing. (Processes left
# in postStart's own session get reaped when postStart returns; that killed an
# earlier version of this tunnel right after it connected.)
#
# Keeps code-server up and the reverse tunnel to the relay VM connected,
# reconnecting forever.
# ============================================================================
set -u
SUB="$1"; KEY="$2"; LOCAL_PORT="$3"; RELAY_HOST="$4"; RELAY_PORT="$5"; WORKDIR="$6"
RELAY_DOMAIN="${7:-149-165-155-34.sslip.io}"
# Codespace name captured in postStart (passed in, not relied on from this env,
# since the detached runner doesn't reliably inherit CODESPACE_NAME).
CS_NAME="${8:-${CODESPACE_NAME:-}}"
# Username passed in too: the detached runner doesn't reliably inherit
# GITHUB_USER, and `gh auth token` may not be ready at first boot — so the login
# fallback needs an explicit value or registration gets rejected (no identity).
CS_USER="$(printf '%s' "${9:-${GITHUB_USER:-}}" | tr '[:upper:]' '[:lower:]')"

export PATH="$HOME/.local/bin:$PATH"
CS_BIN="$(command -v code-server 2>/dev/null || echo "$HOME/.local/bin/code-server")"

# Tell the sign-in redirector where this student's editor lives, so the fixed
# "Open my editor" link (https://go.<relay>) can forward its owner here. A token
# (if available) lets the relay verify identity; otherwise the explicit login is
# accepted (worst case is redirect griefing, never data access).
register() {
  local token
  token="$(gh auth token 2>/dev/null || echo "${GITHUB_TOKEN:-}")"
  curl -s -m 10 -X POST "https://go.${RELAY_DOMAIN}/register" \
    -H "Content-Type: application/json" \
    -d "{\"sub\":\"${SUB}\",\"login\":\"${CS_USER}\",\"name\":\"${CS_NAME}\",\"token\":\"${token}\"}" \
    >/dev/null 2>&1 || true
}

# Re-register on a timer (not just once per connection): the first attempt can
# land before `gh`/network are ready, and the loop below blocks on ssh -N, so a
# one-shot register would never retry. Also keeps the entry fresh vs. the TTL.
( while true; do register; sleep 120; done ) &

while true; do
  # Keep code-server (browser VS Code) running on the loopback port.
  if ! pgrep -f "code-server" >/dev/null 2>&1; then
    nohup "$CS_BIN" "$WORKDIR" >/tmp/code-server.log 2>&1 &
    sleep 2
  fi

  # (Re)establish the reverse tunnel; ssh -N blocks until the link drops.
  ssh -N -i "$KEY" -p "$RELAY_PORT" \
    -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -o ExitOnForwardFailure=yes -o ServerAliveInterval=30 -o ServerAliveCountMax=3 \
    -R "${SUB}:80:localhost:${LOCAL_PORT}" "tunnel@${RELAY_HOST}"

  sleep 5
done
