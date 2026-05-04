# Parser Combinator Design for MoonLift

## Problem

The grammar library answers "did it match?" (boolean). Parser combinators answer
"what did it match?" (value). Values must flow through `ok` continuations.

## Core decision: value protocol

```
ok: cont(next: i32, val: i64), fail: cont(at: i32)
```

All parser fragments share this single protocol. `i64` is the universal value
carrier. A matched byte is `as(i64, c)`. A matched span is `pos` packed as
`(start << 32) | len`. An array length is a count. The user interprets the i64.

*Why i64 and not parameterized types?*  MoonLift regions have fixed type
signatures. We cannot write a single `seq2` region that composes `ok:
cont(next:i32, val:T)` for arbitrary T without code generation.  A universal
byte container keeps the combinators static regions while still carrying values.

## Combinators

### Primitives (produce values)

| combinator        | val on success                    |
|-------------------|-----------------------------------|
| `byte_eq(v)`      | `as(i64, v)`                     |
| `range(lo, hi)`   | `as(i64, matched_byte)`          |
| `any_byte()`      | `as(i64, matched_byte)`          |

### Sequencing (compose values)

| combinator          | semantics                              |
|---------------------|----------------------------------------|
| `seq_keep_b(a, b)`  | run a, then b; return b's value        |
| `seq_keep_a(a, b)`  | run a, then b; return a's value        |
| `seq_pair(a, b)`    | run both; pack (a.val, b.val) into i64 |
| `seq_sum(a, b)`     | run both; val = a.val + b.val          |

`seq_keep_b` is the most common: a is a skipper/whitespace, b is the value
producer.

### Alternation

| combinator     | semantics                           |
|----------------|-------------------------------------|
| `alt2(a, b)`   | try a; if fails try b; forward val  |

### Repetition

| combinator        | semantics                              |
|-------------------|----------------------------------------|
| `star_count(f)`   | run zero or more; val = count          |
| `plus_count(f)`   | run one or more; val = count           |
| `opt_val(f)`      | try f; val = f.val or 0 if skipped     |

### Structural

| combinator     | semantics                                  |
|----------------|--------------------------------------------|
| `match_span(f)`| run f; val = (start << 32) \| (next-start) |
| `empty_val()`  | succeeds (nofail); val = 0                 |
| `pred(f)`      | lookahead without consuming                |
| `not_pred(f)`  | negative lookahead                         |

## seq_fold: user-defined value combining

The user defines a MoonLift block that receives two `i64` values and produces
a combined `i64`:

```moonlift
block add_vals(a_val: i64, b_val: i64)
    let sum: i64 = a_val + b_val
    jump ok(next = next, val = sum)
end
```

The combinator `seq_fold(name, a, b, fold_block_label)` generates a region
that, after both fragments succeed, jumps to the user's fold block with
`(next, a_val, b_val)`. The fold block jumps to the caller's `ok`.

This keeps value semantics fully in MoonLift and uses existing control-flow
mechanisms (blocks, jump args).

## Integration with grammar library

Two options:

### Option A: separate `lib/parser.mlua`

A new module with its own binary combinators, RegionFragValues, n-ary nesting,
and Grammar-like rule builder. Does not share types with the grammar library.

Pro: clean separation, no risk of breaking grammar library
Con: duplicated combinator infrastructure

### Option B: extend `lib/grammar.mlua`

Add value-enabled variants alongside existing combinators. Same continuation
protocol extended with `val: i64`. Rules can opt into value production via a
separate `Grammar:valued_rule(name, fn)`.

Pro: shared infrastructure, one library
Con: more complex API, risk of combinatorial explosion with nf/non-nf ×
valued/non-valued fragment combinations

**Recommendation: Option A.**  The grammar library stays simple (boolean).
Parser combinators are a separate concern. Both use the same underlying
MoonLift region/emit model but don't share fragment types.

## N-ary nesting

Same as grammar library: binary combinators at the MoonLift level, n-ary
via Lua nesting that chains binary combinators:

```lua
R.seq_keep_b({a, b, c})  -- chains: seq_keep_b(seq_keep_b(a, b), c)
```

## Rule builder

```lua
local P = parser("JSON")

P:rule("digit",  function(R) return R.range(48, 57) end)
P:rule("number", function(R) return R.rep_count(R.ref("digit")) end)
P:rule("value",  function(R) return R.alt { R.ref("string"), R.ref("number") } end)

-- Access:
P:get("number")  -- RegionFragValue with ok: cont(next: i32, val: i64)
```

## Open question: typed wrappers at the Lua level?

The MoonLift level is i64-only. At the Lua host level, we *could* wrap
RegionFragValues with type metadata (e.g., "this fragment produces an i32
count") for documentation and validation. But this is optional — the user
can work directly with i64 values and manual packing/unpacking.

## Implementation order

1. Define the value protocol (`ok: cont(next: i32, val: i64)`)
2. Write binary combinators: `seq_keep_b`, `seq_pair`, `alt2_val`, `star_count`
3. Write primitives with values: `range_val`, `byte_eq_val`, `any_byte_val`
4. Write `seq_fold` (user-defined reduction)
5. Write `match_span`, `opt_val`, `pred_val`, `not_pred_val`
6. Build the n-ary Lua layer and `Parser:rule` builder
7. Test: parse expressions into i64 values, verify end-to-end
