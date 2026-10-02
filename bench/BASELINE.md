# Performance baseline snapshot

Reference numbers for the Sort library, produced by `bench/run.sh` (see
that script and `bench/sort_bench.aql` for the workload). Reproduce with:

```bash
BORU=/path/to/boru bench/run.sh          # best-of-3 per algorithm
```

**These numbers are indicative, not absolute.** They were measured in a
shared cloud container under variable load, at small sizes. Their value is
*relative*: ranking the algorithms and tracking the library across boru
versions — not comparing boru against a native sort. boru threads a
first-class comparator function through every element move, and that
per-comparison dispatch, not the algorithm, dominates the wall-clock.

## Snapshot — boru main @ 64c5ab2 (2026-10-01), n_small=200 / n_large=800, best-of-2, 60s cap

boru has **one execution path** since 2026-09-19 — every program is
compiled to bytecode and run on the VM — so there is one column. The
interpreter and `--compile` columns of the earlier snapshot (below) no
longer exist: `AQL_NO_COMPILE=1` / `--compile` / `--force-compile` /
`--no-compile` are retired.

```
ALGORITHM     COMPILED_MS
-----------  ------------
insertion           406.0
selection           342.0
bubble              661.0
shell              4490.0
comb                629.0
quick               131.0
merge               259.0
heap                250.0
intro               131.0
tim                5179.0
sort                356.0
counting             57.0
radix-lsd            65.0
bucket              102.0
```

## What the numbers say

- **`quick`, `intro`, `heap`, `merge` and `sort` (the recommended default,
  a stable merge sort) are the fast comparison sorts**; `counting`,
  `radix-lsd` and `bucket` are faster still on bounded Integer input.
- **`tim` now finishes at n=800** (~5 s). On the build of the historical
  snapshot below it raised
  `evaluation_limit` (boru's default 10M runtime step budget) at n≥500, so
  the old table had no compiled number for it. It is still the slowest
  O(n log n) entry — its run detection is a bounded `iota` loop over
  single-cell FlexList cursors with a deep nest of `if` arms per element —
  and remains a candidate for a library optimisation. It is correct: the
  property suites cross-check it against `merge`.
- **`shell` is the slow outlier of the small family** for the same
  reason: a gap sequence driven by bounded loops over state cells.
- Distribution sorts use a **bounded value range** (≈ O(n)); with a
  million-wide range, `counting`/`bucket` would measure the range (they
  are O(n + range)), so the harness caps it.
- `bench/sort_bench.aql` needed two fixes on boru main beyond `/v`: its
  sizes were bound to Capitalised names (`def SMALL 200` binds a *type*, so
  `iota SMALL` is `[]`), and its all-stack `1000000 SMALL mkarr` bound
  `span` to the size and `n` to a million — an out-of-memory kill. It now
  uses lowercase names and the forward call `mkarr 1000000 n-small`
  (signature order: `span`, then `n`).

## Historical snapshot — boru branch build near 6185620 (2026-07), dual surface

Kept for comparison. Measured when boru still had an interpreter
(`AQL_NO_COMPILE=1`) alongside the bytecode VM; the bench then ran with
`AQL_NO_CHECK=1`. n_small=200 / n_large=800, best-of-2, 30s cap.

```
ALGORITHM      INTERP_MS   COMPILED_MS    SPEEDUP
insertion        12119.0         829.0      14.6x
selection         4492.0         848.0       5.3x
bubble            8514.0        1582.0       5.4x
shell               >30s        9397.0          -
comb              7032.0        1666.0       4.2x
quick               >30s         374.0          -
merge            18898.0         465.0      40.6x
heap             10421.0         625.0      16.7x
intro               >30s         363.0          -
tim                 >30s             -          -
sort                >30s         466.0          -
counting           837.0          50.0      16.7x
radix-lsd         2808.0          94.0      29.9x
bucket            1471.0          67.0      22.0x
```

At the time the bytecode VM was 4–40× faster than the interpreter, and the
`bucket` / `shell` rows reflected the `flex[0]`+`set` index-cursor refactor
that let their inner loops lower (the earlier `flex [i]` cursor read the
enclosing `each` frame's iterator through dynamic scope, which the byte
compiler could not bind, so `--compile` silently fell back to the
interpreter).
