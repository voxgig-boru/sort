# The single-path gate: run · check

This library's suites are written once and must run green on the boru that
users have. `run.sh` is the gate CI runs (`.github/workflows/test.yml`, the
`divergence` job). Last verified against **boru main @ 64c5ab2**
(2026-10-01).

## One execution path

Since 2026-09-19 boru has **one** way to run a program: it is compiled to
bytecode and run on the VM, or it fails with

```
[boru/compile_failed] ... this is a compiler defect
```

There is **no interpreter fallback** any more. The flags this harness used
to compare — `--compile`, `--force-compile`, `--no-compile`, and the
`BORU_COMPILE` / `BORU_FORCE_COMPILE` / `BORU_NO_COMPILE` env vars — are
**retired**; passing one is a usage error. The harness's old
INTERPRETER / BYTECODE / `--force-compile` columns therefore have nothing
left to compare, and are gone: *"the suite runs"* now **means** *"the suite
fully compiles"*. `boru X` also runs the static check as a pre-flight and
refuses on a check error; this harness never passes `-no-check`.

Two surfaces remain, and **both gate**:

```bash
boru X         # compile + run. Must exit 0, and an assertion-bearing suite
               #   must print "all green" (each one ends by asserting
               #   Test.fail-count is 0).            (GATING)
boru check X   # static analysis. Must report 0 errors — for every suite
               #   AND for the library module sort.aql.  (GATING)
```

`boru check` used to be advisory here (its false positives on first-class
function values — this library threads comparator functions through every
sort). On boru main the module and every suite check with 0 errors and 0
warnings, so it gates like everything else.

## Running it

```bash
test/divergence/run.sh                           # builds its own boru (main HEAD)
BORU=/path/to/boru test/divergence/run.sh        # reuse an existing binary
BORU_REF=<40-char sha> test/divergence/run.sh    # build a specific ref
SUITE_TIMEOUT=600 …                              # per-invocation seconds (default 600)
```

Without `BORU`, `run.sh` resolves boru-lang/boru **main HEAD** at run time,
fetches it as a codeload tarball (works even where a raw `git clone` of
boru-lang/boru is blocked), builds `cmd/go` → `./boru`, and caches the
binary in `~/.cache/boru-divergence` keyed by the SHA. That needs `go` +
network once per new main HEAD.

Output (boru main @ 64c5ab2):

```
[divergence] modules — boru check (gate: 0 errors):
  MODULE                        CHECK
  sort.aql                      ok

[divergence] suites — boru X (gate: exit 0 + "all green") and boru check X (gate: 0 errors):
  SUITE                         RUN                 CHECK           SECONDS
  sort_unit_test.aql            ok                  ok              6
  sort_unit_spec.aql            ok                  ok              3
  sort_prop_test.aql            ok                  ok              5
  sort_prop_spec.aql            ok                  ok              9
  sort_smoke_test.aql           ok                  ok              6

[divergence] PASS — every suite compiles, runs green, and every suite and module checks with 0 errors.
```

A RUN cell reads `COMPILE_FAILED` (the compiler refused the program),
`FAIL(rc=N)` (a runtime error, a check error in the pre-flight, or a
failing final assertion), or `NO-ALL-GREEN` (exit 0 but the summary line
is missing). `test/sort_smoke_test.aql` carries no assertions, so it only
has to exit 0.

## Background: what this guarded against, and what it guards now

Before the single path, `boru --compile` was documented to return results
identical to the interpreter, and this harness compared the two so a
compiler divergence on any algorithm would surface (the keystone property
— every algorithm equals the stable `Sort.merge` — ran under both). With
one path there is nothing to diverge *from*; a compiler defect now shows
up either as a loud `compile_failed` or as a wrong answer that the
property suites catch against `Sort.merge`. Two such defects were hit and
worked around during the 64c5ab2 migration — see `DX-REPORT.md`,
"Migration to boru main @ 64c5ab2".
