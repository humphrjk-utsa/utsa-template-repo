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

export PATH="$HOME/.local/bin:$PATH"
CS_BIN="$(command -v code-server 2>/dev/null || echo "$HOME/.local/bin/code-server")"

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
