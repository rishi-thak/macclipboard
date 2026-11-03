#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_PATH="$("$ROOT_DIR/scripts/build_app.sh" | tail -n 1)"
INSTALL_DIR="$HOME/Applications"
TARGET_APP="$INSTALL_DIR/ClipboardOpt.app"
AGENT_DIR="$HOME/Library/LaunchAgents"
AGENT_PLIST="$AGENT_DIR/com.rishi.clipboardopt.plist"
SUPPORT_DIR="$HOME/Library/Application Support/ClipboardOpt"

mkdir -p "$INSTALL_DIR" "$AGENT_DIR"
mkdir -p -m 700 "$SUPPORT_DIR"

# The app runs from launchd, so it can't see this project's .env.
# Copy the key file next to the app's data (owner-only). Never printed.
if [[ -f "$ROOT_DIR/.env" ]]; then
  cp "$ROOT_DIR/.env" "$SUPPORT_DIR/.env"
  chmod 600 "$SUPPORT_DIR/.env"
fi

rm -rf "$TARGET_APP"
cp -R "$APP_PATH" "$TARGET_APP"

cat > "$AGENT_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.rishi.clipboardopt</string>
  <key>ProgramArguments</key>
  <array>
    <string>$TARGET_APP/Contents/MacOS/clipboardopt</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
</dict>
</plist>
EOF

launchctl unload "$AGENT_PLIST" >/dev/null 2>&1 || true
pkill -x clipboardopt 2>/dev/null || true
sleep 1
launchctl load "$AGENT_PLIST"

echo "Installed $TARGET_APP"
echo "Loaded $AGENT_PLIST"
