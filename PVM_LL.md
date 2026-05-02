# PVM-LL

PVM-LL is the low-level PVM style for Moonlift.  It is **not** a Lua builder DSL
and it is **not** an ASDL phase-body language.

You write ordinary `.mlua`:

- Lua for metaprogramming.
- Moonlift `region` for phase boundaries.
- `emit` to compose compiler passes.
- `switch` for dispatch.
- `jump` for continuations.
- `func` only at external ABI boundaries.

`moonlift.pvm_ll` only provides small reusable MLUA templates for common phase
boundary patterns such as scalar cache wrappers and stream sinks.

## Scalar phase

```lua
local pvmll = require("moonlift.pvm_ll")

local classify_uncached = region classify_uncached(ctx: ptr(u8), subject: i32;
    value: cont(v: i32))
entry start()
    switch subject do
    case 0 then
        jump value(v = 11)
    case 1 then
        jump value(v = 22)
    default then
        jump value(v = 99)
    end
end
end

local classify = pvmll.one {
    name = "classify",
    uncached = classify_uncached,
    ctx_ty = pvmll.ptr(pvmll.u8),
    subject_ty = pvmll.i32,
    value_ty = pvmll.i32,
}
```

Use it from another region with ordinary `emit`:

```moonlift
emit @{classify}(ctx, subject; value = got_class)
```

The wrapper is just a region that delegates to `classify_uncached` and forwards
through a real continuation block.  No triplets, no Lua runtime callbacks.

## Export shell

Functions are only shells.  Internal compiler composition should stay region-to-region.

```moonlift
export func classify_export(ctx: ptr(u8), subject: i32) -> i32
    return region -> i32
    entry start()
        emit @{classify}(ctx, subject; value = done)
    end
    block done(v: i32)
        yield v
    end
    end
end
```

## Cached scalar phase

`pvmll.cached_one` wraps an uncached one-result region.

Conventions:

```text
lookup(ctx, subject) -> Hit { valid: bool, value: Value }
insert(ctx, subject, value) -> void
```

```lua
local lower_expr = pvmll.cached_one {
    name = "lower_expr",
    uncached = lower_expr_uncached,
    ctx_ty = Ctx,
    subject_ty = ExprId,
    value_ty = ValueId,
    hit_ty = LowerExprHit,
    lookup = "lower_expr_lookup",
    insert = "lower_expr_insert",
}
```

The generated region is the usual PVM boundary:

```text
lookup
  hit  -> jump value(hit.value)
  miss -> emit uncached; insert; jump value(v)
```

## Stream phases and sinks

Streams are sink-based.  A stream phase has a `done` continuation.  Values are
emitted through a sink region with a `resume` continuation.

```lua
local sink = pvmll.append_sink {
    name = "append_fact",
    ctx_ty = Ctx,
    value_ty = FactId,
    append = "append_fact_to_ctx", -- append(ctx, value) -> i32 status
}

local cmd_facts = region cmd_facts(ctx: Ctx, cmd: CmdId;
    done: cont())
entry start()
    switch tag_cmd(ctx, cmd) do
    case 0 then
        let fact: FactId = make_fact(ctx, cmd)
        emit @{sink}(ctx, fact; resume = done)
    default then
        jump done()
    end
end
end
```

This is the PVM-LL stream model:

```text
produce value -> emit sink(value; resume = next block)
```

No triplet generator exists.

## Stream cache shape

`pvmll.cached_stream_span` implements the low-level equivalent of a cached PVM
stream.  The cache stores a span of previously emitted values.

Conventions:

```text
lookup(ctx, subject) -> Hit { valid: bool, start: index, len: index }
value_at(ctx, absolute_index) -> Value
begin(ctx, subject) -> Record
commit(ctx, subject, record) -> void
uncached_recording(ctx, subject, record; done(record))
```

The wrapper does:

```text
hit:
  replay cached span through the sink
miss:
  begin record
  emit uncached_recording
  commit record
  done
```

## Metaprogramming

Use Lua to generate normal regions.  Region names can use numeric staged ids:

```lua
local function make_classifier(zero_value, one_value, default_value)
    local id = pvmll.gensym_id()
    return region classify_@{id}(ctx: ptr(u8), subject: i32;
        value: cont(v: i32))
    entry start()
        switch subject do
        case 0 then jump value(v = @{zero_value})
        case 1 then jump value(v = @{one_value})
        default then jump value(v = @{default_value})
        end
    end
    end
end
```

That is the intended public style: MLUA regions plus Lua staging.  `pvm_ll.mlua`
only removes repetitive boundary/cache/sink boilerplate.

## API reference

- `pvmll.one { name, uncached, ctx_ty, subject_ty, value_ty, fail_ty? }`
- `pvmll.cached_one { name, uncached, ctx_ty, subject_ty, value_ty, hit_ty, lookup, insert, fail_ty? }`
- `pvmll.optional { name, uncached, ctx_ty, subject_ty, value_ty, fail_ty? }`
- `pvmll.append_sink { name, ctx_ty, value_ty, append }` where `append(ctx, value) -> i32`
- `pvmll.recording_sink { name, sink, ctx_ty, record_ty, value_ty, append_record }` where `append_record(ctx, rec, value) -> i32`
- `pvmll.cached_stream_span { name, uncached_recording, sink, ctx_ty, subject_ty, value_ty, hit_ty, record_ty, lookup, value_at, begin, commit, fail_ty? }`
- `pvmll.gensym_id()` for Lua-generated region-name suffixes.
