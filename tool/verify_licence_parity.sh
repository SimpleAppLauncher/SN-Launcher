#!/usr/bin/env bash
# Proves the Rust licence filter and the Dart one agree.
#
# Not a nice-to-have. The Rust version decides whether a photograph may legally
# be put on a user's wall, so a divergence is a licensing bug rather than a
# performance one. Both run over the same corpus of real Commons licence
# strings — most of which are share-alike, which is the whole trap — and the
# outputs are diffed.
#
#     tool/verify_licence_parity.sh
set -uo pipefail
cd "$(dirname "$0")/.."

CORPUS="native/licence_filter/corpus.txt"
if [ ! -f "$CORPUS" ]; then
  echo "corpus missing: $CORPUS" >&2
  exit 2
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

python3 tool/licence_reference.py < "$CORPUS" \
  | sed 's/^true/1/I; s/^false/0/I' > "$TMP/dart"
( cd native/licence_filter && \
  cargo run --offline --release --example parity < "$OLDPWD/$CORPUS" 2>/dev/null ) \
  | sed 's/^true/1/I; s/^false/0/I' > "$TMP/rust"

n=$(wc -l < "$CORPUS" | tr -d ' ')
if diff -q "$TMP/dart" "$TMP/rust" > /dev/null; then
  echo "PARITY OK — $n licence strings agree"
  echo "  allow: $(grep -c '^1' "$TMP/rust")   refuse: $(grep -c '^0' "$TMP/rust")"
else
  echo "DIVERGENCE — Rust and Dart disagree. This is a licensing bug:" >&2
  diff "$TMP/dart" "$TMP/rust" >&2
  exit 1
fi
