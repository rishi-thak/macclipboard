#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="ClipboardOpt.app"
APP_DIR="$ROOT_DIR/dist/$APP_NAME"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
# Prefer Developer ID, then Apple Development. A stable signature keeps the
# Accessibility grant across rebuilds; an unsigned build must be re-granted.
SIGNING_IDENTITY="${CLIPOPT_SIGNING_IDENTITY:-$(security find-identity -v -p codesigning | awk -F'"' '/Developer ID Application:/{print $2; exit}')}"
if [[ -z "$SIGNING_IDENTITY" ]]; then
  SIGNING_IDENTITY="$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development:/{print $2; exit}')"
fi

cd "$ROOT_DIR"
swift build -c release
BUILD_DIR="$(swift build -c release --show-bin-path)"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$CONTENTS_DIR/Resources"

cp "$ROOT_DIR/App/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$BUILD_DIR/clipboardopt" "$MACOS_DIR/clipboardopt"
chmod +x "$MACOS_DIR/clipboardopt"

if [[ -n "$SIGNING_IDENTITY" ]]; then
  codesign --force --sign "$SIGNING_IDENTITY" --options runtime "$APP_DIR"
else
  codesign --force --sign - "$APP_DIR"
fi

echo "$APP_DIR"
