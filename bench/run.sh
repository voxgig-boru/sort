#!/usr/bin/env bash
# Performance baseline runner for the Sort library.
#
# Times each representative algorithm sorting a fixed, deterministic
# pseudo-random Integer array and prints one table row per algorithm.
#
# boru has ONE execution path (since 2026-09-19): a program is compiled to
# bytecode and run on the VM, or it fails with `[boru/compile_failed]`.
# The old interpreter column (AQL_NO_COMPILE=1) and the `--compile` column
# are gone — those switches are retired and passing one is a usage error —
# so there is one column of numbers: COMPILED_MS.
#
# Each algorithm runs as its OWN boru process, best-of REPS, with a per-run
# timeout: a dedicated process per cell flushes at exit, and a slow cell is
# marked `>Ns` rather than hanging or corrupting the table. The timing is
# execution-only (boru:time-util around the sort call), so process start,
# the pre-flight check and compilation are excluded.
#
# Usage:  BORU=/path/to/boru bench/run.sh [reps]      # default reps=3
#         BENCH_TIMEOUT=60 …                          # per-run seconds
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/.." && pwd)"
BORU="${BORU:-boru}"
reps="${1:-3}"
to="${BENCH_TIMEOUT:-60}"

command -v "$BORU" >/dev/null 2>&1 || { echo "run.sh: boru not found (set BORU=/path/to/boru)" >&2; exit 1; }

SMALL=200      # O(n^2) / sub-quadratic family
LARGE=800      # O(n log n) / distribution family

# name size kind    (kind: cmp = comparator sort via Sort.by-number/v; dist = no comparator)
ALGOS=(
  "insertion $SMALL cmp"  "selection $SMALL cmp"  "bubble $SMALL cmp"
  "shell $SMALL cmp"      "comb $SMALL cmp"
  "quick $LARGE cmp"      "merge $LARGE cmp"      "heap $LARGE cmp"
  "intro $LARGE cmp"      "tim $LARGE cmp"        "sort $LARGE cmp"
  "counting $LARGE dist"  "radix-lsd $LARGE dist" "bucket $LARGE dist"
)

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# gen <name> <size> <kind> : write a one-algorithm timed program to $tmp/prog.boru.
# The value range is chosen per family: comparison sorts get a near-distinct
# range (few duplicates — the interesting case), while distribution sorts get a
# range of ~O(n) because counting / bucket cost is O(n + range), so a million-
# wide range would measure the range, not the sort.
# The import is absolute: a relative import resolves against the importing
# file's own directory, which here is the temp dir.
gen() {
  local name="$1" size="$2" kind="$3" call span
  if [ "$kind" = dist ]; then call="Sort.$name a"; span=4000; else call="Sort.$name Sort.by-number/v a"; span=1000000; fi
  cat > "$tmp/prog.boru" <<EOF
import "$repo/sort.aql"
import "boru:time-util"
def a (iota $size each [ var [[i] ((i mul 2654435761) mod $span) ] ])
def t (TimeUtil.now)
def _ ($call)
print (TimeUtil.total-ms (TimeUtil.elapsed t))
EOF
}

# best_of <cmd...> : run $tmp/prog.boru `reps` times, echo the min ms, or ""
# when every rep timed out or produced no number.
best_of() {
  local r best="" ms rc
  for ((r=0; r<reps; r++)); do
    ms="$(timeout "$to" "$@" "$tmp/prog.boru" 2>/dev/null | tail -1)"; rc=$?
    [ $rc -ne 0 ] && continue
    case "$ms" in ''|*[!0-9.]*) continue ;; esac
    if [ -z "$best" ] || awk "BEGIN{exit !($ms < $best)}"; then best="$ms"; fi
  done
  echo "$best"
}

echo "# boru: $("$BORU" -version 2>&1)"
echo "# n_small=$SMALL n_large=$LARGE  reps=$reps (best-of)  timeout=${to}s  execution-only ms"
printf '%-11s  %12s\n' ALGORITHM COMPILED_MS
printf '%-11s  %12s\n' ----------- ------------
for spec in "${ALGOS[@]}"; do
  read -r name size kind <<<"$spec"
  gen "$name" "$size" "$kind"
  echo "# … $name (n=$size)" >&2
  c="$(best_of "$BORU")"
  printf '%-11s  %12s\n' "$name" "${c:-">${to}s"}"
done
