#!/usr/bin/env bash
set -euo pipefail

PLIST_PATH="$HOME/Library/LaunchAgents/com.local.codex-command-voice-submit.plist"
BIN_DST="$HOME/.local/bin/codex-command-voice-submit"

launchctl unload "$PLIST_PATH" >/dev/null 2>&1 || true
rm -f "$PLIST_PATH" "$BIN_DST"

echo "已卸载 codex-command-voice-submit。"
