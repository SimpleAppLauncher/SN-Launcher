#!/usr/bin/env bash
# Proves which permissions an APK actually declares.
#
# A build must declare exactly the runtime permissions its own features need
# — no fewer, and no more.
#
# No fewer: a permission the manifest does not contain can never be granted.
# The request comes back denied with no dialog ever shown, so the feature
# that wanted it is broken for the life of the install and the user has no
# way to fix it. That is not a permission the user refused; it is a build
# that never asked.
#
# No more: each of these can read something private — or, for notifications,
# interrupt something the user was doing — and Google Play Protect's warning
# at install time is correct. A build that declares the microphone for a
# feature it does not have is asking for access it will never use.
#
# The notification-listener service is not checked here: it is always
# declared so the launcher can read active media sessions, but it is bound by
# the system and does nothing until the user grants Notification access in
# Settings.
#
#     tool/verify_permissions.sh <apk> [expected]
#
# `expected` is a comma-separated list of the runtime permissions the build is
# supposed to declare, for example:
#
#     tool/verify_permissions.sh app-release.apk READ_CALENDAR,RECORD_AUDIO
#
# An empty list — the default — asserts that the build declares none of
# them.
set -uo pipefail
apk="${1:?usage: verify_permissions.sh <apk> [READ_CALENDAR,RECORD_AUDIO]}"
expected="${2:-}"

AAPT2="$(ls -d "${ANDROID_HOME:-$HOME/Library/Android/sdk}"/build-tools/*/aapt2 2>/dev/null | sort -V | tail -1)"
[ -x "$AAPT2" ] || { echo "aapt2 not found" >&2; exit 2; }

RUNTIME='RECORD_AUDIO|READ_CALENDAR|ACCESS_COARSE_LOCATION|ACCESS_FINE_LOCATION|POST_NOTIFICATIONS'

all="$("$AAPT2" dump permissions "$apk" 2>/dev/null | grep -oE "android\.permission\.[A-Z_]+" | sort -u || true)"

found="$(printf '%s\n' "$all" \
  | sed 's/^android\.permission\.//' \
  | grep -E "^($RUNTIME)$" \
  | sort -u \
  | paste -sd, - || true)"

want="$(printf '%s' "$expected" \
  | tr ',' '\n' \
  | sed 's/[[:space:]]//g' \
  | grep -v '^$' \
  | sort -u \
  | paste -sd, - || true)"

echo "  $(basename "$apk")"
echo "    all permissions:"
printf '%s\n' "$all" | sed 's/^/      /'

if [ -n "$found" ]; then
  echo "    runtime: $found"
else
  echo "    runtime: none"
fi

if [ "$found" = "$want" ]; then
  if [ -n "$want" ]; then
    echo "  OK: declares exactly $want"
  else
    echo "  OK: no runtime permissions"
  fi
  exit 0
fi

echo "  FAIL: expected '$want', found '$found'" >&2
if [ -n "$want" ]; then
  echo "        a permission the build declares is one its features cannot use," >&2
  echo "        and a permission it does not declare is one they can never have." >&2
fi
exit 1
