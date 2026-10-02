# How-to guides

Task-oriented recipes. Each one assumes you already know roughly how a
sort is called; if not, start with the [Tutorial](tutorial.md). For the
*why* behind any of these, follow the links into the
[Explanation](explanation.md); for exact signatures, the
[Reference](reference.md).

- [Install and run boru](#install-and-run-boru)
- [Sort by a custom comparator](#sort-by-a-custom-comparator)
- [Sort in descending order](#sort-in-descending-order)
- [Sort by a key](#sort-by-a-key)
- [Sort filenames in natural order](#sort-filenames-in-natural-order)
- [Sort strings case-insensitively](#sort-strings-case-insensitively)
- [Choose an algorithm](#choose-an-algorithm)
- [Use a distribution sort](#use-a-distribution-sort)
- [Handle errors](#handle-errors)
- [Run the tests](#run-the-tests)
- [Measure performance](#measure-performance)

---

## Install and run boru

The module is written in boru, which has no tagged release yet, so build
`boru` from source (the documented `go install …@latest` fails on the
repo's replace directives). The library tracks boru **main**; a plain
`git clone` may be blocked by an egress proxy, so fetch main HEAD (or any
commit) as a codeload tarball:

```bash
ref="$(git ls-remote https://github.com/boru-lang/boru.git main | cut -f1)"
mkdir -p /tmp/boru-source
curl -fsSL "https://codeload.github.com/boru-lang/boru/tar.gz/$ref" \
  | tar -xz -C /tmp/boru-source --strip-components=1
cd /tmp/boru-source/cmd/go
GOWORK=off GOFLAGS=-mod=mod go build \
  -ldflags "-X github.com/boru-lang/boru/cmd/go.Version=$ref" \
  -o "$HOME/.local/bin/boru" ./boru
```

(This is the recipe the SessionStart hook and `test/divergence/run.sh`
use.) Make sure `$HOME/.local/bin` is on your `PATH`, then check it:

```bash
boru -version
# => boru 64c5ab2f3aed4a1d12a4cd71f759f34eed1962c1   (the ref you built)
```

Run any script in this repo by passing its path:

```bash
boru test/sort_smoke_test.aql
```

`boru X` runs a static pre-flight check, then compiles the program to
bytecode and runs it on the VM — boru's **only** execution path since
2026-09-19. There is no interpreter fallback, and the old `--compile` /
`--force-compile` / `--no-compile` flags are retired (passing one is a
usage error). `boru check X` runs the static check on its own.

This module was last verified against boru main @ `64c5ab2` (2026-10-01).
The CI workflow, the SessionStart hook and `test/divergence/run.sh` all
resolve main HEAD at run time.

---

## Sort by a custom comparator

A comparator is a two-argument function value returning a negative / zero
/ positive Integer when the first item sorts before / equal to / after the
second. Define one with `fn` and pass it with a **`/v`** suffix so it is
handed over as a value rather than invoked on the spot (a bare name that
holds a function *calls* it):

```boru
import "./sort.aql"

def by-length fn [
  [b:Any a:Any] [Integer] [ (a size) (b size) cmp ]
]

print (Sort.merge by-length/v ["bbb" "a" "cc"])
# => ["a", "cc", "bbb"]
```

Write the body in terms of `a` (the earlier item) and `b` (the later one),
and defer to the native `cmp` rather than subtracting — `cmp` is a
three-way compare with no overflow risk. To order records by a field:

```boru
def by-second fn [
  [b:Any a:Any] [Integer] [ (a get 1) (b get 1) cmp ]
]
print (Sort.merge by-second/v [[1 30] [2 10] [3 20]])
# => [[2 10], [3 20], [1 30]]
```

(Why `/v`, and where your comparator's helpers resolve:
[Explanation → Function values and `/v`](explanation.md#function-values-and-v).)

---

## Sort in descending order

Don't write a second, reversed comparator — wrap an existing one with the
`Sort.reverse` combinator. It takes a comparator and returns a new one
that reverses its verdict:

```boru
print (Sort.quick (Sort.reverse Sort.by-number/v) [5 3 8 1 9 2])
# => [9, 8, 5, 3, 2, 1]
```

The comparator going *into* the combinator carries `/v` like any other
comparator argument; the parens then place the new comparator for the
sort. `reverse` composes with any comparator, including ones you build:

```boru
def by-length fn [[b:Any a:Any] [Integer] [ (a size) (b size) cmp ]]
print (Sort.merge (Sort.reverse by-length/v) ["bbb" "a" "cc"])
# => ["bbb", "cc", "a"]
```

---

## Sort by a key

Often you want to order items by some derived value (a field, a length, a
computed score) rather than by the items themselves. `Sort.by-key` takes a
**key function** — one argument in, the key out — and returns a comparator
that orders items by their keys (compared with the native `cmp`):

```boru
def length-of fn [[s:Any] [Integer] [ s size ]]
print (Sort.merge (Sort.by-key length-of/v) ["bbb" "a" "cc"])
# => ["a", "cc", "bbb"]
```

The key function is passed as a value, so it carries `/v`. `by-key`
composes with `reverse` for a descending key order:

```boru
print (Sort.merge (Sort.reverse (Sort.by-key length-of/v)) ["bbb" "a" "cc"])
# => ["bbb", "cc", "a"]
```

---

## Sort filenames in natural order

Plain lexicographic order puts `"file10"` before `"file2"` (digit `1`
precedes `2`). `Sort.natural` compares embedded runs of digits by their
**numeric value** instead, which is almost always what you want for
filenames, versions, and labels:

```boru
print (Sort.merge Sort.natural/v ["file10" "file2" "file1"])
# => ["file1", "file2", "file10"]
```

It handles digit runs anywhere in the string, so `"x9"` sorts before
`"x10"` too.

---

## Sort strings case-insensitively

`Sort.by-string` is case-sensitive — every uppercase letter sorts before
every lowercase one. For a case-folded order, use `Sort.case-insensitive`:

```boru
print (Sort.merge Sort.case-insensitive/v ["HELLO" "abc" "Zebra"])
# => ["abc", "HELLO", "Zebra"]
```

It lowercases both operands before comparing, so `"abc"`, `"HELLO"`, and
`"Zebra"` order as `a < h < z`.

---

## Choose an algorithm

All the comparison sorts produce the same ordering; they differ in speed,
stability, and pedigree. Reach for these in practice:

| Goal | Use |
|------|-----|
| A sensible general-purpose default | `Sort.sort` (stable merge sort) |
| Stable order (equal items keep input order) | `Sort.merge` or `Sort.tim` |
| Fast, in-place, average case | `Sort.quick` |
| Guaranteed O(n log n) worst case | `Sort.heap` or `Sort.intro` |
| Nearly-sorted input | `Sort.tim` or `Sort.insertion` |
| Integers only, want to skip comparisons | a distribution sort (below) |

The remaining comparison sorts — `bubble`, `selection`, `gnome`,
`cocktail`, `comb`, `shell`, `odd-even`, `cycle`, `pancake`, `bitonic` —
are correct and useful for study, but for production data prefer the rows
above. The joke sorts (`bogo`, `stooge`, `slow`) are deliberately
inefficient and exist for demonstration only. The full complexity and
stability table is in the [Reference](reference.md#comparison-sorts).

```boru
print (Sort.sort Sort.by-number/v [5 3 8 1 9 2])   # => [1, 2, 3, 5, 8, 9]
print (Sort.tim  Sort.by-number/v [5 3 8 1 9 2])   # => [1, 2, 3, 5, 8, 9]
```

---

## Use a distribution sort

When your data is **Integers**, the distribution sorts skip comparisons
entirely and order by counting or bucketing. They take **no comparator**
and always sort ascending:

```boru
print (Sort.radix-lsd [170 45 75 90 2 802 24 66])
# => [2, 24, 45, 66, 75, 90, 170, 802]
```

`Sort.counting`, `Sort.pigeonhole` and `Sort.bucket` also accept
**negative** Integers:

```boru
print (Sort.counting [5 -2 8 -1 0])
# => [-2, -1, 0, 5, 8]
```

`Sort.radix-lsd`, `Sort.radix-msd`, and `Sort.bead` require
**non-negative** Integers; `Sort.bucket` accepts any Integers. All raise
`bad_input` on a non-Integer element (and the radix/bead family on a
negative one) — see the next recipe. (Why these beat comparison sorts on
the right data:
[Explanation → Distribution sorts](explanation.md#why-distribution-sorts-need-no-comparator).)

---

## Handle errors

Failures raise coded errors. Wrap the call in `do … error …`. The
simplest read is to bind what `do` returns — the Error value — and use
its `code` / `message` fields:

```boru
def e (do [Sort.counting ["a" "b"]])
print (e.code)
# => bad_input
```

Inside an `error [ … ]` handler the Error value is on the stack; read a
field with `dot code` or with a **quoted** key, `get "code"` (`get`
evaluates its key, so a bare `get code` is an `undefined word: code`):

```boru
def result (do [Sort.counting ["a" "b"]] error [ dot code ])
print (result)
# => bad_input
```

The message says exactly what was wrong:

```boru
def msg (do [Sort.radix-lsd [3 -1 2]] error [ get "message" ])
print (msg)
# => Sort.radix-lsd: needs non-negative Integers (got -1)
```

The two error codes are `bad_input` (a distribution sort got a
non-Integer, a negative where it needs non-negative, or a value range
over 1e8) and `bogo_giveup` (`Sort.bogo` exceeded its shuffle cap; use it
only on tiny inputs). To dispatch on the code, use `case` on `e.code`. In
a test, assert the failure instead (`Assert.equal expected actual` in
forward form):

```boru
import "boru:test"
Assert.throws [Sort.counting ["a" "b"]]
def e2 (do [Sort.counting ["a" "b"]])
Assert.equal bad_input/q e2.code
```

(Why the module raises coded errors:
[Explanation → Raising errors](explanation.md#raising-coded-errors).)

---

## Run the tests

Five suites ship with the module. Run them with `boru`:

```bash
boru test/sort_unit_test.aql   # example-based unit tests — direct (boru:test)
boru test/sort_unit_spec.aql   # example-based unit tests — declarative spec format
boru test/sort_prop_test.aql   # property tests — direct Test.check-prop form
boru test/sort_prop_spec.aql   # property tests — declarative spec format
boru test/sort_smoke_test.aql  # end-to-end walk-through over every public word
```

The file names follow a consistent convention: `_test.aql` is a direct
suite (assertions or `Test.check-prop` calls written out in code), and
`_spec.aql` is a declarative suite (cases or properties built as data and
handed to a runner). Both the unit and property layers ship in both forms.

The two unit suites express the same example checks two ways:
`sort_unit_test.aql` asserts imperatively with `Test.test` /
`Assert.equal`, while `sort_unit_spec.aql` builds each check as a
`TestSpec` (`Test.spec` / `Test.case`) that `Test.run-spec` dispatches.

The two property suites are likewise split: `sort_prop_spec.aql` builds
each property as a declarative `PropertySpec` (`Test.prop`) and runs it
with `Test.run-property`, while `sort_prop_test.aql` calls the imperative
`Test.check-prop` driver directly, passing `runs`/`seed`/`max-shrinks`
explicitly. The properties cross-check every algorithm against the stable
`Sort.merge` reference and assert the no-mutation and is-sorted invariants.

Each assertion-bearing test file ends by asserting `Test.fail-count` is
`0` (`Assert.equal 0 (Test.fail-count)`) and printing `all green`, so a
failure makes `boru` exit non-zero — which is exactly what the CI workflow
checks on every push and pull request.

One more check sits on top of this set. `test/divergence/run.sh` is the
gate: every suite must exit 0 under `boru X` (and print `all green` where
it asserts), and `boru check` must report 0 errors on every suite and on
`sort.aql`. Run it with:

```bash
test/divergence/run.sh                        # builds its own boru at main HEAD
BORU=/path/to/boru test/divergence/run.sh     # reuse an existing build
```

It used to compare boru's interpreter against its byte compiler; with a
single execution path there is nothing left to compare, so it gates on
run + check instead. See
[`test/divergence/README.md`](../test/divergence/README.md) for details.

## Measure performance

`bench/` holds a performance baseline: `bench/sort_bench.aql` times each
representative algorithm sorting a fixed, deterministic array (execution-
only, via `boru:time-util`), and `bench/run.sh` runs each algorithm as its
own `boru` process, reporting the best-of-N milliseconds per algorithm:

```bash
BORU=/path/to/boru bench/run.sh          # default 3 reps, best-of
```

There is one column (compiled — boru's only execution path). The sizes
are deliberately small: boru threads a first-class comparator through
every element move, so the per-comparison function dispatch — not the
algorithm — dominates the wall-clock. The numbers are for ranking
algorithms and tracking them across boru versions, not for comparing
against native sorts. `BENCH_TIMEOUT=<secs>` bounds any single run so a
slow configuration is skipped rather than left to hang. A recorded
snapshot lives in [`bench/BASELINE.md`](../bench/BASELINE.md).
