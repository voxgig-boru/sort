# CLAUDE.md

This repository is the `Sort` sorting-algorithms library, written in boru.

## Using the library

See @AGENTS.md for how to call the `Sort` API correctly from boru — the
calling convention, the full API, copy-paste idioms, and the common
mistakes to avoid. Every example there was executed against boru main @
`64c5ab2` (2026-10-01).

## Working on this repository

- A SessionStart hook (`.claude/settings.json` →
  `.claude/hooks/session-start.sh`) builds `boru` from boru-lang/boru
  **main** HEAD (`cmd/go` → `./boru`) in remote sessions, so a fresh
  session can run the suites. Locally, build it once from source (there is
  no tagged release and `go install …/boru@latest` is blocked by replace
  directives) — see [docs/how-to.md](docs/how-to.md#install-and-run-boru).
- **One execution path.** `boru X` runs a static pre-flight check, then
  compiles to bytecode and runs on the VM, or fails with
  `[boru/compile_failed] … compiler defect`. There is no interpreter
  fallback; `--compile` / `--force-compile` / `--no-compile` are retired
  (usage errors). "A suite runs" means "a suite fully compiles". Never use
  `-no-check` to get green.
- **Every comparator argument carries `/v`** (`Sort.by-number/v`,
  `mycmp/v`, `cmp/v`): a bare name holding a function calls it. `/r` is
  the retired spelling.
- The whole library is one file, `sort.aql`, exporting the single `Sort`
  namespace. It had to be one file when boru resolved a function value's
  free words in the module that *ran* it; that is fixed upstream,
  but a comparator reading an imported namespace directly still fails when
  applied as a value for a caller without that import (see `fold-case` in
  `sort.aql`), so comparators and algorithms stay together.
- Relative imports resolve against the **importing file's directory**:
  the suites in `test/` import `"../sort.aql"`.
- Tests live in `test/`, named `sort_<unit|prop>_<test|spec>.aql` plus a
  `sort_smoke_test.aql`: `_test` = imperative (`Test.test`/
  `Test.check-prop`), `_spec` = declarative spec; `unit` = example-based,
  `prop` = property-based. Each assertion-bearing suite ends by asserting
  `Test.fail-count` is `0` and prints `all green`. The keystone property is
  **cross-agreement**: every algorithm must return the same ordering as the
  stable `Sort.merge`.
- `test/divergence/run.sh` is the gate (CI runs it): every suite must exit
  0 under `boru X` and print `all green` where it asserts, and `boru check`
  must report 0 errors on every suite **and** on `sort.aql`. It builds its
  own boru at main HEAD (codeload tarball) unless given
  `BORU=/path/to/boru`. See its `README.md`.
- `DESIGN.md` holds the argued plan for work that is **designed but not
  implemented** — currently the topological-sort family (a comparator
  orders the ready set, so it degenerates to a plain sort on an edgeless
  graph) and a prioritised catalogue of the other missing ordering
  families (selection, ranking, multi-key combinators, sorted-sequence
  operations). Read it before adding a new family: it records the naming
  collisions, the boru runtime constraints that force each shape, and the
  reasons several obvious-looking candidates were declined.
- boru-runtime gotchas discovered while building this library are captured
  inline as code comments in `sort.aql`, in AGENTS.md's "Common mistakes",
  and in `DX-REPORT.md` — whose "Migration to boru main @ 64c5ab2" section
  lists the three open upstream defects `sort.aql` / the suites work around
  (each commented at its site; remove the workaround when fixed upstream).
- The library tracks boru **main** (no pinned commit): CI, the hook and the
  gate all resolve main HEAD at run time. Last verified against boru main
  @ `64c5ab2` (2026-10-01).
- Forking this repo to start a new boru library? See `TEMPLATE.md`.
