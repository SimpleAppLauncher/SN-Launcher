#!/usr/bin/env bash
#
# Full TCP port scan for the Samsung TV, plus a service probe and an sdb
# handshake check. This is a diagnostic tool, not part of the app.
#
# Usage:
#   tool/tv_scan.sh
#   tool/tv_scan.sh 192.168.1.11
#   TV_IP=192.168.1.11 tool/tv_scan.sh
#
# Why: 26101 accepting TCP and then resetting the sdb CNXN packet means the
# sdb daemon is not up. This scan proves whether any other sdb-like port is
# listening. It is a TCP connect scan (no root required); UDP is not scanned.
set -euo pipefail

cd "$(dirname "$0")/.."

TV_IP="${1:-${TV_IP:-192.168.1.11}}"
NMAP="${NMAP:-nmap}"
OUT="${OUT:-build/tizen/tv_scan_${TV_IP}.txt}"

if ! command -v "$NMAP" >/dev/null 2>&1; then
  echo "!! nmap not found. Install it with: brew install nmap" >&2
  exit 1
fi

mkdir -p "$(dirname "$OUT")"

echo "== full TCP scan ${TV_IP} (1-65535)"
echo "   output: ${OUT}"
"$NMAP" -Pn -sT -p- --open -T4 --min-rate 1000 --max-retries 1 \
  --defeat-rst-ratelimit --host-timeout 300s "$TV_IP" | tee "$OUT"

ports="$(
  awk '/^[0-9]+\/tcp[[:space:]]+open/ { sub("/tcp", "", $1); print $1 }' "$OUT" |
    paste -sd, -
)"

if [ -z "$ports" ]; then
  echo
  echo "No open TCP ports found. The TV may be off, filtering, or on a different network."
  exit 0
fi

echo
echo "== open TCP ports"
echo "   ${ports}"

echo
echo "== service probe"
"$NMAP" -Pn -sT -sV --version-light -p "$ports" "$TV_IP" | tee -a "$OUT"

if printf ',%s,' "$ports" | grep -q ',26101,'; then
  echo
  echo "== sdb handshake on 26101"
  python3 - "$TV_IP" <<'PY'
import socket
import sys

ip = sys.argv[1]
s = socket.socket()
s.settimeout(5)
try:
    s.connect((ip, 26101))
    print("TCP connect: ok")
    payload = b"host::\x00"
    pkt = (
        b"CNXN"
        + len(payload).to_bytes(4, "little")
        + (0x40).to_bytes(4, "little")
        + (0x02000000).to_bytes(4, "little")
        + (0).to_bytes(4, "little")
        + payload
    )
    s.sendall(pkt)
    try:
        data = s.recv(64)
        if not data:
            print("sdb reply: empty (daemon closed)")
        elif data[:4] == b"CNXN":
            print("sdb reply: CNXN (daemon is up)")
        elif data[:4] == b"AUTH":
            print("sdb reply: AUTH (daemon is up, authorization needed)")
        else:
            print("sdb reply:", data[:32])
    except ConnectionResetError:
        print("sdb reply: connection reset (daemon not up / not authorized)")
    except socket.timeout:
        print("sdb reply: timeout")
finally:
    s.close()
PY
fi

if printf ',%s,' "$ports" | grep -q ',8001,'; then
  echo
  echo "== Samsung TV API on 8001"
  curl -s --max-time 5 "http://${TV_IP}:8001/api/v2/" |
    python3 -c 'import sys,json; d=json.load(sys.stdin)["device"]; print("PowerState:", d.get("PowerState"), "developerMode:", d.get("developerMode"), "developerIP:", d.get("developerIP"))' 2>/dev/null ||
    echo "   (API did not return the expected JSON)"
fi

echo
echo "Done. An open port is not an sdb port unless it speaks the sdb CNXN protocol."
