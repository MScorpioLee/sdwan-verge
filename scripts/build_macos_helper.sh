#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT_DIR/macos/Helper/sdwan_macos_helper.c"
OUT_DIR="$ROOT_DIR/build/macos/helper"
OUT="$OUT_DIR/sdwan-macos-helper"

mkdir -p "$OUT_DIR"

clang -std=c11 -Wall -Wextra -O2 "$SRC" -o "$OUT"
chmod 755 "$OUT"
echo "$OUT"
