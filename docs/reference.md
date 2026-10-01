# Reference

Technical description of the `sort` module's public surface. This page is
information-oriented: it states what each word is, its call shape, what it
returns, and — for the algorithms — stability, complexity, and
constraints. For *why* the library is built this way, see
[Explanation](explanation.md); for goal-directed recipes, the
[How-to guides](how-to.md).

> **AI agents:** [AGENTS.md](../AGENTS.md) condenses the calling
> convention, idioms, and common mistakes for machine use.

The module exports a single namespace, `Sort`. Import it with:

```boru
import "./sort.aql"
```

A relative import path resolves against the **directory of the importing
file** (for `boru X` and `boru check X` alike), not the working directory —
a script in `test/` writes `import "../sort.aql"`. No `end` is required
after `import` (a trailing `end` is harmless). A consuming script does
**not** need to import `boru:string-util` or `boru:math-util` itself —
`sort.aql` imports them internally.

Verified against boru main @ `64c5ab2` (2026-10-01).

---

## Calling convention

A call binds its arguments **in signature order**: the tokens written
after the word fill the leading parameters, and whatever is left comes off
the stack. Every `Sort` word takes the list — the **receiver** — as its
**last** parameter, so the canonical form is **forward**, verb first and
list last; the **piping** form, list first, binds identically:

```
Sort.<algo> comparator list        →   List (new, sorted; input unchanged)
Sort.<algo> list                   →   List (distribution sorts)
list Sort.<algo> comparator end    →   the same, piping form
```

The forward form is saturated by the trailing list, so a closing paren is
all the terminator it needs. In the piping form, end the call with `end`
(or wrap it in parens) so the trailing comparator cannot collect a
following literal as its list. Receiver-first-all-forward —
`Sort.<algo> list comparator` — matches no signature; `boru check` (which
`boru X` runs first) reports
`uncalled_function: call to 'quick-sort' matched no signature`.

### Passing a comparator

A bare name that holds a function **calls** it wherever it appears (boru
ADR-011), so a comparator passed as an argument — to a sort or to a
combinator — always carries **`/v`**, which hands over the function value:

| You want to use… | Write it as |
|---|---|
| a comparator from this namespace | `Sort.by-number/v` |
| your own comparator word | `mycmp/v` |
| the built-in `cmp` | `cmp/v` |
| a comparator built by a combinator | `(Sort.reverse Sort.by-number/v)` — the parens place the value |
| a comparator bound with `def` | `desc/v` (after `def desc (Sort.reverse Sort.by-number/v)`) |

`/v` replaced the old `/r` modifier (ADR-011, renamed 2026-08-19).

### No mutation

Every algorithm returns a **new** sorted `List`; the input `List` is never
modified. This is the opposite of an in-place library. Always bind the
result (`def s (Sort.quick … xs)`); the original is unchanged.

---

## Comparators

A comparator is a two-argument function value with signature
`[b:T a:T] [Integer]`: given two items it returns a negative / zero /
positive Integer when the first sorts before / equal to / after the
second. Only the sign matters — the same contract as the built-in `cmp`.
The defaults defer to `cmp` (a three-way compare that never subtracts, so
there is no integer-overflow risk).

Pass each one to a sort as `Sort.<name>/v`. Applied directly, the stack
form reads naturally — `a b Sort.by-number end` is negative when `a`
sorts before `b` (`1 2 Sort.by-number end` is `-1`); the forward form
binds in signature order (`b` first), so `Sort.by-number 1 2` is `1`.

| Call (stack form) | Returns | Order |
|------|---------|-------|
| `a b Sort.by-number end` | `Integer` | ascending numeric (Integer or Float) |
| `a b Sort.by-string end` | `Integer` | lexicographic (code-point) |
| `a b Sort.by-boolean end` | `Integer` | `false` before `true` |
| `a b Sort.by-generic end` | `Integer` | `cmp` — within one type family; a mixed pair (`3` vs `"a"`) raises `incomparable` |
| `a b Sort.natural end` | `Integer` | alphanumeric: embedded digit runs compare numerically, so `"file2" < "file10"` |
| `a b Sort.case-insensitive end` | `Integer` | case-folded lexicographic |

### Combinators

Each returns a **new** comparator (a closure over its argument), so they
compose — e.g. `(Sort.reverse (Sort.by-key length-of/v))`. The argument
going in carries `/v`; wrap the call in parens to place the resulting
comparator.

| Call | Args | Returns | Effect |
|------|------|---------|--------|
| `(Sort.reverse comp/v)` | `comp:Comparator` | `Comparator` | reverses `comp` (descending) |
| `(Sort.by-key keyfn/v)` | `keyfn:Function` | `Comparator` | orders items by the key `keyfn` extracts, compared with `cmp` |

```boru
print (Sort.quick (Sort.reverse Sort.by-number/v) [3 1 2])     # => [3, 2, 1]
def len-of fn [[s:Any] [Integer] [ s size ]]
print (Sort.merge (Sort.by-key len-of/v) ["bbb" "a" "cc"])      # => ["a", "cc", "bbb"]
```

---

## Comparison sorts

`Sort.<algo> comparator list → List`. All produce the same ordering
for a given comparator; they differ in stability and cost. *Stable* means
equal elements keep their input order. Complexities are average-case
unless noted; `n` is the list length.

| Algorithm | Stable | Time | Space | Notes |
|-----------|--------|------|-------|-------|
| `bubble`    | yes | O(n²) | O(n) | adjacent-swap passes |
| `insertion` | yes | O(n²), O(n) on nearly-sorted | O(n) | grows a sorted prefix |
| `selection` | no  | O(n²) | O(n) | selects each minimum in turn |
| `gnome`     | yes | O(n²) | O(n) | single back-and-forth cursor |
| `cocktail`  | yes | O(n²) | O(n) | bidirectional bubble |
| `comb`      | no  | O(n²) worst, ~O(n log n) typical | O(n) | shrinking-gap bubble |
| `shell`     | no  | O(n²) worst (halving gaps) | O(n) | gapped insertion |
| `odd-even`  | yes | O(n²) | O(n) | brick / phase pairs |
| `cycle`     | no  | O(n²) | O(n) | minimal writes |
| `pancake`   | no  | O(n²) | O(n) | prefix-flip the maximum into place |
| `bitonic`   | no  | O(n log²n) | O(n) | sorting network, generalised to **any** length |
| `quick`     | no  | O(n log n), O(n²) worst | O(n) | Lomuto partition on the last element |
| `merge`     | **yes** | O(n log n) | O(n) | **the reference** other sorts are checked against |
| `heap`      | no  | O(n log n) | O(n) | binary max-heap |
| `intro`     | no  | O(n log n) **worst case** | O(n) | quicksort with a heapsort fallback |
| `tim`       | **yes** | O(n log n), O(n) on nearly-sorted | O(n) | natural-run detection + stable merge |
| `sort`      | **yes** | O(n log n) | O(n) | recommended default (currently stable merge) |

The space column is O(n) throughout because each algorithm copies the
input into a fresh working FlexList (the input is never mutated) even when
the underlying ordering is "in place" on that copy.

```boru
print (Sort.quick Sort.by-number/v [5 3 8 1])   # => [1, 3, 5, 8]
print (Sort.sort  Sort.by-number/v [5 3 8 1])   # => [1, 3, 5, 8]
```

---

## Distribution sorts

`Sort.<algo> list → List`. These take **no comparator** and order
**Integers ascending** by counting or bucketing rather than comparing.
`k` is the value range (`max − min + 1`); `d` is the number of digits in
the maximum.

| Algorithm | Time | Space | Constraint |
|-----------|------|-------|------------|
| `counting`   | O(n + k) | O(n + k) | Integers; negatives OK |
| `pigeonhole` | O(n + k) | O(n + k) | Integers; negatives OK |
| `radix-lsd`  | O(d·(n + 10)) | O(n) | **non-negative** Integers (base 10), stable |
| `radix-msd`  | O(d·(n + 10)) | O(n) | **non-negative** Integers (base 10), recursive |
| `bucket`     | O(n + k) average | O(n) | Integers (negatives OK); value-range buckets, insertion-sorted then gathered |
| `bead`       | O(n·max) | O(n·max) | **non-negative** Integers (gravity sort) |

`counting` and `pigeonhole` raise `bad_input` on a non-Integer element or
a value range over 1e8. The radix family and `bead` raise `bad_input` on a
non-Integer or a **negative** element.

```boru
print (Sort.radix-lsd [170 45 75 90 2 802])   # => [2, 45, 75, 90, 170, 802]
print (Sort.counting [5 -2 8 -1 0])           # => [-2, -1, 0, 5, 8]
```

---

## Joke / educational sorts

`Sort.<algo> comparator list → List`. Correct, but deliberately
inefficient — for demonstration, not production.

| Algorithm | Time | Notes |
|-----------|------|-------|
| `stooge` | O(n^2.71) | recursive; sorts thirds in a fixed pattern |
| `slow`   | superpolynomial | "multiply and surrender"; recursive |
| `bogo`   | unbounded (capped) | shuffle-until-sorted with a deterministic LCG and a hard cap of 300,000 shuffles; raises `bogo_giveup` past the cap (on boru main @ 64c5ab2 a 10-element input takes about two minutes to give up) — use only on tiny inputs |

```boru
print (Sort.bogo Sort.by-number/v [2 1])   # => [1, 2]
```

---

## Predicate

### `Sort.is-sorted`

Test whether a list is already ordered under a comparator.

| | |
|--|--|
| **Call**    | `Sort.is-sorted comparator list` (piping: `list Sort.is-sorted comparator end`) |
| **Args**    | `comp:Comparator`, then `lst:List` (the receiver, last) |
| **Returns** | `Boolean` — `true` iff `list` is ordered under the comparator |

```boru
print (Sort.is-sorted Sort.by-number/v [1 2 3])         # => true
print (Sort.is-sorted Sort.by-string/v ["c" "a" "b"])   # => false
```

---

## Errors at a glance

All failures raise coded errors; catch with `do […] error […]`. Bind the
result and read `e.code` / `e.message`; inside the handler, where the
Error is on the stack, read `dot code` or `get "code"` (`get` evaluates
its key, so a bare `get code` is an `undefined word`). Dispatch on
several codes with `case`.

| Code | Raised by | Situation |
|------|-----------|-----------|
| `bad_input` | the distribution sorts | a non-Integer element; a negative element to `radix-lsd`/`radix-msd`/`bead`; or a value range over 1e8 for `counting`/`pigeonhole` |
| `bogo_giveup` | `bogo` | shuffle cap exceeded without reaching sorted order |

A missing `end` after a piping-form `Sort.*` call is not a module error
but a general boru dispatch matter — the word can collect a following
literal (add `end` or parens, or use the forward form). A wrong argument
order or a bare (un-`/v`'d) comparator is caught statically: `boru check`
reports `uncalled_function: … matched no signature` and `boru X` does not
run.
