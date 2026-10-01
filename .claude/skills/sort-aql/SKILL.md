---
name: sort-aql
description: Use when writing or editing boru code that calls the Sort sorting library — Sort.quick / Sort.merge / Sort.heap / Sort.tim / Sort.counting / Sort.radix-lsd and the other algorithms, the comparators Sort.by-number / Sort.by-string / Sort.natural / Sort.case-insensitive / Sort.reverse / Sort.by-key, or any file that does `import "./sort.aql"`. Provides the exact boru calling convention (which is not C/Python/JS), the comparator-driven API, verified copy-paste idioms, and fixes for the mistakes agents most often make (foreign call syntax like `xs.sort(cmp)`, misbinding the argument order — the list is the LAST argument — forgetting `/v` on a comparator argument, the retired `/r` spelling, assuming sorts mutate in place).
---

# Calling the Sort library (boru)

Every well-known sorting algorithm, over every boru type, driven by
composable **comparators**. Public surface = the `Sort` namespace. Sorts
return a **new** sorted `List` and never mutate their input. Everything
below is verified against **boru main @ `64c5ab2`** (2026-10-01).

## Import

```boru
import "./sort.aql"
```

- A relative path resolves against the **directory of the file that
  contains the `import`** (for `boru X` and `boru check X` alike), not the
  working directory. A script in `test/` writes `import "../sort.aql"`.
- No `end` is needed after `import`.
- Do **not** import `boru:string-util` / `boru:math-util` — the library
  does it.

## The one calling rule

boru has no `f(a, b)` and no `obj.method(a)`. Every `Sort` word takes the
list (the **receiver**) as its **last** parameter, so two orders bind
correctly:

```
Sort.verb comparator list      # forward (canonical): args first, receiver LAST
list Sort.verb comparator      # piping: the receiver flows in from the left
```

Both produce the same result. Prefer the **forward** form — the receiver
saturates the call, so the closing paren is all the terminator it needs.
The **piping** form wants `end` (or parens) so the trailing comparator
cannot collect a following literal.

```boru
Sort.quick Sort.by-number/v [3 1 2]       # => [1, 2, 3]    ✓ forward (canonical)
[3 1 2] Sort.quick Sort.by-number/v end   # => [1, 2, 3]    ✓ piping
Sort.counting [5 2 8 1]                    # => [1, 2, 5, 8] (no comparator)
```

The **one** order that MISBINDS is receiver-first-all-forward —
`Sort.verb list comparator`. boru rejects it before the run:
`boru check` (which `boru X` runs first) reports
`uncalled_function: call to 'quick-sort' matched no signature`.

```boru
Sort.quick [3 1 2] Sort.by-number/v       # ✗ WRONG — rejected; do not write this
```

### Passing a comparator — always `/v`

A bare name that holds a function **calls** it wherever it appears. A
comparator handed to a sort or a combinator must be passed as a value,
with **`/v`** — every kind alike:

- a namespace comparator → `Sort.by-number/v`
- your own comparator word → `mycmp/v`
- the built-in `cmp` → `cmp/v`
- a comparator built by a combinator and bound with `def` →
  `def desc (Sort.reverse Sort.by-number/v)`, then `Sort.quick desc/v xs`

(`/v` replaced the old `/r` modifier; `mycmp/r` is now an `undefined word`.)
A comparator is a two-argument function returning a negative / zero /
positive `Integer` (first sorts before / equal to / after the second) —
the same contract as `cmp`.

## API

### Comparison sorts — `Sort.<algo> comparator list → List`
`bubble`, `insertion`, `selection`, `gnome`, `cocktail`, `comb`, `shell`,
`odd-even`, `cycle`, `pancake`, `bitonic`, `quick`, `merge` (stable, the
reference), `heap`, `intro`, `tim` (stable), and `sort` (default = stable
merge).

### Distribution sorts — `Sort.<algo> list → List` (Integers, ascending, NO comparator)
`counting`, `pigeonhole`, `bucket` (negatives OK), `radix-lsd`,
`radix-msd`, `bead` (**non-negative** only). Bad elements raise
`bad_input`.

### Joke sorts — `Sort.<algo> comparator list → List`
`stooge`, `slow`, and `bogo` (raises `bogo_giveup` past its cap — tiny
inputs only).

### Comparators & combinators
`Sort.by-number`, `Sort.by-string`, `Sort.by-boolean`, `Sort.by-generic`,
`Sort.natural` (alphanumeric: `"file2" < "file10"`),
`Sort.case-insensitive`. Combinators return a new comparator:
`(Sort.reverse comp/v)` (descending) and `(Sort.by-key keyfn/v)` (order by
a derived key). Predicate: `Sort.is-sorted comparator list → Boolean`.

Catch errors with `do […] error […]`: bind the result and read `e.code`,
or read `dot code` / `get "code"` inside the handler (`get` evaluates its
key, so a bare `get code` is an `undefined word`).

## Idioms (verified)

Canonical **forward** form — `Sort.verb  args  receiver` (receiver last):

```boru
import "./sort.aql"
print (Sort.quick Sort.by-number/v [5 3 8 1])                  # => [1, 3, 5, 8]
print (Sort.merge Sort.by-string/v ["pear" "Apple" "fig"])     # => ["Apple", "fig", "pear"]
print (Sort.quick (Sort.reverse Sort.by-number/v) [5 3 8 1])   # => [8, 5, 3, 1]
```

The **piping** form (receiver first) is equally valid:

```boru
print ([5 3 8 1] Sort.quick Sort.by-number/v end)              # => [1, 3, 5, 8]
```

Natural / alphanumeric order (numbers compare by value, not digit):

```boru
print (Sort.merge Sort.natural/v ["file10" "file2" "file1"])   # => ["file1", "file2", "file10"]
```

Custom comparator (2-arg) and sort-by-key (a 1-arg **key function**):

```boru
def by-len fn [[b:Any a:Any] [Integer] [ (a size) (b size) cmp ]]   # 2-arg comparator
print (Sort.merge by-len/v ["bbb" "a" "cc"])                        # => ["a", "cc", "bbb"]

def len-of fn [[s:Any] [Integer] [ s size ]]                        # 1-arg key function
print (Sort.merge (Sort.by-key len-of/v) ["bbb" "a" "cc"])          # => ["a", "cc", "bbb"]
print (Sort.merge (Sort.reverse (Sort.by-key len-of/v)) ["bbb" "a" "cc"])  # => ["bbb", "cc", "a"]
```

Trap a distribution sort's input error:

```boru
def e (do [Sort.counting ["a" "b"]])
print (e.code)                                                  # => bad_input
```

## Common mistakes

| ✗ Don't | ✓ Do | Why |
|---------|------|-----|
| `Sort.quick([3 1 2], cmp)` / `[3 1 2].sort(cmp)` | `Sort.quick cmp/v [3 1 2]` | boru has no call/method syntax. |
| `Sort.quick nums Sort.by-number/v` (receiver between verb and comparator) | `Sort.quick Sort.by-number/v nums` (receiver LAST) | Receiver-first-all-forward matches no signature; `boru check` reports `uncalled_function` and the run is blocked. |
| `Sort.quick Sort.by-number nums` / `(Sort.by-number Sort.reverse)` | `Sort.by-number/v` | A bare name holding a function **calls** it (`uncalled_function: call to 'by-number' matched no signature`). Every comparator argument carries `/v` — namespace members included. (A few positions still tolerate a bare namespace member on 64c5ab2; don't rely on it.) |
| `Sort.quick mycmp nums` / `Sort.quick cmp nums` | `mycmp/v`, `cmp/v` | Same rule for your own words and the built-in. |
| `Sort.by-number/r`, `mycmp/r` | `/v` | `/r` was renamed `/v` (ADR-011); `mycmp/r` is now an `undefined word`. |
| `xs Sort.quick Sort.by-number/v` followed by a literal on the same statement | add `end`, or use forward `Sort.quick Sort.by-number/v xs` | In piping the call can collect a following literal as its list. |
| sort `xs`, then read `xs` as sorted | `def s (Sort.quick … xs)` | Sorts return a **new** List; the input is unchanged. |
| `Sort.radix-lsd [3 -1 2]` | `Sort.counting`, or non-negative input | radix/bead need non-negative Integers (`bad_input`). |
| `Sort.counting ["a" "b"]` | `Sort.merge Sort.by-string/v ["a" "b"]` | distribution sorts are Integer-only. |
| `e get code` / handler `[ get code ]` | `e.code`, or `dot code` / `get "code"` in a handler | `get` evaluates its key; a bare name there is an `undefined word`. |
| `"label" print (v) print` | `print (v)`, one per statement | `print` collects forward; chains print out of order. |

## Result semantics

- **Sorts return a NEW List** — they never mutate the input. Bind the
  result (`def s (Sort.quick Sort.by-number/v xs)`). Lists are immutable;
  for in-place work use a mutable `FlexList` (`flex`).
- **`eq` is identity, `deq` is structural.** `[1 2 3] eq [1 2 3]` is
  `false` (distinct objects); use `deq` when asserting a sorted List
  equals an expected List by value.
- **Integer overflow fails loud.** boru Integers are fixed-width; arithmetic
  that overflows raises `integer_overflow` rather than wrapping — this is
  intended. The default comparators use `cmp`, which never subtracts, so
  ordering itself is overflow-safe; watch overflow only in your own
  key/arithmetic (`add`, `mul`, …).
- **`Sort.by-generic` orders within one family** (it is `cmp`):
  `Sort.merge Sort.by-generic/v [3 "a"]` raises `incomparable`.

If the full repo is available, `AGENTS.md`, `api.json` (machine-readable
signatures), and `docs/reference.md` have the complete guide;
`test/sort_smoke_test.aql` is a runnable example.
