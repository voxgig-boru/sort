# Explanation

Understanding-oriented discussion of how this sorting library works and
why it is built the way it is. Read this when you want the *why*; for the
*what*, see the [Reference](reference.md), and for *how to get a job
done*, the [How-to guides](how-to.md).

---

## What the library is for

It is a catalogue of sorting algorithms — every well-known comparison
sort, the main distribution sorts, and a few joke sorts — over every boru
type, driven by a single small abstraction: the **comparator**. You pick
an algorithm and an ordering, write them in boru's forward shape — the
list, the call's receiver, last — and get back a new sorted list:

```
Sort.<algo> comparator list   →   a new sorted List
```

The design goal is that the *ordering* and the *algorithm* are
independent. Any comparator works with any comparison algorithm, and you
swap one without touching the other. The rest of this page explains why
that boundary is a comparator, why the sorts hand back new lists instead
of mutating in place, and the boru idioms that make both work.

---

## Why the design is comparator-driven

A sort has to answer exactly one question about your data, over and over:
*given two items, which comes first?* Everything else — how items are
moved, how many passes are made, the recursion structure — belongs to the
algorithm and is the same whatever you are sorting. So the library factors
that one question out into a value you supply: the comparator.

The payoff is a small surface that covers a large space. There is no
`sort-numbers`, `sort-strings-descending`, `sort-by-length` family of
words; there is one `Sort.quick` (and `Sort.merge`, `Sort.heap`, …) that
takes whatever ordering you hand it. Orderings compose, too: `Sort.reverse`
turns any comparator into its descending counterpart, and `Sort.by-key`
turns a "how do I extract the sort key" function into a full comparator.
You build the order you need from small pieces rather than reaching for a
bespoke algorithm.

This is the same separation C's `qsort` makes with its comparison
callback, Python's `key=`/`cmp` parameters, and the JS `Array.sort`
comparator — a well-worn boundary. What is particular to boru is *how* a
comparator is represented and passed, which the next sections cover.

### What a comparator is

A comparator is a two-argument function value. Given two items it returns
an **Integer** whose **sign** is the answer: negative if the first item
sorts before the second, zero if they are equivalent, positive if after.
Only the sign matters — magnitude is ignored — so the contract is exactly
that of the built-in `cmp`.

```boru
def by-length fn [
  [b:Any a:Any] [Integer] [ (a size) (b size) cmp ]
]
```

Two conventions are worth internalising. First, the body is written in
terms of `a` (the *earlier* item) and `b` (the *later* one), so "`a`
before `b` ⇒ negative" reads naturally; boru's binding rule — with every
operand on the stack, the first signature parameter takes the top of the
stack — is what makes `a` the earlier item when a sort invokes
`xi xj comp`. Second, the built-in comparators
defer to `cmp` rather than computing `a - b`. A three-way `cmp` never
subtracts, so there is no risk of integer overflow flipping a comparison —
a classic bug in hand-rolled numeric comparators.

---

## Why sorts return new lists

Every algorithm copies its input into a fresh working FlexList, sorts the
copy, and returns it as a new List. The input list is never touched. This
is the opposite of a traditional in-place sort, and it is a deliberate
choice:

- **Values stay values.** A function that quietly rewrites its argument is
  a source of action-at-a-distance bugs. Returning a new list keeps a sort
  a pure mapping from input to output — easy to reason about, safe to call
  on a list someone else still holds.
- **It matches how the library is tested.** Every algorithm is
  cross-checked against the stable `Sort.merge` reference and asserted not
  to mutate its input. A non-mutation contract is only meaningful if it
  holds uniformly, so all sorts honour it.
- **The cost is bounded and predictable.** The copy is O(n) space, which
  the algorithms would often need for scratch buffers anyway (merge sort's
  merge buffer, the distribution sorts' count arrays).

The practical consequence for callers is the one rule from the
[Tutorial](tutorial.md#step-5--sorts-return-a-new-list): always **bind the
result** (`def sorted (Sort.quick … xs)`). Reading the original
variable after "sorting" it gives you the original, unsorted list, because
nothing wrote to it.

---

## Why distribution sorts need no comparator

The distribution sorts — `counting`, `pigeonhole`, `radix-lsd`,
`radix-msd`, `bucket`, `bead` — do not take a comparator at all. They do
not compare items against each other; they use each item's **value** as an
index, scattering items into counts or buckets and reading them back in
order. That is how they break the O(n log n) comparison-sort lower bound:
they exploit knowledge a comparator deliberately hides, namely that the
keys are integers in a known range.

The flip side is that this only works for integers (and, for radix and
bead, non-negative ones), so these words validate their input and raise
`bad_input` rather than silently misbehaving. The comparator-driven sorts
and the distribution sorts are thus two answers to two different
situations — arbitrary orderings of arbitrary data versus integer keys —
and the library ships both.

---

## The boru idioms it rests on

The comparator abstraction is clean in principle, but making it work in
boru leans on a few language facts worth understanding.

### Forward calls, receiver last

boru is not C/Python/JS: there is no `sort(list, cmp)` and no
`list.sort(cmp)`. A call binds its arguments **in signature order** — the
tokens written after the word fill the leading parameters, and whatever is
left comes off the stack. Every `Sort` word takes the list, its
*receiver*, as the **last** parameter, so the canonical call is verb
first, list last:

```boru
Sort.quick Sort.by-number/v [3 1 2]
```

Because the receiver is last, the piping form — the list flowing in from
the left, `[3 1 2] Sort.quick Sort.by-number/v end` — binds the same
parameters. What does *not* work is the receiver first in an all-forward
call (`Sort.quick [3 1 2] Sort.by-number/v`): the list lands in the
comparator slot, no signature matches, and boru's pre-flight check rejects
the program before it runs. The `(… )` parentheses terminate a call, which
is why `(Sort.quick Sort.by-number/v xs)` is the usual way to use a sort's
result as a value.

### Function values and `/v`

A comparator has to be passed *as a value* — handed to the sort to call
later — not invoked at the call site. boru's rule (ADR-011) is that a
bare name holding a function **calls** it, wherever it appears; the `/v`
suffix suppresses the call and yields the function value instead. So
**every** comparator argument carries it: the namespace comparators
(`Sort.by-number/v`), your own words (`mycmp/v`) and the built-in
(`cmp/v`) alike. The combinators follow the same rule on the way in —
`(Sort.reverse Sort.by-number/v)` — and their result is placed by the
parentheses. (Older builds spelled the modifier `/r` and treated a
namespace member as an already-parked value that went bare; boru renamed
`/r` to `/v` on 2026-08-19 and dropped the bare-member exception.)

### One module, still

Comparators and algorithms live in one file, `sort.aql`. The original
reason was that boru resolved a function value's free words in **the
module that ran it**, so a comparator calling a private helper (the
`natural` digit-run scanner, say) failed when a sort in another module
invoked it. boru fixed that (a function value now resolves its free words
in the module that *defined* it), but one corner still breaks: a
comparator that reads an **imported namespace** directly
(`StringUtil.lower`) raises `undefined word: StringUtil` when it is
applied as a function value on behalf of a caller that did not import
`boru:string-util` itself. `Sort.case-insensitive` therefore routes that
read through a private helper (`fold-case`), and the library stays one
file. For your own comparators: define the comparator and its helpers in
the script that runs the sort, and they resolve.

### Threading comparators through recursion

The divide-and-conquer sorts (`quick`, `merge`, `heap`, `intro`,
`bitonic`, `tim`, and the recursive joke sorts) recurse, and each
recursive call needs the comparator. It is threaded directly as a
`comp:Function` parameter and forwarded to the recursive calls as
`comp/v`. A helper that forwards `comp/v` also *invokes* it through the
value — `xi xj comp/v apply`, the same call as a bare `xi xj comp` —
because boru main's compiler refuses (or, reached from inside an `each`
body, mis-compiles) a body that reads one Function parameter both bare and
by `/v`. Sorts that never forward the comparator invoke it bare. The
workaround is commented at each site and recorded in `DX-REPORT.md`.

### Bounded loops

When the library was written boru had no `while`, so the data-dependent
loops (gnome's cursor walk, comb's gap shrink, bogo's shuffle, …) are
bounded `iota` loops with an explicit state cell, where the bound is a
proven worst-case step count for that algorithm. The loop always reaches
the sorted state and then idles for the remaining iterations. boru has
since grown `while [cond] [body]`; the bounded loops are kept because they
are correct, compile, and make every algorithm's worst case explicit. It
is also why `bogo` has a hard cap and raises `bogo_giveup` rather than
looping forever.

---

## Design choices specific to this library

### `Sort.merge` as the reference

Merge sort is the stable, predictable O(n log n) implementation, and the
test suite treats it as ground truth: every other algorithm is checked to
produce the same ordering as `Sort.merge` on the same input. `Sort.sort`,
the recommended default, is currently merge sort for exactly this reason —
it is the one whose correctness the rest of the library is measured
against.

### Stability where it is claimed

`merge`, `tim`, and the simple adjacent-swap sorts (`insertion`, `bubble`,
`cocktail`, `gnome`, `odd-even`) preserve the input order of equal
elements; the [Reference](reference.md#comparison-sorts) marks which.
Stability matters when you sort by one key and want ties broken by a
previous ordering — sort by the secondary key first with a stable sort,
then by the primary. The default `Sort.sort` is stable so this composition
just works.

### Raising coded errors

The distribution sorts validate their input and `bogo` enforces its cap by
`raise`-ing coded errors: `bad_input` for a non-Integer / negative /
out-of-range element, `bogo_giveup` for an exhausted shuffle budget.
Handlers catch them with `do […] error […]` and read `code` / `message`
off the Error value (`e.code` once bound; `dot code` or `get "code"`
inside the handler). Coded errors let a caller distinguish "you gave me the
wrong kind of data" from a bug, and dispatch on the code with `case`.

---

## Further reading

- [Tutorial](tutorial.md) — sort your first list step by step.
- [How-to guides](how-to.md) — task-focused recipes.
- [Reference](reference.md) — every algorithm and comparator, exactly.
