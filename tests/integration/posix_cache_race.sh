#!/usr/bin/env bash
# Exercise the exact POSIX shell commands used by uosc-waveform's filesystem
# adapter with concurrent processes and real filesystem operations.
set -euo pipefail

case "$(uname -s)" in
  Linux*|MINGW*|MSYS*) ;;
  *) echo "SKIP posix_cache_race: non-POSIX host"; exit 0 ;;
esac

sandbox="$(mktemp -d)"
trap 'rm -rf -- "$sandbox"' EXIT

lock="$sandbox/lock ' ไทย \$HOME ; [ ] .lock"
winners="$sandbox/lock-winners"
: > "$winners"
for i in $(seq 1 32); do
  (
    if /bin/sh -c 'set -C; printf %s "$2" > "$1"' uosc-waveform-lock "$lock" "owner=$i" 2>/dev/null; then
      printf '%s\n' "$i" >> "$winners"
    fi
  ) &
done
wait
[[ "$(wc -l < "$winners")" -eq 1 ]] || { echo "multiple exclusive lock winners" >&2; exit 1; }
[[ "$(cat "$lock")" == "owner=$(cat "$winners")" ]] || { echo "corrupt lock payload" >&2; exit 1; }

# Repeated acquisition must not truncate a lock owned by another process.
if /bin/sh -c 'set -C; printf %s "$2" > "$1"' uosc-waveform-lock "$lock" "intruder" 2>/dev/null; then
  echo "existing lock was overwritten" >&2
  exit 1
fi
[[ "$(cat "$lock")" == "owner=$(cat "$winners")" ]] || exit 1

payload="$sandbox/cache ' ไทย \$HOME ; .bgra"
meta="$sandbox/cache ' ไทย \$HOME ; .meta"
publish_winners="$sandbox/publish-winners"
: > "$publish_winners"

for i in $(seq 1 32); do
  (
    raw_temp="$sandbox/session-$i.tmp"
    meta_temp="$sandbox/session-$i.meta.tmp"
    printf 'payload:%s' "$i" > "$raw_temp"
    printf 'key=%s' "$i" > "$meta_temp"
    # Same no-replace hard-link operation as fs.rename_noreplace() on Linux.
    if /bin/ln -- "$raw_temp" "$payload" 2>/dev/null; then
      rm -- "$raw_temp"
      if /bin/ln -- "$meta_temp" "$meta" 2>/dev/null; then
        rm -- "$meta_temp"
        printf '%s\n' "$i" >> "$publish_winners"
      fi
    fi
  ) &
done
wait

[[ "$(wc -l < "$publish_winners")" -eq 1 ]] || { echo "multiple or no cache publishers" >&2; exit 1; }
winner="$(cat "$publish_winners")"
[[ "$(cat "$payload")" == "payload:$winner" ]] || { echo "raw mismatch" >&2; exit 1; }
[[ "$(cat "$meta")" == "key=$winner" ]] || { echo "manifest mismatch" >&2; exit 1; }

# A late publisher cannot replace either committed file, even on POSIX.
printf 'late' > "$sandbox/late.tmp"
if /bin/ln -- "$sandbox/late.tmp" "$payload" 2>/dev/null; then
  echo "late publisher replaced payload" >&2
  exit 1
fi
[[ "$(cat "$payload")" == "payload:$winner" ]] || exit 1

echo "PASS posix_cache_race: 32 contenders, one lock owner, one publisher, matching commit"
