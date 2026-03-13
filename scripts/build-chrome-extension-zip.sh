#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_DIR="$ROOT_DIR/ChromeExtension"
OUTPUT_DIR="$ROOT_DIR/docs/downloads"
OUTPUT_FILE="$OUTPUT_DIR/eir-chrome-extension.zip"

mkdir -p "$OUTPUT_DIR"
rm -f "$OUTPUT_FILE"

(
  cd "$ROOT_DIR"
  export COPYFILE_DISABLE=1
  zip -rq "$OUTPUT_FILE" "ChromeExtension" \
    -x "ChromeExtension/.DS_Store" \
    -x "ChromeExtension/**/.DS_Store"
)

printf 'Created %s\n' "$OUTPUT_FILE"
