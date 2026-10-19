#!/usr/bin/env bash
# Proves which permissions an APK actually declares.
#
# This exists because Google Play Protect warns on install when an app asks for
# the microphone, the calendar, the location, or the notification listener, and
# the warning is correct: each of those can read something private, and the
# notification listener can read every notification on the device.
#
# The safe build must declare none of them. If this script fails, the build is
# not the build people are supposed to be installing.
#
#     tool/verify_permissions.sh <apk> [expected: safe|sensitive]
set -uo pipefail
apk="${1:?usage: verify_permissions.sh <apk> [safe|sensitive]}"
expected="${2:-safe}"
AAPT2="$(ls -d "${ANDROID_HOME:-$HOME/Library/Android/sdk}"/build-tools/*/aapt2 2>/dev/null | sort -V | tail -1)"
[ -x "$AAPT2" ] || { echo "aapt2 not found" >&2; exit 2; }

SENSITIVE='RECORD_AUDIO|READ_CALENDAR|ACCESS_COARSE_LOCATION|ACCESS_FINE_LOCATION'
found="$("$AAPT2" dump permissions "$apk" 2>/dev/null | grep -oE "android\.permission\.[A-Z_]+" | sort -u | grep -E "$SENSITIVE" || true)"

echo "  $(basename "$apk")"
echo "    all permissions:"
"$AAPT2" dump permissions "$apk" 2>/dev/null | grep -oE "android\.permission\.[A-Z_]+" | sort -u | sed 's/^/      /'

if [ -n "$found" ]; then
  echo "    sensitive: $(echo "$found" | tr '\n' ' ')"
else
  echo "    sensitive: none"
fi

case "$expected" in
  safe)
    if [ -n "$found" ]; then
      echo "  FAIL: a safe build must not declare $(echo "$found" | tr '\n' ' ')" >&2
      exit 1
    fi
    echo "  OK: no sensitive permissions"
    ;;
  sensitive)
    if [ -z "$found" ]; then
      echo "  FAIL: a sensitive build was expected to declare them" >&2
      exit 1
    fi
    echo "  OK: sensitive permissions present as asked"
    ;;
esac
