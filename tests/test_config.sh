#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT_DIR/.build/codex-command-voice-submit"

make -C "$ROOT_DIR" build >/dev/null

output="$(
  CCVS_TRIGGER_MODIFIER=control \
  CCVS_SUBMIT_KEY=tab \
  CCVS_CANCEL_KEY=space \
  "$BIN" --check
)"

grep -q '^triggerModifier=control$' <<<"$output"
grep -q '^submitKey=tab$' <<<"$output"
grep -q '^cancelKey=space$' <<<"$output"

default_output="$("$BIN" --check)"
grep -q '^triggerModifier=command$' <<<"$default_output"
grep -q '^submitKey=return$' <<<"$default_output"
grep -q '^cancelKey=escape$' <<<"$default_output"

none_output="$(CCVS_CANCEL_KEY=none "$BIN" --check)"
grep -q '^cancelKey=none$' <<<"$none_output"
