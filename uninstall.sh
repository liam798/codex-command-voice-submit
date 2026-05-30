#!/usr/bin/env bash
set -euo pipefail

PLIST_PATH="$HOME/Library/LaunchAgents/com.local.codex-voice-auto-send.plist"
BIN_DST="$HOME/.local/bin/codex-voice-auto-send"
OLD_PLIST_PATH="$HOME/Library/LaunchAgents/com.local.codex-command-voice-submit.plist"
OLD_BIN_DST="$HOME/.local/bin/codex-command-voice-submit"

launchctl unload "$PLIST_PATH" >/dev/null 2>&1 || true
launchctl unload "$OLD_PLIST_PATH" >/dev/null 2>&1 || true
rm -f "$PLIST_PATH" "$BIN_DST" "$OLD_PLIST_PATH" "$OLD_BIN_DST"

echo "已卸载 codex-voice-auto-send。"
