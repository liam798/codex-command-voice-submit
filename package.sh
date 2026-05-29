#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
NAME="codex-command-voice-submit"
VERSION="${1:-$(date +%Y%m%d-%H%M%S)}"
DIST_DIR="$ROOT_DIR/dist"
STAGE_DIR="$DIST_DIR/$NAME-$VERSION"
ARCHIVE="$DIST_DIR/$NAME-$VERSION.tar.gz"

cd "$ROOT_DIR"
make clean build
codesign --force --sign - "$ROOT_DIR/.build/$NAME"

rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR/Sources"

cp "$ROOT_DIR/Sources/main.swift" "$STAGE_DIR/Sources/main.swift"
cp "$ROOT_DIR/Makefile" "$STAGE_DIR/Makefile"
cp "$ROOT_DIR/install.sh" "$STAGE_DIR/install.sh"
cp "$ROOT_DIR/uninstall.sh" "$STAGE_DIR/uninstall.sh"
cp "$ROOT_DIR/README.md" "$STAGE_DIR/README.md"
cp "$ROOT_DIR/INSTALL.md" "$STAGE_DIR/INSTALL.md"
cp "$ROOT_DIR/package.sh" "$STAGE_DIR/package.sh"
chmod +x "$STAGE_DIR/install.sh" "$STAGE_DIR/uninstall.sh" "$STAGE_DIR/package.sh"

tar -C "$DIST_DIR" -czf "$ARCHIVE" "$NAME-$VERSION"

echo "$ARCHIVE"
