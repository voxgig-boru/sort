# Developer-experience report — building the `Sort` library in boru

A field report from converting this repository into the `Sort`
sorting-algorithms library: 25 algorithms and a set of comparators,
originally built and verified against **`boru-lang/boru @ 12a44e0`**, and
since migrated to **boru main @ `64c5ab2`** (2026-10-01) — see the first
section. Snippets in the historical sections were run against `12a44e0`
and use its spellings (`/r`, `aql`, the interpreter/compiler split).

The goal of this document is to save the next person time, and to give the
`boru` maintainers a prioritized list of sharp edges. It is deliberately
balanced — [§9](#9-what-worked-well) covers what made the build *pleasant*,
which was a lot.

## Migration to boru main @ 64c5ab2 (2026-10-01)

The library had last been verified against boru `6185620` (2026-07-21),
1,587 upstream commits earlier. This section records what the migration to
**boru main @ `64c5ab2`** (2026-09-30) hit, what was worked around, and
which upstream defects stay open. Everything below was executed against
that build. **The sections after this one are the original field report
(against `12a44e0`) and are kept as history** — several of their findings
are fixed upstream (noted at the end of this section).

**Result:** `sort.aql` and all five suites check with **0 errors, 0
warnings** and every suite fully compiles and runs green on boru's single
execution path (`test/divergence/run.sh` passes). No test expectation was
changed.

### Breaking changes hit

| Change upstream | Effect here | Migration |
|---|---|---|
| **One execution path** (2026-09-19): compile to bytecode + VM, or `[boru/compile_failed]`; `--compile` / `--force-compile` / `--no-compile` and the `BORU_*COMPILE` env vars retired | the divergence harness compared interpreter vs byte compiler; `bench/run.sh` timed both | `test/divergence/run.sh` rewritten to gate on run (exit 0 + `all green`) + `boru check` (0 errors, suites **and** module); `bench/run.sh` has one column |
| **`/r` renamed `/v`** (ADR-011, 2026-08-19); `ref` → `valof` | every `comp/r` forward and every export (`by-number: by-number/r`) | `/v` throughout; `mycmp/r` is now `undefined word: mycmp/r` |
| **A bare name holding a function calls**, with no slot-typed exception (ADR-011 as amended 2026-08-17) | namespace comparators passed bare — `Sort.quick Sort.by-number xs`, `(Sort.by-number Sort.reverse)` — now *call* `by-number`: `uncalled_function: call to 'by-number' matched no signature` (baseline: `sort_smoke_test` check error; `sort_unit_test` refused with `code-body word test-test (Stage 2)`; two `sort_prop_spec` properties failed) | every comparator argument carries `/v`: `Sort.by-number/v`, `mycmp/v`, `cmp/v`. The docs' old rule "namespace comparators are already values — no `/r`" is **inverted**. (Observed leniency: a few positions still accept a bare *namespace member* on 64c5ab2 — `xs Sort.quick Sort.by-number end` and `(Sort.reverse Sort.by-number)` run — contrary to the ADR; the docs tell callers not to rely on it.) |
| **Relative imports resolve against the importing file's directory** | suites imported `"./sort.aql"` relative to the cwd | suites import `"../sort.aql"`; `bench/sort_bench.aql` likewise |
| **Receiver-first all-forward is rejected statically** | `Sort.quick [3 1 2] Sort.by-number/v` used to raise `signature_error` at run time | now `uncalled_function: call to 'quick-sort' matched no signature` from the pre-flight check; the run is blocked. Docs updated |
| **`get` evaluates its key** | docs taught `e get code` / handler `[ get code ]` | `e.code`, or `dot code` / `get "code"` in a handler |
| **`Test.check-prop` returns a PropertyResult** | a bare call left the Map on the stack | `sort_prop_test` hands each result to a `report` fn that prints `ok`/`FAIL` |
| **Postfix print chains reorder** | the suites' `"---" print "fail count: " print Test.fail-count end print` summary dropped a line, and `0 Test.fail-count end Assert.equal end` compared against a stray stack value | one forward `print (…)` per line and `Assert.equal 0 (Test.fail-count)`. `Assert.equal` is `[expected actual]` in forward form (`expected foo, got bad_input`), so `sort_unit_test` now writes `Test.test NAME [ Assert.equal expected actual ]` and failure messages read the right way round |
| **A Capitalised `def` binds a type** | `bench/sort_bench.aql`'s `def SMALL 200` made `iota SMALL` `[]`, and its all-stack `1000000 SMALL mkarr` bound `n` to a million (OOM-killed) | lowercase `n-small` / `n-large`, forward `mkarr 1000000 n-small` |
| `boru check` false positives on fn values are fixed | `check` was advisory | `check` now gates (0 errors everywhere) |
| boru has `while` | the bounded `iota` loops were written for its absence | kept (correct, compiled); comments updated |

### Workarounds applied (each commented at its site; remove when fixed upstream)

**1. A Function parameter read both bare and by `/v` in one body
(NUR123's open remainder).** The recursive helpers invoked the comparator
bare (`xi xj comp`) and forwarded it (`comp/v`). boru's compiler refuses
that body — the error names NUR123, which `design/NUR-ARCHIVE.0.md`
archives as FIXED while listing "a binding read both bare and by `/v`" as
an unimplemented case still owed a fix:

```boru
# repro-bare-and-v.boru
def go fn [[comp:Function n:Integer xs:List] [Integer] [
  def c ((xs get 0) (xs get 1) comp)
  def _r (if (n gt 0) [ (xs (n sub 1) comp/v go) ] [ 0 ])
  n
]]
print ([3 1] 2 cmp/v go)
# => error: [boru/compile_failed]: bytecode compilation FAILED: fn go: binding
#    `comp` is read both bare and by /v in one body (one value ID, two dispatch
#    semantics — NUR123) — this is a compiler defect ...
```

Worse, reached from inside an `each` body the same helper **compiles** and
silently corrupts a *later, unrelated* call's loop state — in the suites,
`Sort.heap` followed by `Sort.tim` returned the input unsorted (or raised
`undefined word: ip`). Minimal repro (unrecorded upstream; possibly
related to NUR361):

```boru
# repro-nur123-state-corruption.boru
def sd fn [
  [comp:Function n:Integer i:Integer arr:FlexList] [FlexList] [
    def c ((arr get 0) (arr get 1) comp)
    def _s (if (i lt n) [ arr n (i add 1) comp/v sd ] [ arr ])
    arr
  ]
]
def first fn [
  [comp:Function] [Integer] [
    def arr (flex [3 1 2])
    def _b (iota 1 each [ var [[t] arr 0 2 comp/v sd 0 ] ])
    0
  ]
]
def second fn [
  [n:Integer] [Integer] [
    if (n lte 1) [ 0 ] [
      def arr (flex [0 0 0])
      def cnt (flex [0])
      def _ (iota (n add 1) each [ var [[t] cnt set 0 ((cnt get 0) add 1) end drop 0 ] ])
      def _u (arr size)
      cnt get 0
    ]
  ]
]
print (cmp/v first)    # 0
print (3 second)       # expected 4 — prints 1 (4 without the line above)
```

**Workaround:** every helper that forwards `comp/v` also invokes it through
the value — `xi xj comp/v apply`, the same call — so the body reads `comp`
only by `/v`. With that one-line change the repro above prints `4`.
Sorts that never forward the comparator keep the bare `xi xj comp`.

**2. A comparator that reads an imported namespace, applied as a fn value
for a caller without that import.** `Sort.case-insensitive` called
`StringUtil.lower` directly; applied by a sort on behalf of a script that
had not imported `boru:string-util`, it raised
`undefined word: StringUtil`. Unrecorded upstream:

```boru
# repro-ns-import/m.boru
import "boru:string-util"
def low fn [[b:String a:String] [Integer] [ ((a StringUtil.lower) (b StringUtil.lower) cmp) ]]
def run fn [[comp:Function xs:List] [Integer] [
  def r ((xs get 0) (xs get 1) comp)
  r
]]
export "M" { low: low/v run: run/v }

# repro-ns-import/main.boru
import "./m.boru"
print (M.low "b" "A")              # -1 (direct call: fine)
print (M.run M.low/v ["b" "A"])    # expected 1; got: undefined word: StringUtil
```

**Workaround:** the namespace read moves into a private by-name helper
(`fold-case`), which resolves in the defining module.

**3. A `Test.prop` body reading a namespace member by `/v`.** The
property bodies of `sort_prop_spec` passed `Sort.by-number/v`; the
compiler refuses them with `code-body word test-prop (Stage 2)` (the
`Test.*` quotation-body row of `design/FULL-COMPILATION.0.md`'s S2
"code-body refusals" census). A module-level binding read by `/v`
compiles:

```boru
# repro-test-prop-ns-v/m.boru
def inc fn [[x:Integer] [Integer] [ x add 1 ]]
def app fn [[f:Function x:Integer] [Integer] [ x f ]]
export "M" { inc: inc/v app: app/v }

# repro-test-prop-ns-v/main.boru
import "boru:test"
import "./m.boru"
def p (Test.prop "p" [ 3 ] [ var [[x] ((M.app M.inc/v x) eq 4) ] ])
def r (p Test.run-property)
print (r.ok)
# => error: [boru/compile_failed]: ... code-body word test-prop (Stage 2) ...
```

**Workaround:** `sort_prop_spec` binds `def by-num (Sort.by-number/v)` at
module level and its properties pass `by-num/v`.

**3. Runtime callbacks: a bare member call in a `Test.check-prop`
generator (2026-10-02, boru-lang/boru#528).** Every suite compiled as a
program, but `boru -compile-report test/sort_prop_test.aql` listed one
runtime callback that declined its compile stamp and ran on the
interpreter: the P7 generator `[ r.int 2 99 ]` @ 187:3 — "closure
storedfn$body: unapplied fn-value in body residual (dynamic apply not
lowered)" (boru COMPILABLE-SUBSET §5). It is now `[ (r.int 2 99) ]`, the
member call grouped in parens, commented at the site. A scratch harness
ran the old and new generators through `Test.check-prop` with a property
that prints every value, for seeds 2, 7 and 13 at 25 runs each, plus a
failing property with shrinking on: the outputs, result maps included,
are byte-identical, and the original property body and its
`20 2 0` arguments are unchanged. Declines across the five suites: **1 →
0** (`sort_prop_test` 1 → 0; the others were already 0). No site was
left; the `iota (r.int …) each [ var [[i] r.int … ] ]` generators were
already stamped. `sort_prop_spec`'s `Test.prop` generators have the same
shape and never declined.

### Upstream defects that do not affect this library

- A `Test.check-prop` called **inside a fn body** whose property body
  builds an interpolated template from its bound value is refused at
  compile time, while the interpreter runs it (found in the scratch
  harness for workaround 3; confirmed on both lanes with a Go probe;
  `boru check` reports 0 errors). The suites call `Test.check-prop` at top
  level, where the same body compiles:

  ```boru
  import "boru:test"
  def run fn [[] [] [
    def res (Test.check-prop "p" [ 5 ] [ var [[k] def s `g ${k}` (s size) gt 0 ] ] 2 1 0)
    print (res "ok" get)
  ]]
  run
  # interpreter: true
  # compiled:    [boru/compile_failed]: operand of unknown provenance or not
  #              statically materialisable at test-check-prop
  ```

- The `boru:test` type-ID collision (`expected X, got X` when a library
  fn returns its own class and `boru:test` is imported first) does not
  arise: `Sort` returns plain Lists and defines no class, so the suites'
  import order (`boru:test` first) is safe.

### Historical findings below, re-checked on 64c5ab2

- §1.1–§1.2 (`/r` one-shot, the Array box): obsolete — `/r` is `/v`, and
  the comparator is threaded directly as a parameter (with the workaround
  above).
- §1.3 (recursion reached through a fn param): **fixed** — a recursive
  helper called from a comparator applied as a value resolves.
- §1.4 (free words resolve in the running module): **fixed** upstream
  (boru `7e98aeb`), except the imported-namespace corner (workaround 2).
- §1.6's cheat-sheet rows "`Sort.by-number` bare ✅" and "`Sort.by-number/r`
  🟠 don't" are **inverted**: pass `Sort.by-number/v`.
- §2.1 (`lst get i` in `each` → `None`) and §2.2 (`slice` stringifies):
  **fixed** — both return the Integers.
- §3.4 (`and`/`or` do not short-circuit): still true (by design).
- §4 (reserved words reported at run time): now reported by the
  pre-flight check (`check error: [boru/reserved_word]`).
- §6 (checker false positives; `check` advisory): **fixed** — 0 errors,
  and `check` gates.

---

## Update (DX-driven boru fixes)

A later boru build acted on some of the issues below, so the library was
migrated to match it. The accessor family was split: `get`/`getr` now
**evaluate** their key, so a bare literal field name after `get` is an
`undefined_word` error by design — literal-field reads move to the new
`.field` / `!.field` sugar (e.g. `e get code` → `e.code`), or, where the
value is on the stack with no receiver, to the quoted-atom key form
`get field/q`. The only such sites here were the two error-code reads in
`test/sort_unit_test.aql` (`e get code` → `e.code`). Separately, the
`comp/r` frame over-pop bug behind the Array-**box** comparator-threading
workaround ([§1.2](#12-the-def-cf-compr-workaround-trips-the-static-checker))
is fixed, so every divide-and-conquer sort now threads the comparator
**directly** as its `comp:Function` parameter — invoked bare (`xi xj comp`)
and forwarded with `comp/r` — and the recursive `radix-msd` `no_signature`
false positive ([§6](#6-tooling--the-static-checker-aql-check)) is gone, so
`boru check sort.aql` is now **0 errors**. (Note: the `def cf (comp/r)`
local form of [§1.2](#12-the-def-cf-compr-workaround-trips-the-static-checker)
still trips the checker's `undefined_word` false positive, so the box
collapses to the parameter itself rather than to a `cf` local.) These
changes require an boru build carrying those fixes; on the original pinned
build they will not run/check clean.

## Severity legend

- 🔴 **Silent wrong result** — code runs, returns the wrong value, no error.
- 🟠 **Hard error / forced a workaround** — fails loudly; shaped the design.
- 🟡 **Sharp edge** — surprising, but easy to live with once known.

The single biggest theme: **first-class functions are load-bearing for a
comparator-driven library, and they are the least-polished corner of the
language** ([§1](#1-first-class-functions--comparators)). The second:
**collections silently change element identity** in two different ways
([§2](#2-collections--types)).

---

## 1. First-class functions & comparators

A comparator is a two-argument function value threaded into every sort. The
whole library lives or dies on passing functions around, and this is where
most of the time went.

### 1.1 🟠 Parking a Function *parameter* with `/r` is one-shot

`word/r` defers a word as a value. On a **parameter**, the second `/r` in
the same scope fails:

```boru
def mycmp fn [[b:Integer a:Integer] [Integer] [ (a cmp b) ]]
def use1  fn [[comp:Function x:Integer y:Integer] [Integer] [ (x y comp) ]]
def two   fn [[comp:Function a:Integer b:Integer] [Integer] [
  def r1 (a b comp/r use1)
  def r2 (b a comp/r use1)   # <-- second /r on the same param
  r1 add r2
]]
print ((3 7 mycmp/r two)) end
# => error: [aql/undefined_word]: undefined word: comp
```

**Cause (observed):** parking a param appears to consume it from the scope;
a *bound local* does not have this problem. **Workaround:** bind once,
re-reference freely — `def cf (comp/r)` then `cf/r` as many times as needed.
This is the first half of the box pattern below.

### 1.2 🟠 The `def cf (comp/r)` workaround trips the static checker

The bind-once fix runs correctly but `boru check` rejects it:

```boru
def go fn [[comp:Function n:Integer] [Integer] [
  def cf (comp/r)
  def _ (iota n each [var [[i] def r (i i cf/r apply) 0]])
  5 5 cf/r apply
]]
# interpreter: runs fine
# boru check:   4 errors — "undefined_word: cf"
```

Threaded through a dozen recursive sort helpers, that was **89 check
errors** in `sort.aql`, all the same false positive.

**Workaround — the "box" pattern.** Store the comparator in a one-cell
`Array`, forward the *box* (a plain value, no `/r`), and read it back to
invoke:

```boru
def go fn [[comp:Function n:Integer] [Integer] [
  def box (make Array [comp/r])   # park once, into an Array cell
  def cf  (box get 0)             # read back the function value
  def _ (iota n each [var [[i] def r (i i cf) 0]])
  5 5 cf                           # invoke bare
]]
# interpreter: runs fine
# boru check:   0 errors
```

Both forms return the same (correct) result; only the box form is
check-clean. This is the pattern every divide-and-conquer sort uses — see
`sort.aql:306-310` (`quick-go`, `merge-go`, `heap-sort`, `bitonic`, `intro`,
`stooge`, `slow`, `tim`).

**Design impact:** the entire comparator-threading layer was rewritten from
`def cf (comp/r)` to the Array box purely to satisfy the checker.

### 1.3 🟠 A recursive helper reached *through a Function param* fails to resolve

A comparator invoked via a `Function` parameter may call **non-recursive**
helpers, but if a helper it reaches **recurses**, the self-call does not
resolve:

```boru
def dbl  fn [[n:Integer] [Integer] [ n mul 2 ]]                            # non-recursive
def deep fn [[n:Integer] [Integer] [ if (n lte 0) [0] [ (n sub 1) deep ] ]] # recursive
def hcmp fn [[b:Any a:Any] [Integer] [ def s (a dbl)  (s b cmp) ]]
def rcmp fn [[b:Any a:Any] [Integer] [ def s (a deep) (s b cmp) ]]
def run  fn [[comp:Function y:Any x:Any] [Any] [ (x y comp/r apply) ]]
print ((typeof (do [ 3 7 hcmp/r run ]))) end   # => Integer  (helper resolved)
print ((typeof (do [ 3 7 rcmp/r run ]))) end   # => Error    (deep's self-call unresolved)
```

The sort algorithms themselves recurse fine — they are dispatched by name
through the namespace, not handed in as a value. The breakage is specific to
recursion reached *via* a passed-in function.

**Design impact:** the `natural` (alphanumeric) comparator was rewritten
from a clean recursive scanner into a **bounded iterative loop** with cursor
state in single-cell Arrays (`sort.aql:110-157`), precisely so it stays
callable when a sort invokes it through the comparator parameter.

### 1.4 🟠 A function value's free words resolve in the *running* module

An exported comparator that calls a private helper works when called
directly, but **fails when a sort in a different module invokes it** — the
helper resolves in the caller's module, not the definition's. Splitting
`comparator.aql` from `sort.aql` made `Sort.natural` raise
`undefined_word: natural-go` the moment `Sort.merge` (in the other module)
drove it.

**Design impact:** comparators and algorithms **must share one module**.
The planned two-file split was abandoned for a single `sort.aql`; this is
documented in `CLAUDE.md` and the file header.

### 1.5 🟠 Combinators: one captured function survives a module hop, two do not

`reverse` (a lambda capturing one comparator) composes through a sort across
modules. A combinator capturing **two** functions where one is a
cross-module comparator fails when invoked. This is why `by-key` captures
only the key-extractor and orders the keys with the built-in `cmp`, and why
the planned `then` (chain two comparators) was **dropped**.

### 1.6 🟡 Reference/passing quirks (a cheat-sheet)

All verified:

| Form | Result |
|------|--------|
| `def f inc/r` (bare) | 🔴 doesn't bind — later `f` is `undefined word: f` |
| `def f (inc/r)` (parens) | ✅ binds the function value |
| `Sort.by-number` (namespace member, bare) | ✅ already a parked value — pass as-is |
| `Sort.by-number/r` | 🟠 double-steps / misbehaves — **don't** add `/r` to a namespace member |
| `5 5 cf` (bare, `cf` a bound function) | ✅ auto-dispatches on the two stack args |
| `5 inc/r apply` | ✅ the documented invoke form |
| `xs Sort.quick Sort.by-number wrap` | 🟡 `Sort.by-number` **auto-invokes** because a word follows it |

```boru
def f inc/r            # => later: error: [aql/undefined_word]: undefined word: f
def f (inc/r)          # => binds; 5 f/r apply  =>  6
```

The net user-facing rule (now in `AGENTS.md`): namespace comparators bare,
your own comparator word with `/r`, the built-in with `cmp/r`.

---

## 2. Collections & types

Two silent identity changes, each of which produced a wrong sort before
being tracked down.

### 2.1 🔴 `lst get i` with a bare `each` variable returns `None`

Indexing a **List** with the loop variable from `each` yields `None`;
indexing an **Array** is fine, and even `lst get (i add 0)` is fine:

```boru
def lst [10 20 30]
def _ (iota 3 each [var [[i]
  print ((`lst_get=${(lst get i)}  arr_get=${((make Array lst) get i)}`)) end 0
]])
# => lst_get=None  arr_get=10
# => lst_get=None  arr_get=20
# => lst_get=None  arr_get=30
```

The loop variable types as `Integer`, so this is genuinely surprising — only
the *List* `get` path mishandles it. **Workaround / rule:** copy the input to
`make Array` and index the array. Every sort does `def arr (make Array lst)`
first; `is-sorted` originally indexed the List directly and returned wrong
answers until switched to an array.

### 2.2 🔴 `slice` on a list of typed values stringifies the elements

```boru
print ((typeof ([3 1 2] get 0))) end             # => Integer
print ((typeof (([3 1 2] slice 0 2) get 0))) end # => ProperString
```

A sub-list of integers comes back as strings, and a later `cmp` then raises
`incomparable: cannot order ProperString and Integer`. **Workaround:** never
`slice` a value list — build sublists by index (`iota mid each [var [[i] lst get (i add off)]]`)
or, as the sorts do, operate in place on one backing Array with `(lo, hi)`
bounds. This is why no algorithm uses `slice` to divide its input.

### 2.3 🟡 `convert Array list` is unsupported; `make Array list` is the constructor

`convert` only does scalar/map conversions, so `convert Array someList`
errors. Use `make Array someList`. Both `make Array` and `convert List`
**preserve** element types (unlike `slice`).

---

## 3. Statements & control flow

### 3.1 🟡 `set` is void — never `def`-bind it

`arr set i v end` returns nothing; `def _ (arr set i v end)` is an error
("expected 1 return value"). Call it as a bare statement. (Same for any void
word.)

### 3.2 🟠 A bare non-void `if` leaks its value into the return

A bare `if cond [a] [b]` used as a *statement* (not the final expression)
leaves its value on the stack, so the function returns one value too many:

```boru
def f fn [[x:Integer] [Integer] [
  if (x gt 0) [ 99 ] [ 0 ]    # bare statement, but it yields a value
  x add 1
]]
print ((5 f)) end
# => error: [aql/type_error]: f: expected 1 return value(s), got 2
```

In `sort.aql` this was subtler: the `counting`/`pigeonhole` range-guard
`if (span gt 1e8) [ raise … ] [0]` leaked a `0` that rode along in the
returned List, surfacing as a stray `0` in the smoke output rather than a
hard error (the declared return type swallowed it). **Workaround:** bind the
guard — `def _g (if … [raise …] [0])`.

### 3.3 🟡 `each` body must yield a value

Every `each` iteration must leave exactly one value; loops that act only for
side effects push a sentinel `0`. Ubiquitous in the code.

### 3.4 🟠 `and` / `or` do not short-circuit

Both operands are always evaluated:

```boru
print ((false and (1 div 0 gt 0))) end
# => error: division by zero
```

So `and` cannot guard a risky second operand. **Workaround:** nest `if` for
bounds checks — `if (i lt n) [ … access i … ] [ … ]` rather than
`(i lt n) and (… access i …)`. This shows up in every loop that reads
`arr get (i add 1)` near a boundary.

---

## 4. Naming & reserved words 🟡

A surprising number of useful identifiers are built-in words and cannot be
used as a `def` name **or a parameter name**, and the collision is often
only reported at runtime:

```boru
def cmp fn [[b:Any a:Any] [Integer] [ 0 ]]
# => error: [aql/reserved_word]: def cmp: 'cmp' is a built-in word and cannot be redefined
```

Hit during the build: `cmp`, `reverse`, `sort`, `merge`, `inner`, `min`,
`max`, `range`, `find`, `filter`, `select`, `group`, `depth`. A parameter
named `cmp` collided (renamed to `comp`/`cmpf`); a local `range` collided
(renamed to `span`); a `depth` parameter collided (renamed to `lim`).
Namespace **export keys** are unaffected — `Sort.merge` / `Sort.reverse` are
fine as map keys; only top-level `def`/param names are reserved.

---

## 5. Numerics 🟡

Integer overflow is a **hard error at 63 bits**, not a silent wrap. A naive
comparator `a sub b` can overflow on extreme inputs, so the default
comparators use `lt`/`gt` (or the built-in `cmp`, which compares without
subtracting). The counting / pigeonhole / radix sorts range-guard before
allocating their tables. This is a *good* default — loud beats silent — just
worth designing around.

---

## 6. Tooling — the static checker (`boru check`) 🟠

`boru check` is valuable but has false positives precisely where this library
lives:

- The `def cf (comp/r)` cluster ([§1.2](#12-the-def-cf-compr-workaround-trips-the-static-checker)) — `undefined_word: cf`.
- The recursive `radix-msd` self-call — `no_signature`.

These surface even when checking a **test file**, transitively through the
imported `sort.aql`. There is no way to reach zero `check` errors without
contorting correct code, so the project treats `check` as **advisory**: the
divergence harness (`test/divergence/run.sh`) and CI (`.github/workflows/test.yml`) gate on
**interpreter == byte compiler** instead — which passed for all five suites
and all 25 algorithms. The box pattern ([§1.2](#12-the-def-cf-compr-workaround-trips-the-static-checker)) already removed the largest
cluster; what remains is a handful of genuine false positives.

There is also a **test-framework** limitation worth recording:
`Test.run-spec` (the declarative spec runner) cannot dispatch a subject word
that takes a **Function** argument — i.e. the comparison sorts. Comparators
*as* subjects (`a b Sort.natural`) and the no-comparator distribution sorts
dispatch fine, so the declarative unit-spec (`test/sort_unit_spec.aql`)
covers those, and the comparison sorts are covered imperatively
(`test/sort_unit_test.aql`) and by the property-spec
(`test/sort_prop_spec.aql`), whose bodies are arbitrary code.

---

## 7. Build / environment 🟠

`git clone` of the boru source is blocked by the egress proxy; the GitHub
**codeload tarball** is not:

```
$ git clone https://github.com/boru-lang/boru …
fatal: unable to access '…': The requested URL returned error: 403

$ curl -fsSL -o /dev/null -w "%{http_code}" \
    https://codeload.github.com/boru-lang/boru/tar.gz/12a44e0…
200
```

Both the SessionStart hook (`.claude/hooks/session-start.sh`) and the
divergence harness fetch via `codeload.github.com/.../tar.gz/<ref>` so a
fresh remote session can build `boru` without a clone.

---

## 8. How these shaped the library (summary)

| Issue | Design consequence |
|-------|--------------------|
| §1.2 checker rejects `def cf (comp/r)` | Array-**box** comparator threading everywhere |
| §1.3 recursion-via-param fails | `natural` is **iterative**, not recursive |
| §1.4 free words resolve in running module | **single-file** `sort.aql` (no `comparator.aql`) |
| §1.5 two-capture combinator fails | `by-key` uses built-in `cmp`; `then` **dropped** |
| §2.1 / §2.2 List `get`/`slice` corruption | sorts copy to `make Array` and work on **index bounds** |
| §6 checker false positives | `boru check` is **advisory**; gate on interpreter == compiler |
| §7 clone blocked | hook + harness fetch via **codeload tarball** |

---

## 9. What worked well

It would be unfair to list only the rough edges. These made the build
genuinely pleasant:

- **Named-word recursion** is solid — quicksort, mergesort, heapsort,
  bitonic, stooge, slow, and recursive MSD radix all recurse by name with no
  trouble (the [§1.3](#13-a-recursive-helper-reached-through-a-function-param-fails-to-resolve) caveat is *only* about recursion reached through a
  passed-in value).
- **The built-in `cmp`** is a polymorphic three-way comparator
  (`3 cmp 7 => -1`, `"a" cmp "b" => -1`) — every default comparator is a
  one-liner over it.
- **Lambdas / closures** via `[params] => [body]` capture their enclosing
  scope cleanly — `reverse` is a four-token combinator.
- **`iota` / `each` / `fold`** are an ergonomic iteration trio; with
  single-cell Arrays for mutable state they express every bounded loop the
  language's lack of `while` would otherwise make awkward.
- **`make Array` / `convert List`** round-trip values with full type
  fidelity (the contrast that makes [§2.2](#22-slice-on-a-list-of-typed-values-stringifies-the-elements) so surprising).
- **Interpreter ↔ byte-compiler agreement held throughout.** Every suite,
  including the keystone cross-agreement property (each algorithm must equal
  the stable `Sort.merge`, 100 runs × 15 algorithms), produced byte-identical
  output under `boru X` and `boru --compile X`. For a library whose correctness
  *is* "all 25 algorithms agree", that guarantee was the bedrock the whole
  test strategy rests on.

---

## 10. Suggested upstream fixes (prioritized)

1. **Teach `boru check` about `def x (param/r)` and recursive self-calls.**
   This single fix removes every false positive this library hit and would
   let `check` return to gating ([§1.2](#12-the-def-cf-compr-workaround-trips-the-static-checker), [§6](#6-tooling--the-static-checker-aql-check)).
2. **Make List `get` with an `each` variable, and `slice` on a value List,
   either type-preserving or a loud error** — never a silent `None` /
   stringification ([§2.1](#21-lst-get-i-with-a-bare-each-variable-returns-none), [§2.2](#22-slice-on-a-list-of-typed-values-stringifies-the-elements)). These are the only 🔴s here.
3. **Lift the one-shot restriction on parking a Function parameter with
   `/r`** ([§1.1](#11-parking-a-function-parameter-with-r-is-one-shot)) — it forces the bind-once dance and, with #1, the box.
4. **Resolve a function value's free words (incl. recursion) in its
   *defining* module**, so library authors can split files ([§1.3](#13-a-recursive-helper-reached-through-a-function-param-fails-to-resolve), [§1.4](#14-a-function-values-free-words-resolve-in-the-running-module)).
5. **Report reserved-word collisions at parse/check time**, not at runtime
   ([§4](#4-naming--reserved-words-)).
6. **Let `Test.run-spec` dispatch subjects that take a Function argument**
   ([§6](#6-tooling--the-static-checker-aql-check)), so declarative specs can cover higher-order words.

*Report generated while building `Sort` against `boru @ 12a44e0`. Every
snippet was executed against that build; outputs are reproduced verbatim.*
