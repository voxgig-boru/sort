# AGENTS.md — using the `Sort` library

Guidance for an AI coding agent calling this sorting library from a boru
project. Every code block below was executed against `boru-lang/boru`
**main @ `64c5ab2`** (2026-10-01). If you read nothing else, read
[The one calling rule](#the-one-calling-rule) and
[Common mistakes](#common-mistakes).

> **Calling convention — forward args, receiver (list) last:**
> `Sort.<algo> comparator list`. Piping `list Sort.<algo> comparator` also
> works; only `Sort.<algo> list comparator` misbinds (`boru check` rejects
> it). **Every comparator argument carries `/v`** —
> `Sort.quick Sort.by-number/v xs`, `Sort.merge mycmp/v xs`,
> `Sort.heap cmp/v xs`.

## What it is

Every well-known sorting algorithm, over every boru type, driven by
composable **comparators**. The public surface is the single `Sort`
namespace. Sorts return a **new** sorted `List` and never mutate their
input.

- **Comparison sorts** (take a comparator): `bubble`, `insertion`,
  `selection`, `gnome`, `cocktail`, `comb`, `shell`, `odd-even`, `cycle`,
  `pancake`, `bitonic`, `quick`, `merge`, `heap`, `intro`, `tim`, and the
  default `sort`.
- **Distribution sorts** (no comparator; Integers ascending): `counting`,
  `pigeonhole`, `radix-lsd`, `radix-msd`, `bucket`, `bead`.
- **Joke / educational sorts** (take a comparator): `bogo`, `stooge`,
  `slow`.
- **Comparators**: `by-number`, `by-string`, `by-boolean`, `by-generic`,
  `natural` (alphanumeric), `case-insensitive`, plus the combinators
  `reverse` and `by-key`.
- **Predicate**: `is-sorted`.

boru main has **one execution path**: `boru file` runs a static pre-flight
check, then compiles the program to bytecode and runs it on the VM. There
is no interpreter fallback, and `--compile` / `--force-compile` /
`--no-compile` are retired (passing one is a usage error). A check error,
or a `[boru/compile_failed] … this is a compiler defect`, blocks the run.

## Import

```boru
import "./sort.aql"
```

- A relative path resolves against the **directory of the file that
  contains the `import`** (for `boru X` and `boru check X` alike), not the
  working directory. A script next to `sort.aql` writes
  `import "./sort.aql"`; one in `test/` writes `import "../sort.aql"`.
- No `end` is needed after `import`; a trailing `end` is harmless.
- Do **not** import `boru:string-util` or `boru:math-util` yourself —
  `sort.aql` imports its own dependencies.

## The one calling rule

boru is not C/Python/JS. There is no `f(a, b)` and no `obj.method(a)`.
A call binds its arguments **in signature order**: the tokens written
after the word fill the leading parameters, and whatever is left comes
off the stack. Every `Sort` word takes the list (the **receiver**) as its
**last** parameter, so two orders bind correctly:

```
Sort.verb comparator list      # forward (canonical): args first, receiver LAST
list Sort.verb comparator      # piping: the receiver flows in from the left
```

Both produce the same result. The **forward** form is *saturated* by the
trailing list, so it needs no `end` (the closing paren terminates it). In
the **piping** form, end the call with `end` (or wrap it in parens) so the
trailing comparator cannot collect a following literal as its list.

```boru
print (Sort.quick Sort.by-number/v [3 1 2])        # => [1, 2, 3]    forward (canonical)
print ([3 1 2] Sort.quick Sort.by-number/v end)    # => [1, 2, 3]    piping
print (Sort.counting [5 2 8 1])                    # => [1, 2, 5, 8] (no comparator)
```

The **one** order that MISBINDS is receiver-first-all-forward —
`Sort.verb list comparator`. boru rejects it before the run: `boru check`
(which `boru X` runs first) reports
`uncalled_function: call to 'quick-sort' matched no signature`.

```boru
Sort.quick [3 1 2] Sort.by-number/v               # ✗ WRONG — rejected; do not write this
```

### Passing a comparator — always `/v`

A bare name that holds a function **calls** it wherever it appears
(boru ADR-011). A comparator handed to a sort — or to a combinator — must
be passed *as a value*, which is what the `/v` modifier does:

| You want to use… | Write it as |
|---|---|
| a comparator from this namespace | `Sort.by-number/v` |
| your own comparator word | `mycmp/v` |
| the built-in `cmp` | `cmp/v` |
| a combinator's result | `(Sort.reverse Sort.by-number/v)` — the parens place the new comparator |
| a comparator bound with `def` | `def desc (Sort.reverse Sort.by-number/v)`, then `desc/v` |

`/v` replaced the old `/r` modifier (renamed 2026-08-19); `mycmp/r` is now
an `undefined word`.

```boru
def by-len fn [[b:Any a:Any] [Integer] [ (a size) (b size) cmp ]]
print (Sort.merge by-len/v ["bbb" "a" "cc"])       # => ["a", "cc", "bbb"]
print (Sort.heap cmp/v [3 1 2])                    # => [1, 2, 3]
```

## A comparator's contract

A comparator is a two-argument function value. Given two items it returns
an **Integer**: negative if the first sorts before the second, zero if
they are equivalent, positive if after. Only the sign matters — the same
contract as the built-in `cmp` and as C's `qsort`. Write the body in terms
of `a` (the earlier item) and `b` (the later one); with the signature
`[b:T a:T]`, a sort's all-stack call `xi xj comp` binds `xi` to `a`:

```boru
def by-second fn [
  [b:Any a:Any] [Integer] [ (a get 1) (b get 1) cmp ]   # order pairs by their 2nd element
]
print (Sort.merge by-second/v [[1 30] [2 10] [3 20]])  # => [[2 10], [3 20], [1 30]]
```

Calling a comparator directly is rarely needed; if you do, the stack form
reads naturally — `1 2 Sort.by-number end` is `-1` (1 before 2). The
forward form binds in signature order (`b` first), so
`Sort.by-number 1 2` is `1`.

## API reference (exact call shapes)

Shapes are written in the canonical forward form; the piping form
`list Sort.<algo> comparator end` binds identically.

### Comparison sorts — `Sort.<algo> comparator list → List`

| Algorithm | Notes |
|-----------|-------|
| `merge` | **Stable**; the reference the others are checked against. |
| `tim` | **Stable**; natural-run detection + merge. |
| `insertion`, `bubble`, `cocktail`, `gnome` | Stable, simple, O(n²). |
| `selection`, `comb`, `shell`, `odd-even`, `cycle`, `pancake` | In-place family, O(n²)/sub-quadratic. |
| `quick` | Lomuto partition, O(n log n) average. |
| `heap` | O(n log n), in-place heap. |
| `intro` | Quicksort with a heapsort fallback (O(n log n) worst case). |
| `bitonic` | Sorting network, generalised to **any** length. |
| `sort` | The recommended default (currently stable merge sort). |

### Distribution sorts — `Sort.<algo> list → List` (Integers, ascending, no comparator)

| Algorithm | Constraint |
|-----------|------------|
| `counting`, `pigeonhole` | Integers (negatives OK); raise `bad_input` on non-Integers or a value range > 1e8. |
| `radix-lsd`, `radix-msd` | **Non-negative** Integers (base 10). |
| `bucket` | Integers (negatives OK). |
| `bead` | **Non-negative** Integers. |

### Joke sorts — `Sort.<algo> comparator list → List`

`stooge`, `slow` (recursive, very slow), and `bogo` (shuffle-until-sorted;
raises `bogo_giveup` past its cap — use only on tiny inputs).

### Comparators & combinators

| Call | Returns | Notes |
|------|---------|-------|
| `Sort.by-number/v` | comparator | ascending numeric (Integer/Float) |
| `Sort.by-string/v` | comparator | lexicographic (code point) |
| `Sort.by-boolean/v` | comparator | `false` before `true` |
| `Sort.by-generic/v` | comparator | `cmp` — within one type family; mixed families raise `incomparable` |
| `Sort.natural/v` | comparator | alphanumeric: `"file2" < "file10"` |
| `Sort.case-insensitive/v` | comparator | case-folded strings |
| `(Sort.reverse comp/v)` | comparator | reverses `comp` (descending) |
| `(Sort.by-key keyfn/v)` | comparator | order by `keyfn`'s key (compared with `cmp`) |

The combinators compose: `(Sort.reverse (Sort.by-key keyfn/v))`.

### Predicate

`Sort.is-sorted comparator list → Boolean`.

### Errors

Failures raise coded errors; catch with `do […] error […]`. Bind the
result and read `e.code` / `e.message`, or — inside the handler, where
the Error is on the stack — `dot code` or `get "code"` (`get` evaluates
its key, so a bare `get code` is an `undefined word`). Codes: `bad_input`
(a distribution sort got a non-Integer, a negative where it needs
non-negative, or a value range over 1e8) and `bogo_giveup`.

## Copy-paste idioms (all verified)

Sort numbers, strings, and a custom order:

```boru
import "./sort.aql"
print (Sort.quick Sort.by-number/v [5 3 8 1])                  # => [1, 3, 5, 8]
print (Sort.merge Sort.by-string/v ["pear" "Apple" "fig"])     # => ["Apple", "fig", "pear"]
print (Sort.quick (Sort.reverse Sort.by-number/v) [5 3 8 1])   # => [8, 5, 3, 1]
```

Natural / alphanumeric ordering (the headline utility — numbers that
appear as prefixes or suffixes sort by value, not by digit):

```boru
print (Sort.merge Sort.natural/v ["file10" "file2" "file1"])   # => ["file1", "file2", "file10"]
```

Sort by a derived key (here, string length), ascending and descending:

```boru
def len-of fn [[s:Any] [Integer] [ s size ]]
print (Sort.merge (Sort.by-key len-of/v) ["bbb" "a" "cc"])                  # => ["a", "cc", "bbb"]
print (Sort.merge (Sort.reverse (Sort.by-key len-of/v)) ["bbb" "a" "cc"])   # => ["bbb", "cc", "a"]
```

Distribution sort over Integers (no comparator):

```boru
print (Sort.radix-lsd [170 45 75 90 2 802 24 66])              # => [2, 24, 45, 66, 75, 90, 170, 802]
```

Check an ordering, and trap a distribution sort's input error:

```boru
print (Sort.is-sorted Sort.by-number/v [1 2 3])                # => true
def e (do [Sort.counting ["a" "b"]])
print (e.code)                                                 # => bad_input
def code (do [Sort.counting ["a" "b"]] error [ dot code ])
print (code)                                                   # => bad_input
```

## Common mistakes

| ✗ Don't write | ✓ Write | Why |
|---------------|---------|-----|
| `Sort.quick([3 1 2], cmp)` | `Sort.quick cmp/v [3 1 2]` | No `f(a,b)` syntax in boru. |
| `[3 1 2].sort(cmp)` | `Sort.quick cmp/v [3 1 2]` | No method-call syntax. |
| `Sort.quick nums Sort.by-number/v` (receiver between verb and comparator) | `Sort.quick Sort.by-number/v nums` (receiver LAST) | Receiver-first-all-forward matches no signature: `boru check` reports `uncalled_function: call to 'quick-sort' matched no signature` and the run is blocked. |
| `Sort.quick Sort.by-number nums` / `(Sort.by-number Sort.reverse)` | `Sort.by-number/v` | A bare name holding a function **calls** it — `uncalled_function: call to 'by-number' matched no signature`. Namespace comparators need `/v` like any other. (A few positions still tolerate the bare member on 64c5ab2; don't rely on it.) |
| `Sort.quick mycmp nums` / `Sort.quick cmp nums` | `mycmp/v`, `cmp/v` | Same rule for your own words and the built-in. |
| `mycmp/r`, `Sort.by-number/r` | `/v` | `/r` was renamed `/v` (ADR-011); `mycmp/r` is an `undefined word`. |
| `xs Sort.quick Sort.by-number/v` with more tokens after it | `xs Sort.quick Sort.by-number/v end`, or forward `Sort.quick Sort.by-number/v xs` | In the piping form the call can collect a following literal as its list. |
| treat a sort as in-place (sort `xs`, then read `xs`) | bind the result: `def s (Sort.quick … xs)` | Sorts return a **new** List; the input is unchanged. |
| `Sort.radix-lsd [3 -1 2]` | use `Sort.counting`, or non-negative input | radix/bead need non-negative Integers (else `bad_input`). |
| `Sort.counting ["a" "b"]` | `Sort.merge Sort.by-string/v ["a" "b"]` | Distribution sorts are Integer-only. |
| `Sort.bogo cmp/v` on a big list | only tiny lists, or use `Sort.quick` | bogosort raises `bogo_giveup` past its cap. |
| `e get code` / handler `[ get code ]` | `e.code`, or `dot code` / `get "code"` in a handler | `get` evaluates its key; a bare name there is an `undefined word`. |
| `import "./sort.aql"` from a file in a subdirectory | `import "../sort.aql"` | Relative imports resolve against the importing file's directory. |

A note on `print` while debugging: `print` collects a forward argument,
so write `print (value)` — verb first, one value per statement — and
output appears in source order. Postfix chains (`"a" print` on one line,
`"b" print` on the next) print out of order.

## Where to look next

- `docs/reference.md` — full per-word reference, stability, complexity.
- `api.json` — the same API as a machine-readable manifest.
- `docs/how-to.md` — task recipes (custom orders, natural sort, by-key).
- `docs/tutorial.md` — a hands-on first sort.
- `docs/explanation.md` — why the comparator-driven design, and the boru
  idioms it rests on.
- `test/sort_smoke_test.aql` — a complete, runnable worked example.
- `DX-REPORT.md` — boru-runtime notes, including the migration to boru
  main @ `64c5ab2` and its open upstream defects.
