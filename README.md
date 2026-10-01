# sort

A dependency-light **sorting library** implemented in
[boru](https://github.com/boru-lang/boru) — every well-known sorting
algorithm, over every boru type, driven by composable **comparators**.
Sorts return a new sorted list and never mutate their input.

```boru
import "./sort.aql"

print (Sort.quick Sort.by-number/v [5 3 8 1])                 # => [1, 3, 5, 8]
print (Sort.merge Sort.natural/v ["file10" "file2" "file1"])  # => ["file1", "file2", "file10"]
print (Sort.radix-lsd [170 45 75 2 802 24])                   # => [2, 24, 45, 75, 170, 802]
```

> **Calling convention — forward args, receiver (list) last:**
> `Sort.<algo> comparator list`. Piping `list Sort.<algo> comparator` also
> works; only `Sort.<algo> list comparator` misbinds (`boru check` rejects
> it). **Every comparator argument carries `/v`** — `Sort.by-number/v`,
> your own `mycmp/v`, the built-in `cmp/v` — because a bare name that holds
> a function calls it.

> **Verified against boru main @ `64c5ab2`** (2026-10-01). The library
> tracks boru `main` (no pinned commit); see `DX-REPORT.md`, "Migration to
> boru main @ 64c5ab2", for what changed.

> **Forking this to build a new boru library?** This repo is a GitHub
> template — read **[TEMPLATE.md](TEMPLATE.md)** for the instantiation
> checklist, then delete it.

> **Calling this library from an AI coding agent?** Read
> **[AGENTS.md](AGENTS.md)** first — the exact boru calling convention,
> verified idioms, and common mistakes. (Claude Code auto-loads it via
> `CLAUDE.md`; a portable skill lives in
> [`.claude/skills/sort-aql`](.claude/skills/sort-aql/SKILL.md).)

## What you get

- **Comparison sorts** — `quick`, `merge` (stable), `heap`, `intro`,
  `tim` (stable), `insertion`, `selection`, `bubble`, `shell`, `comb`,
  `cocktail`, `gnome`, `cycle`, `odd-even`, `pancake`, `bitonic`.
- **Distribution sorts** (Integers, no comparator) — `counting`,
  `pigeonhole`, `radix-lsd`, `radix-msd`, `bucket`, `bead`.
- **Joke / educational sorts** — `bogo`, `stooge`, `slow`.
- **Comparators** — `by-number`, `by-string`, `by-boolean`,
  `by-generic`, `natural` (alphanumeric, so `"file2" < "file10"`),
  `case-insensitive`, plus the combinators `reverse` and `by-key`.

Sort anything by supplying a comparator — a two-argument function
returning a negative/zero/positive `Integer`, the same contract as the
built-in `cmp`:

```boru
def by-len fn [[b:Any a:Any] [Integer] [ (a size) (b size) cmp ]]
print (Sort.merge by-len/v ["bbb" "a" "cc"])   # => ["a", "cc", "bbb"]
```

## Documentation

The docs follow the [Diátaxis](https://diataxis.fr) framework — four
modes, each serving a different need. Start wherever your need is:

| | Mode | Read this when you want to… |
|--|------|----------------------------|
| 🎓 | **[Tutorial](docs/tutorial.md)** | learn by sorting your first list step by step |
| 🔧 | **[How-to guides](docs/how-to.md)** | accomplish a specific task (custom order, natural sort, by-key…) |
| 📖 | **[Reference](docs/reference.md)** | look up exact words, return types, stability, complexity |
| 💡 | **[Explanation](docs/explanation.md)** | understand the comparator-driven design and why it's built this way |

New here? Read the [Tutorial](docs/tutorial.md). Already know your
algorithms and just want the API? Jump to the [Reference](docs/reference.md).

## The `Sort` API at a glance

| Call | Purpose |
|------|---------|
| `Sort.<algo> comparator list` | sort with a comparison algorithm → new sorted List |
| `Sort.<algo> list`            | sort Integers with a distribution sort (no comparator) |
| `Sort.by-number/v`            | a comparator (pass it with `/v`): negative / zero / positive Integer |
| `(Sort.reverse comp/v)`       | a comparator that reverses `comp` (descending) |
| `(Sort.by-key keyfn/v)`       | a comparator that orders by a derived key |
| `Sort.is-sorted comparator list` | test whether a list is ordered → Boolean |

Wrap a call in parens to use its result as a value; the piping form
(`list Sort.<algo> comparator`) wants a trailing `end` at statement level.
Full details are in the [Reference](docs/reference.md).

## For AI coding agents

If an agent will call this library, point it at **[AGENTS.md](AGENTS.md)**
— the exact boru calling convention, verified idioms, and the common
mistakes to avoid.

To make that guidance available in *another* project that uses this
library, install the bundled skill either way:

- **Copy the skill** — drop
  [`.claude/skills/sort-aql/`](.claude/skills/sort-aql/SKILL.md)
  into that project's `.claude/skills/` (or your `~/.claude/skills/`). It
  loads on demand whenever `Sort` calls appear.
- **Install the plugin** — this repo is also a plugin marketplace:

  ```
  /plugin marketplace add voxgig-boru/sort
  /plugin install sort-aql@voxgig-boru
  ```

Working inside *this* repo, Claude Code picks the guidance up
automatically via `CLAUDE.md` (which imports `AGENTS.md`) and the bundled
skill.

## Project layout

```
sort.aql                  the library (the Sort namespace: comparators + algorithms)
AGENTS.md                 agent guide: how to call this library correctly
DESIGN.md                 design notes for planned work (not yet implemented)
test/sort_unit_test.aql   example-based unit tests — direct (Test.test)
test/sort_unit_spec.aql   example-based unit tests — declarative spec format
test/sort_prop_test.aql   property-based tests — direct (Test.check-prop)
test/sort_prop_spec.aql   property-based tests — declarative spec format
test/sort_smoke_test.aql  end-to-end smoke run over every public word
test/divergence/          the gate: every suite runs green (compiled) + boru check clean
bench/                    performance baseline (bench/run.sh, BASELINE.md)
docs/                     Diátaxis documentation (above)
```

Test files follow a consistent naming convention: `_test.aql` for
direct tests (unit or property), `_spec.aql` for declarative specs (unit
or property). The keystone property is **cross-agreement** — every
algorithm must return the same ordering as the stable `Sort.merge`.

## Running it

Build `boru`, then run any script or test — see
[How-to → Install and run](docs/how-to.md#install-and-run-boru) and
[Run the tests](docs/how-to.md#run-the-tests). `boru X` checks the program,
compiles it to bytecode and runs it on the VM — boru's only execution path:

```bash
boru test/sort_unit_test.aql   # unit tests — direct
boru test/sort_unit_spec.aql   # unit tests — declarative spec format
boru test/sort_prop_test.aql   # property tests — direct
boru test/sort_prop_spec.aql   # property tests — declarative spec format
boru test/sort_smoke_test.aql  # end-to-end smoke run
```

```bash
test/divergence/run.sh         # the gate: every suite + boru check on suites and module
```

A GitHub Actions workflow
([`.github/workflows/test.yml`](.github/workflows/test.yml)) builds boru from
boru-lang/boru `main` HEAD and runs every suite, the gate above, and a
`consistency` job (agent-skill drift and JSON manifests) on each push and
pull request.

## License

See [LICENSE](LICENSE).
