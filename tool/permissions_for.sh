#!/usr/bin/env bash
# Prints the runtime permissions a build with these features should declare.
#
#     tool/permissions_for.sh assets/features.json
#
# The output is a comma-separated list of Android permission names, or
# nothing when the build needs none of them.
#
# This file is the shell half of a decision that is also made in Dart, in
# lib/src/services/permission_service.dart. The two have to agree: a build
# that declares a permission its features do not use is asking for access it
# will never use, and a build that does not declare one its features need is
# a build whose feature can never work.
#
# test/permission_service_test.dart runs this script and compares what it
# says against what the app expects, so the two cannot drift.
#
# The feature names here are the same names the Dart side uses.
permission_for_feature() {
  case "$1" in
    calendar)     echo "READ_CALENDAR" ;;
    weather)      echo "ACCESS_COARSE_LOCATION" ;;
    voiceCommand) echo "RECORD_AUDIO" ;;
    music)        echo "POST_NOTIFICATIONS" ;;
    *)            ;;
  esac
}

# Is a feature switched on in this build's feature file?
#
# A grep, not a JSON parser: the feature files are written by hand with one
# boolean per line, and a build script that needs a JSON library to read its
# own configuration is a build script that will not run on the next machine.
feature_enabled() {
  local file="$1" feature="$2"
  grep -Eq "\"$feature\"[[:space:]]*:[[:space:]]*true" "$file"
}

# The comma-separated permission list a build should declare.
#
# The order matches the order of kPermissionRequirements in the Dart side,
# because the test compares the two strings.
required_permissions() {
  local features_file="$1"
  local names=()
  local feature permission
  for feature in calendar weather voiceCommand music; do
    feature_enabled "$features_file" "$feature" || continue
    permission="$(permission_for_feature "$feature")"
    [ -n "$permission" ] && names+=("$permission")
  done
  if [ ${#names[@]} -eq 0 ]; then
    echo ""
    return
  fi
  printf '%s\n' "${names[@]}" | awk 'NF && !seen[$0]++' | paste -sd, -
}

# Run directly: print the list for the feature file given as an argument.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  required_permissions "${1:?usage: permissions_for.sh <features.json>}"
fi
