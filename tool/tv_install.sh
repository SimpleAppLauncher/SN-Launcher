#!/usr/bin/env bash
#
# Install and launch the Samsung TV TPK over sdb.
#
# This does not build anything. The TPK must already be signed with a Samsung
# distributor certificate that names the TV's DUID (see docs/TIZEN.md).
#
# Usage:
#   tool/tv_install.sh
#   tool/tv_install.sh /path/to/other.tpk
#   TV_IP=192.168.1.11 tool/tv_install.sh
#
# The first sdb connection to a TV is supposed to put an "Allow" prompt on the
# screen. If this script never sees a device, the TV's sdb daemon is not
# listening, which is a TV-side state, not a network problem: the TV must be
# powered on, developer mode must be on with this Mac's IP, and the TV must have
# been power-cycled after that setting was saved.
set -euo pipefail

cd "$(dirname "$0")/.."

TV_IP="${TV_IP:-192.168.1.11}"
APP_ID="com.giathinh.snlauncher.tv"
TPK="${1:-build/tizen/tpk/${APP_ID}-1.0.0.tpk}"
SDB="${SDB:-$HOME/tizen-sdk/tools/sdb}"
SHOT="${SHOT:-build/tizen/snlauncher-tv.png}"

if [ ! -x "$SDB" ]; then
  echo "!! sdb not found at $SDB" >&2
  echo "   Set SDB=/path/to/sdb or restore the Tizen SDK." >&2
  exit 1
fi
if [ ! -f "$TPK" ]; then
  echo "!! TPK not found at $TPK" >&2
  echo "   Build it with: flutter-tizen build tpk --device-profile tv --target-arch arm --release -s snlauncher" >&2
  exit 1
fi

power_state() {
  curl -s --max-time 4 "http://${TV_IP}:8001/api/v2/" 2>/dev/null |
    sed -n 's/.*"PowerState":"\([^"]*\)".*/\1/p' | head -1
}

echo "== TV ${TV_IP}"
state="$(power_state)"
if [ -n "$state" ]; then
  echo "   PowerState: ${state}"
  if [ "$state" = "standby" ]; then
    echo "!! The TV is in standby. sdb does not accept connections in standby." >&2
    echo "   Turn the TV on with the remote, then run this again." >&2
    exit 1
  fi
else
  echo "   (API did not answer; continuing anyway)"
fi

echo "== sdb connect"
"$SDB" start-server >/dev/null 2>&1 || true
"$SDB" connect "${TV_IP}:26101" 2>&1 | sed 's/^/   /' || true

serial=""
for _ in $(seq 1 24); do
  serial="$("$SDB" devices 2>/dev/null | awk 'NR>1 && $2=="device" {print $1; exit}')"
  [ -n "$serial" ] && break
  sleep 5
done

if [ -z "$serial" ]; then
  cat >&2 <<EOF

!! No authorized sdb device after 2 minutes.

The TV side is the blocker, in this order:

  1. The TV must be ON, not in standby.
  2. Apps -> App Settings -> enter 12345 on the remote.
     Developer mode: On
     Host PC IP:    $(ipconfig getifaddr en0 2>/dev/null || echo '<this Mac>')
  3. Reboot the TV. The developer-mode setting only starts the sdb daemon
     after a reboot. A hard power cycle (unplug for 30 seconds) also clears
     a daemon that accepts TCP and then resets it.
  4. Run this script again and press Allow on the TV when the prompt appears.

Port 26101 accepting a connection and then resetting is the symptom of (3),
not of a certificate or firewall problem.
EOF
  exit 1
fi

echo "== device ${serial}"
echo "== install ${TPK}"
"$SDB" -s "$serial" install "$TPK" 2>&1 | sed 's/^/   /'
echo "== launch ${APP_ID}"
"$SDB" -s "$serial" shell 0 app_launcher -s "$APP_ID" 2>&1 | sed 's/^/   /' || true

sleep 6
mkdir -p "$(dirname "$SHOT")"
echo "== screenshot"
for remote in /tmp/snlauncher-tv.png /opt/usr/media/Images/snlauncher-tv.png; do
  if "$SDB" -s "$serial" shell 0 screenshot "$remote" >/dev/null 2>&1; then
    if "$SDB" -s "$serial" pull "$remote" "$SHOT" >/dev/null 2>&1; then
      echo "   ${SHOT}"
      break
    fi
  fi
done
[ -f "$SHOT" ] || echo "   (screenshot failed; use the TV remote to capture one)"

echo
echo "Done. This is an install, not a verification: look at the TV."
