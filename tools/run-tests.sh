#!/usr/bin/env bash
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SCRIPTS="$ROOT/portable_config/scripts"
ENTRY="$SCRIPTS/uosc-waveform.lua"

find_lua() {
  if [[ -n "${LUA_BIN:-}" ]]; then printf '%s\n' "$LUA_BIN"; return; fi
  local candidate
  for candidate in lua54 lua5.4 lua5.3 lua5.2 luajit lua; do
    if command -v "$candidate" >/dev/null 2>&1; then printf '%s\n' "$candidate"; return; fi
  done
  return 1
}

LUA="$(find_lua)" || { echo "ERROR: no Lua interpreter found" >&2; exit 2; }
PASS=0
FAIL=0
TMP_CONFIG="${TMPDIR:-/tmp}/uosc-waveform-test-config-$$"
cleanup() { rm -rf "$TMP_CONFIG"; }
trap cleanup EXIT

run_case() {
  local label="$1"; shift
  printf '%-44s' "$label"
  if "$@"; then
    PASS=$((PASS + 1)); echo " PASS"
  else
    FAIL=$((FAIL + 1)); echo " FAIL"
  fi
}

while IFS= read -r test_file; do
  name="$(basename "$test_file" .lua)"
  rm -rf "$TMP_CONFIG"
  case "$name" in
    syntax_check)
      mapfile -d '' runtime_files < <(find "$SCRIPTS" -type f -name '*.lua' -print0 | sort -z)
      run_case "$name" "$LUA" "$test_file" "${runtime_files[@]}"
      ;;
    controller_mouse_fade|controller_mouse_proximity|controller_nonstandard_uosc)
      run_case "$name" "$LUA" "$test_file" "$SCRIPTS"
      ;;
    bootstrap_single_file|startup_osd_silent)
      run_case "$name" "$LUA" "$test_file" "$ENTRY" "$TMP_CONFIG"
      ;;
    *)
      run_case "$name" "$LUA" "$test_file" "$ROOT"
      ;;
  esac
done < <(find "$ROOT/tests" -maxdepth 1 -type f -name '*.lua' | sort)

while IFS= read -r stress_file; do
  run_case "stress/$(basename "$stress_file" .lua)" "$LUA" "$stress_file" "$ROOT"
done < <(find "$ROOT/tests/stress" -maxdepth 1 -type f -name '*.lua' | sort)

if [[ "${SKIP_FFMPEG_INTEGRATION:-0}" != "1" ]]; then
  if command -v python3 >/dev/null 2>&1 && command -v ffmpeg >/dev/null 2>&1; then
    run_case "integration/ffmpeg_visual_parity" \
      python3 "$ROOT/tests/integration/ffmpeg_visual_parity.py" \
      --root "$ROOT" --lua "$LUA" --ffmpeg ffmpeg
    run_case "integration/ffmpeg_memory_budget" \
      python3 "$ROOT/tests/integration/ffmpeg_memory_budget.py" \
      --root "$ROOT" --lua "$LUA" --ffmpeg ffmpeg
  else
    echo "integration/ffmpeg_visual_parity          SKIP (python3 or ffmpeg missing)"
  fi
fi

echo "RESULT pass=$PASS fail=$FAIL lua=$LUA"
[[ "$FAIL" -eq 0 ]]
