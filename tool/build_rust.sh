#!/usr/bin/env bash
# Builds the Rust licence filter for Android and drops the .so files where the
# Android build will package them.
#
# The Rust library is optional at runtime: if it is missing, the Dart
# implementation of the same rules runs instead. That is deliberate — the
# licence filter is the highest-stakes pure function in the project (it decides
# whether a photograph may legally be put on a user's wall) and it must not be
# able to take the photo rotation down because a .so failed to build.
#
#     tool/build_rust.sh
#
# The output lands in android/app/src/main/jniLibs/<abi>/ so the Gradle build
# packages it with no extra configuration.
set -euo pipefail
cd "$(dirname "$0")/.."

export PATH="$HOME/.cargo/bin:$PATH"

NDK="${ANDROID_NDK:-$HOME/Library/Android/sdk/ndk/$(ls "$HOME/Library/Android/sdk/ndk" | sort -V | tail -1)}"
if [ ! -d "$NDK" ]; then
  echo "NDK not found at $NDK" >&2
  exit 1
fi
HOST_TAG="$(ls "$NDK/toolchains/llvm/prebuilt" | head -1)"
BIN="$NDK/toolchains/llvm/prebuilt/$HOST_TAG/bin"

# target triple -> rust target -> android API level
#
# API 21 is the floor: Flutter's own minimum is 21, and a lower one buys
# nothing on hardware this old anyway.
build() {
  local triple="$1" rust_target="$2" api="$3"
  local clang="$BIN/${triple}${api}-clang"
  if [ ! -x "$clang" ]; then
    echo "  SKIP $triple — no $clang" >&2
    return 1
  fi
  echo "  building $rust_target"
  # env, not a shell assignment: a computed name cannot be an assignment
  # prefix in bash, and silently doing nothing here would produce an APK with
  # no Rust library in it and no error.
  upper="$(echo "$rust_target" | tr 'a-z-' 'A-Z_')"
  env \
    "CARGO_TARGET_${upper}_LINKER=$clang" \
    "CC_${rust_target//-/_}=$clang" \
    "AR_${rust_target//-/_}=$BIN/llvm-ar" \
    "CARGO_TARGET_${upper}_RUSTFLAGS=-C link-arg=-fuse-ld=lld" \
    cargo build --offline --release --target "$rust_target" \
      --manifest-path native/licence_filter/Cargo.toml
}

build "aarch64-linux-android"    "aarch64-linux-android"    "21"
build "armv7a-linux-androideabi" "armv7-linux-androideabi"  "21"
build "x86_64-linux-android"     "x86_64-linux-android"     "21"

OUT="android/app/src/main/jniLibs"
mkdir -p "$OUT/arm64-v8a" "$OUT/armeabi-v7a" "$OUT/x86_64"

# cargo puts cross-compiled output in the project's target directory, keyed by
# target triple. Reading it from the rustup sysroot instead finds the host's
# directory and silently copies nothing.
DEST="native/licence_filter/target"
cp "$DEST/aarch64-linux-android/release/liblicence_filter.so"    "$OUT/arm64-v8a/"
cp "$DEST/armv7-linux-androideabi/release/liblicence_filter.so"  "$OUT/armeabi-v7a/"
cp "$DEST/x86_64-linux-android/release/liblicence_filter.so"     "$OUT/x86_64/"

echo
echo "  packaged:"
find "$OUT" -name '*.so' -exec ls -la {} \; | awk '{printf "    %-58s %6.0f KB\n", $9, $5/1024}'
