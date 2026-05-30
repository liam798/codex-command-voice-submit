#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT_DIR/.build/codex-voice-auto-send"

make -C "$ROOT_DIR" build >/dev/null

output="$(
  CCVS_TRIGGER_MODIFIER=control \
  CCVS_TRIGGER_SIDE=right \
  CCVS_SUBMIT_KEY=tab \
  CCVS_CANCEL_KEY=space \
  CCVS_SHOW_HINT=0 \
  CCVS_HINT_TEXT="按 Space 取消自动发送" \
  CCVS_HINT_DURATION_MS=800 \
  "$BIN" --check
)"

grep -q '^triggerModifier=control$' <<<"$output"
grep -q '^triggerSide=right$' <<<"$output"
grep -q '^submitKey=tab$' <<<"$output"
grep -q '^cancelKey=space$' <<<"$output"
grep -q '^showHint=false$' <<<"$output"
grep -q '^hintText=按 Space 取消自动发送$' <<<"$output"
grep -q '^hintDurationMs=800$' <<<"$output"

default_output="$("$BIN" --check)"
grep -q '^minHoldMs=2000$' <<<"$default_output"
grep -q '^triggerModifier=command$' <<<"$default_output"
grep -q '^triggerSide=left$' <<<"$default_output"
grep -q '^submitKey=return$' <<<"$default_output"
grep -q '^cancelKey=escape$' <<<"$default_output"
grep -q '^showHint=true$' <<<"$default_output"
grep -q '^hintText=Esc 取消发送$' <<<"$default_output"
grep -q '^hintDurationMs=1200$' <<<"$default_output"

none_output="$(CCVS_CANCEL_KEY=none "$BIN" --check)"
grep -q '^cancelKey=none$' <<<"$none_output"
