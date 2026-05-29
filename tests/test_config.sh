#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT_DIR/.build/codex-command-voice-submit"

make -C "$ROOT_DIR" build >/dev/null

output="$(
  CCVS_TRIGGER_MODIFIER=control \
  CCVS_SUBMIT_KEY=tab \
  "$BIN" --check
)"

grep -q '^triggerModifier=control$' <<<"$output"
grep -q '^submitKey=tab$' <<<"$output"

default_output="$("$BIN" --check)"
grep -q '^triggerModifier=command$' <<<"$default_output"
grep -q '^submitKey=return$' <<<"$default_output"
