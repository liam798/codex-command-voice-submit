#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
BIN_SRC="$ROOT_DIR/.build/codex-voice-auto-send"
INSTALL_DIR="$HOME/.local/bin"
BIN_DST="$INSTALL_DIR/codex-voice-auto-send"
PLIST_DIR="$HOME/Library/LaunchAgents"
PLIST_PATH="$PLIST_DIR/com.local.codex-voice-auto-send.plist"
OLD_PLIST_PATH="$PLIST_DIR/com.local.codex-command-voice-submit.plist"
OLD_BIN_DST="$INSTALL_DIR/codex-command-voice-submit"

if [[ ! -x "$BIN_SRC" ]]; then
  echo "请先运行：make build"
  exit 1
fi

mkdir -p "$INSTALL_DIR" "$PLIST_DIR"
launchctl unload "$OLD_PLIST_PATH" >/dev/null 2>&1 || true
rm -f "$OLD_PLIST_PATH" "$OLD_BIN_DST"

cp "$BIN_SRC" "$BIN_DST"
chmod +x "$BIN_DST"

cat > "$PLIST_PATH" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.local.codex-voice-auto-send</string>
  <key>ProgramArguments</key>
  <array>
    <string>$BIN_DST</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>StandardOutPath</key>
  <string>$HOME/Library/Logs/codex-voice-auto-send.log</string>
  <key>StandardErrorPath</key>
  <string>$HOME/Library/Logs/codex-voice-auto-send.err.log</string>
  <key>EnvironmentVariables</key>
  <dict>
    <key>CCVS_MIN_HOLD_MS</key>
    <string>${CCVS_MIN_HOLD_MS:-2000}</string>
    <key>CCVS_SUBMIT_DELAY_MS</key>
    <string>${CCVS_SUBMIT_DELAY_MS:-900}</string>
    <key>CCVS_TRIGGER_MODIFIER</key>
    <string>${CCVS_TRIGGER_MODIFIER:-command}</string>
    <key>CCVS_TRIGGER_SIDE</key>
    <string>${CCVS_TRIGGER_SIDE:-left}</string>
    <key>CCVS_SUBMIT_KEY</key>
    <string>${CCVS_SUBMIT_KEY:-return}</string>
    <key>CCVS_CANCEL_KEY</key>
    <string>${CCVS_CANCEL_KEY:-escape}</string>
    <key>CCVS_SHOW_HINT</key>
    <string>${CCVS_SHOW_HINT:-1}</string>
    <key>CCVS_HINT_TEXT</key>
    <string>${CCVS_HINT_TEXT:-}</string>
    <key>CCVS_APP_NAMES</key>
    <string>${CCVS_APP_NAMES:-Codex,Code X,CodeX}</string>
    <key>CCVS_BUNDLE_IDS</key>
    <string>${CCVS_BUNDLE_IDS:-com.openai.codex,com.openai.chatgpt}</string>
    <key>CCVS_VERBOSE</key>
    <string>${CCVS_VERBOSE:-0}</string>
  </dict>
</dict>
</plist>
PLIST

launchctl unload "$PLIST_PATH" >/dev/null 2>&1 || true
launchctl load "$PLIST_PATH"

echo "已安装并启动：$BIN_DST"
echo "如未生效，请在系统设置 -> 隐私与安全性中授予辅助功能和输入监控权限。"
