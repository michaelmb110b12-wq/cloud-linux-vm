#!/bin/bash
set -u

MACHINE="${INSTABOX_MACHINE:-linux-guaq}"
LOCAL_PORT="${INSTABOX_LOCAL_PORT:-15901}"
REMOTE_PORT="${INSTABOX_REMOTE_PORT:-5901}"
CLI="/opt/instabox-install/.local/bin/instabox"

log() {
  printf '[instabox-tunnel] %s\n' "$*"
}

export INSTABOX_API_URL="${INSTABOX_API_URL:-https://api.instabox.sh}"
export PATH="/opt/instabox-install/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

if [ -z "${INSTABOX_API_KEY:-}" ]; then
  log "INSTABOX_API_KEY is missing; automatic VM startup is disabled."
  exit 0
fi

if [ ! -x "$CLI" ]; then
  log "InstaBox CLI is missing at $CLI"
  exit 1
fi

mkdir -p "${HOME:-/tmp}/.ssh"

TUNNEL_PID=""
cleanup() {
  if [ -n "$TUNNEL_PID" ]; then
    kill -TERM "$TUNNEL_PID" 2>/dev/null || true
    wait "$TUNNEL_PID" 2>/dev/null || true
  fi
}
stop() {
  cleanup
  exit 0
}
trap cleanup EXIT
trap stop INT TERM

while true; do
  STATUS="$("$CLI" ls 2>/dev/null | awk -v machine="$MACHINE" '$1 == machine { print $2; exit }')"

  case "$STATUS" in
    Running)
      log "$MACHINE is running."
      ;;
    Paused|Suspended)
      log "$MACHINE is paused; resuming it."
      "$CLI" resume "$MACHINE" || true
      sleep 5
      continue
      ;;
    Stopped)
      log "$MACHINE is stopped; starting it."
      "$CLI" start "$MACHINE" || true
      sleep 5
      continue
      ;;
    Starting|Resuming|Provisioning)
      log "$MACHINE is $STATUS; waiting."
      sleep 5
      continue
      ;;
    "")
      log "Could not read the state of $MACHINE; retrying."
      sleep 10
      continue
      ;;
    *)
      log "$MACHINE reports state '$STATUS'; checking again shortly."
      sleep 10
      continue
      ;;
  esac

  log "Opening VNC tunnel 127.0.0.1:$LOCAL_PORT -> $MACHINE:$REMOTE_PORT"
  "$CLI" port-forward "$MACHINE" "$LOCAL_PORT:$REMOTE_PORT" &
  TUNNEL_PID=$!
  wait "$TUNNEL_PID"
  RESULT=$?
  TUNNEL_PID=""
  log "VNC tunnel exited (status $RESULT); checking the VM and reconnecting in 5 seconds."
  sleep 5
done
