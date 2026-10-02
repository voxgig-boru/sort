#!/usr/bin/env bash
# The multi-surface gate for this library, rewritten for boru's SINGLE
# execution path.
#
# Since 2026-09-19 boru has ONE way to run a program: it is compiled to
# bytecode and run on the VM, or it fails with
#   [boru/compile_failed] ... this is a compiler defect
# There is no interpreter fallback any more, and the flags this harness
# used to compare — `--compile`, `--force-compile`, `--no-compile` (and the
# BORU_COMPILE / BORU_FORCE_COMPILE / BORU_NO_COMPILE env vars) — are
# RETIRED; passing one is a usage error. The old INTERPRETER / BYTECODE /
# force-compile columns therefore have nothing left to compare: "the suite
# runs" now MEANS "the suite fully compiles". (`boru X` also runs the static
# check as a pre-flight; this harness never passes `-no-check`.)
#
# Two surfaces remain, and BOTH gate:
#
#   run    boru X          compile + run. Must exit 0, and an assertion-
#                          bearing suite must print "all green" (each one
#                          ends by asserting Test.fail-count is 0).
#   check  boru check X    static analysis. Must report 0 errors — for
#                          every suite AND every library module.
#
# `check` used to be advisory here (its false positives on first-class
# function values); on boru main the library and every suite check clean,
# so it gates like everything else.
#
# boru binary: set BORU=/path/to/boru to use an existing build (no network,
# no Go needed). Otherwise this script builds its OWN boru at BORU_REF
# (default: boru-lang/boru main HEAD, resolved at run time), cached under
# ~/.cache/boru-divergence by the resolved SHA. The source is fetched as a
# codeload tarball so it works even where a raw `git clone` of
# boru-lang/boru is blocked; the binary is built from cmd/go as ./boru.
#
# Each boru invocation is bounded by SUITE_TIMEOUT seconds (default 600).
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
SUITE_TIMEOUT="${SUITE_TIMEOUT:-600}"

# Library modules (checked) and suites (run + checked), repo-relative.
MODULES="
sort.aql
"
SUITES="
test/sort_unit_test.aql
test/sort_unit_spec.aql
test/sort_prop_test.aql
test/sort_prop_spec.aql
test/sort_smoke_test.aql
"
# Suites with no assertions: pass = exit 0 (no "all green" line expected).
SMOKE="test/sort_smoke_test.aql"

log() { echo "[divergence] $*"; }

# --- locate or build boru -------------------------------------------------
if [ -n "${BORU:-}" ]; then
  [ -x "$BORU" ] || { echo "error: BORU=$BORU is not an executable." >&2; exit 1; }
else
  BORU_REF="${BORU_REF:-$(git ls-remote https://github.com/boru-lang/boru.git main | cut -f1)}"
  [ -n "$BORU_REF" ] || { echo "error: could not resolve boru main HEAD (network?); set BORU=/path/to/boru." >&2; exit 1; }
  # A symbolic ref (main, a tag, feature/x, refs/heads/main) is mutable and may
  # contain '/': resolve it to the commit it names, so the cache key below is
  # immutable and a valid file name. A hex SHA (full or abbreviated) is used as given.
  case "$BORU_REF" in
    *[!0-9a-f]*)
      _sha="$(git ls-remote https://github.com/boru-lang/boru.git "$BORU_REF" 2>/dev/null | awk -v r="$BORU_REF" '
        $2==r || $2=="refs/heads/"r {h=$1} $2=="refs/tags/"r {t=$1} $2=="refs/tags/"r"^{}" {p=$1}
        END {print (h!="" ? h : (p!="" ? p : t))}')"
      [ -n "$_sha" ] || { echo "error: could not resolve BORU_REF=$BORU_REF to a boru-lang/boru commit (network?); pass a commit SHA or set BORU=/path/to/boru." >&2; exit 1; }
      BORU_REF="$_sha" ;;
  esac
  CACHE="$HOME/.cache/boru-divergence"
  BORU="$CACHE/boru-$BORU_REF"
  if [ ! -x "$BORU" ]; then
    command -v go >/dev/null 2>&1 || { echo "error: Go toolchain not found (or set BORU=/path/to/boru)." >&2; exit 1; }
    log "building boru @ $BORU_REF (one-time; cached) …"
    src="$(mktemp -d)"
    curl -fsSL "https://codeload.github.com/boru-lang/boru/tar.gz/$BORU_REF" \
      | tar -xz -C "$src" --strip-components=1 || { echo "error: fetch/extract failed." >&2; exit 1; }
    mkdir -p "$CACHE"
    ( cd "$src/cmd/go" && GOWORK=off GOFLAGS=-mod=mod go build \
        -ldflags "-X github.com/boru-lang/boru/cmd/go.Version=$BORU_REF" \
        -o "$BORU" ./boru ) || { echo "error: build failed." >&2; rm -rf "$src"; exit 1; }
    rm -rf "$src"
  fi
fi
log "boru: $("$BORU" -version 2>&1)"
echo

cd "$REPO"
fail=0

# check_errors FILE -> prints the error count `boru check` reports ("?" if
# the checker did not get as far as a summary line).
check_errors() {
  local out n
  out="$(timeout "$SUITE_TIMEOUT" "$BORU" check "$1" 2>&1)"
  n="$(printf '%s\n' "$out" | grep -oE 'check( failed)?: [0-9]+ error' | grep -oE '[0-9]+' | tail -1)"
  printf '%s' "${n:-?}"
}

# --- library modules: check ----------------------------------------------
log "modules — boru check (gate: 0 errors):"
printf '  %-28s  %s\n' MODULE CHECK
for m in $MODULES; do
  e="$(check_errors "$m")"
  if [ "$e" = 0 ]; then c_col="ok"; else c_col="FAIL($e errors)"; fail=1; fi
  printf '  %-28s  %s\n' "$m" "$c_col"
done
echo

# --- suites: run (compiled) + check --------------------------------------
log "suites — boru X (gate: exit 0 + \"all green\") and boru check X (gate: 0 errors):"
printf '  %-28s  %-18s  %-14s  %s\n' SUITE RUN CHECK SECONDS
for s in $SUITES; do
  name="$(basename "$s")"
  t0=$(date +%s)
  out="$(timeout "$SUITE_TIMEOUT" "$BORU" "$s" 2>&1)"; rc=$?
  secs=$(( $(date +%s) - t0 ))
  if printf '%s\n' "$out" | grep -q 'boru/compile_failed'; then
    r_col="COMPILE_FAILED"; fail=1
  elif [ $rc -ne 0 ]; then
    r_col="FAIL(rc=$rc)"; fail=1
  elif ! printf '%s\n' "$SMOKE" | grep -qx "$s" && ! printf '%s\n' "$out" | grep -qx 'all green'; then
    r_col="NO-ALL-GREEN"; fail=1
  else
    r_col="ok"
  fi
  e="$(check_errors "$s")"
  if [ "$e" = 0 ]; then c_col="ok"; else c_col="FAIL($e)"; fail=1; fi
  printf '  %-28s  %-18s  %-14s  %s\n' "$name" "$r_col" "$c_col" "$secs"
  if [ "$r_col" != ok ]; then
    printf '%s\n' "$out" | grep -E 'error|FAIL' | head -5 | sed 's/^/      /'
  fi
done

echo
if [ "$fail" = 0 ]; then
  log "PASS — every suite compiles, runs green, and every suite and module checks with 0 errors."
else
  log "FAIL — a suite failed to compile/run/go green, or a check reported errors."
fi
exit $fail
