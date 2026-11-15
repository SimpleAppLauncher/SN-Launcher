#!/usr/bin/env bash
#
# Builds the release APKs and publishes them in the shape the in-app updater
# can find.
#
# The names matter. The updater looks for one exact file name per build and
# per device:
#
#     SN-Launcher-<version>-<abi>.apk          the reduced build
#     SN-Launcher-ef-<version>-<abi>.apk       the ef build
#
# and it matches on the name alone. The names the project used to publish —
# `-arm64`, `-armv7`, `-beta-` — are not among them, which is why the older
# releases cannot be updated into.
#
#     tool/publish_release.sh              # build and publish
#     tool/publish_release.sh --dry-run    # build and stage, publish nothing
#
# The dry run exists because publishing is the one step here that cannot be
# undone, and the rest of the script is the part that goes wrong.
set -euo pipefail

cd "$(dirname "$0")/.."

export PATH="$HOME/flutter/bin:$PATH"
export ANDROID_HOME="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
export JAVA_HOME="$(/usr/libexec/java_home -v 17)"

dry_run=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) dry_run=1 ;;
    *) echo "usage: $0 [--dry-run]" >&2; exit 2 ;;
  esac
done

# The version the app reports.
#
# The build number after the '+' is not part of it. The updater compares
# version names, never version codes, because Flutter gives each ABI its own
# version code — 9001 for the universal build, 10001 for arm64 — so a
# version-code comparison would say a device's own build is newer than
# itself.
version="$(sed -n 's/^version: *\([0-9][^ ]*\).*/\1/p' pubspec.yaml | head -1)"
version="${version%%+*}"
[ -n "$version" ] || { echo "could not read the version from pubspec.yaml" >&2; exit 2; }

tag="v$version"

# A version with a dash in it is a pre-release.
#
# GitHub has to be told, or the release appears as the newest *stable* one and
# every user with the updater switched on is offered a build that is not
# finished.
prerelease=0
case "$version" in *-*) prerelease=1 ;; esac

# A release that already exists would be a mistake rather than an update.
# The feed is a list, and two releases with the same tag make the newest one
# ambiguous.
if gh release view "$tag" >/dev/null 2>&1; then
  echo "release $tag already exists — bump the version in pubspec.yaml first" >&2
  exit 1
fi

echo "=== building the release APKs (version $version) ==="
tool/build_variants.sh both

stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT

# The ABIs the APK file names use, and the ones Android reports.
#
# The build script names its outputs after Gradle's ABI names; the platform
# reports the same list. Getting this wrong means a release that exists and
# that the updater cannot find — so the names here are exactly the ones
# `Build.SUPPORTED_ABIS` returns, and `test/publish_release_test.dart` checks
# this table against that list.
canonical_abi() {
  case "$1" in
    arm64-v8a)   echo "arm64-v8a" ;;
    armeabi-v7a) echo "armeabi-v7a" ;;
    armel)       echo "armeabi-v7a" ;;
    x86_64)      echo "x86_64" ;;
    *)           echo "" ;;
  esac
}

apks=()
for f in build/app/outputs/flutter-apk/sn-launcher*-release.apk; do
  [ -e "$f" ] || continue
  base="$(basename "$f")"
  case "$base" in
    sn-launcher.ef-*) variant=ef;      abi="${base#sn-launcher.ef-}" ;;
    sn-launcher-*)    variant=reduced; abi="${base#sn-launcher-}" ;;
    *) continue ;;
  esac
  abi="$(canonical_abi "${abi%-release.apk}")"
  [ -n "$abi" ] || { echo "unknown ABI in $base" >&2; exit 1; }

  if [ "$variant" = "ef" ]; then
    name="SN-Launcher-ef-$version-$abi.apk"
  else
    name="SN-Launcher-$version-$abi.apk"
  fi
  cp "$f" "$stage/$name"
  apks+=("$stage/$name")
  echo "  $name"
done

[ "${#apks[@]}" -gt 0 ] || { echo "no APKs were built" >&2; exit 1; }

# The permissions are checked again here, over the files that are about to be
# published rather than over the build directory.
#
# The build script already checks them; checking the staged copies as well
# means a file that was renamed or copied wrongly is caught before it reaches
# a release that a user might install.
echo "=== checking the published files ==="
for f in "${apks[@]}"; do
  case "$(basename "$f")" in
    SN-Launcher-ef-*) features=assets/features.ef.json ;;
    *)                features=assets/features.json ;;
  esac
  tool/verify_permissions.sh "$f" "$(tool/permissions_for.sh "$features")"
done

# The checksums, so a person downloading by hand can check what they got.
( cd "$stage" && shasum -a 256 ./*.apk > SHA256SUMS )

if [ "$dry_run" = "1" ]; then
  echo
  echo "dry run: nothing was published. The files that would be:"
  ls -1 "$stage"
  echo
  echo "  tag:  $tag"
  exit 0
fi

notes="$stage/NOTES.md"
{
  echo "SN-Launcher $version."
  echo
  echo "The APKs are named for the device they run on:"
  echo
  echo '    SN-Launcher-<version>-<abi>.apk        the reduced build'
  echo '    SN-Launcher-ef-<version>-<abi>.apk     the ef build'
  echo
  echo "SHA256SUMS holds the checksum of each file."
  echo
  echo "These are signed with the project's release key. A build signed with"
  echo "a different key cannot be installed over this one, and will be"
  echo "refused."
} > "$notes"

echo "=== publishing $tag ==="
# Not an array: macOS ships bash 3.2, where "${arr[@]}" on an empty array is an
# unbound-variable error under `set -u`. The build script hit that once.
if [ "$prerelease" = "1" ]; then
  gh release create "$tag" "${apks[@]}" "$stage/SHA256SUMS" \
    --title "SN-Launcher $version" \
    --notes-file "$notes" \
    --prerelease
else
  gh release create "$tag" "${apks[@]}" "$stage/SHA256SUMS" \
    --title "SN-Launcher $version" \
    --notes-file "$notes"
fi

echo
echo "published $tag"
