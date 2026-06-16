# Region `call` Architecture

## Status

Design plan for adding `call` as the sealed-function counterpart to region `emit`.

This document captures the intended final architecture, not a phased slice.

## Core idea

Moonlift regions are the primary control abstraction. A region declares a control protocol through named continuation exits:

```moonlift
region scan(p: ptr(u8), n: index, target: u8;
            hit(pos: index),
            miss())
entry loop(i: index = 0)
    if i >= n then jump miss() end
    if p[i] == target then jump hit(pos = i) end
    jump loop(i = i + 1)
end
end
```

The language should support two use-site modes for the same region protocol:

```moonlift
emit scan(p, n, target; hit = found, miss = done)
call scan(p, n, target; hit = found, miss = done)
```

Meaning:

```text
emit = inline CFG splice
call = generated function boundary + packed protocol result + local dispatch
```

`emit` remains the default Moonlift style. `call` is the explicit escape hatch for code size, sharing, ABI boundaries, and situations where inlining a large region everywhere is undesirable.

The important invariant is:

```text
Same region protocol. Different cost boundary.
```

## User-facing semantics

### `emit`

```moonlift
emit parse_digit(p; ok = got_digit, fail = bad)
```

means:

```text
splice the region CFG here; region exits jump directly to local continuation blocks
```

### `call`

```moonlift
call parse_digit(p; ok = got_digit, fail = bad)
```

means:

```text
execute a generated callable form of the region, pack its exit protocol into a result value,
then immediately dispatch that result back to the named local continuation blocks
```

Source users do not manually write the wrapper function or result union. The region protocol remains the only source of truth.

Rule of thumb:

```text
default to emit
use call when you want a boundary
```

## Conceptual lowering

Source:

```moonlift
call scan(p, n, target; hit = found, miss = done)
```

lowers conceptually to:

```moonlift
let __r = __moon_region_call_scan(p, n, target)

switch __r
case hit(pos)
    jump found(pos = pos)
case miss()
    jump done()
default
    trap
end
```

and a generated wrapper:

```moonlift
func __moon_region_call_scan(p: ptr(u8), n: index, target: u8): __moon_region_call_scan_result
    return region: __moon_region_call_scan_result
    entry start()
        emit scan(p, n, target; hit = __ret_hit, miss = __ret_miss)
    end

    block __ret_hit(pos: index)
        return __moon_region_call_scan_result.hit(pos)
    end

    block __ret_miss()
        return __moon_region_call_scan_result.miss()
    end
    end
end
```

The generated wrapper always uses `emit`, never `call`, so lowering cannot recursively generate itself.

## Generated protocol result type

A callable region needs a real result protocol type. This must be ordinary Tree/ASDL, not hidden side state.

For a region protocol:

```moonlift
hit(pos: index)
miss()
```

generate a real tagged-union-shaped type equivalent to:

```moonlift
union __moon_region_call_scan_result
    hit(pos: index)
  | miss()
end
```

If the existing tagged union representation requires payload structs for multi-field variants, generate real payload structs as needed:

```moonlift
struct __moon_region_call_scan_hit_payload
    pos: index
end

union __moon_region_call_scan_result
    hit(__moon_region_call_scan_hit_payload)
  | miss()
end
```

The exact representation should reuse existing language-level struct/union/variant machinery. No new backend variant protocol should be introduced for this feature.

## Compiler placement

`call region` is a frontend/open/RNF lowering feature.

Safe implementation areas:

- `lua/moonlift/schema/tree.asdl`
- `lua/moonlift/parse.lua`
- `lua/moonlift/open_expand.lua`
- `lua/moonlift/region_normal_form.lua`
- host/builder APIs that construct region uses
- tests/docs/LSP keyword support

Avoid backend and semantic-lowering areas:

- `lua/moonlift/schema/code.asdl`
- `lua/moonlift/code_type.lua`
- `lua/moonlift/code_validate.lua`
- `lua/moonlift/code_to_back.lua`
- `lua/moonlift/lower_to_back.lua`
- `lua/moonlift/frontend_pipeline.lua` unless only adding frontend boundary checks
- `lua/moonlift/schema/{flow,mem,kernel,lower}.asdl`
- `lua/moonlift/code_{flow,mem,kernel,lower}_*.lua`
- `lua/moonlift/kernel_validate.lua`

Backend contract:

```text
By the time Tree reaches Code/backend lowering, no region-call semantics remain.
The backend sees only ordinary funcs, structs/unions, calls, switches, jumps, and traps.
```

This was coordinated with `agent-T321D3@moonlift-95231d` for workflow `wf-440a7835`; their backend work expects exactly this boundary.

## Tree representation

Add a region-use mode:

```asdl
RegionUseMode = RegionUseEmit
              | RegionUseCall
```

Then extend region-fragment use statements:

```asdl
StmtUseRegionFrag(
    MoonTree.StmtHeader h,
    MoonTree.RegionUseMode mode,
    string use_id,
    MoonOpen.RegionFragRef frag,
    MoonTree.Expr* args,
    MoonOpen.SlotBinding* fills,
    MoonOpen.ContBinding* cont_fills
) unique
```

All existing `emit` sites construct `RegionUseEmit`.

The parser constructs `RegionUseCall` for source `call`.

## Parser contract

`call` mirrors `emit` exactly:

```moonlift
call region_name(args; exit1 = label1, exit2 = label2)
```

It uses the same argument parsing and continuation-fill parsing as `emit`.

No separate syntax for result union, wrapper function, or dispatch is exposed.

## Expansion/RNF contract

Expansion/RNF owns the distinction:

- `RegionUseEmit` lowers by existing region-normal-form CFG import/splice.
- `RegionUseCall` lowers to generated ordinary Tree items/statements:
  - generated result type(s)
  - generated wrapper function
  - call-site local result binding
  - variant switch dispatch to continuation targets

After this lowering, no `RegionUseCall` may remain.

Open validation should report any unexpanded `RegionUseCall` as a compiler phase-boundary failure or explicit validation issue.

## Wrapper reuse

Generated wrappers should be reused per closed region instantiation and protocol shape.

Repeated source:

```moonlift
call scan(a; hit = h1, miss = m1)
call scan(b; hit = h2, miss = m2)
```

should generate one wrapper:

```text
__moon_region_call_scan
```

and two call-site dispatches.

The reuse key should be based on the resolved closed region fragment identity and its continuation protocol after open expansion. It must not depend on the local continuation targets at each call site.

Generated names must be deterministic and collision-resistant. Use a reserved prefix such as:

```text
__moon_region_call_<region>_result
__moon_region_call_<region>_fn
__moon_region_call_<region>_<cont>_payload
```

If necessary, include a stable specialization suffix for open/generic instantiations.

## Durability/sealing rule

`call` seals a control protocol into a data protocol. Therefore every continuation payload must be durable data.

Allowed:

```moonlift
ok(value: i32)
err(code: i32)
hit(pos: index)
miss()
found(handle: Voice)
```

Rejected:

```moonlift
ok(p: lease(store) ptr(T))
ok(v: lease(store) view(T))
```

because `call` would pack a temporary lease into a returned union, making temporary access durable.

Diagnostic shape:

```text
cannot call region `borrow`: continuation `ok` carries lease payload `lease(store) ptr(T)`
use `emit` so the temporary access stays in control flow
```

This check must happen before Code/backend lowering, structurally on Tree/RNF types.

Summary:

```text
emit may carry temporary control facts
call may only carry data-sealable protocol payloads
```

This aligns with the handle/store/lease model:

- handles are durable identity and can be packed
- leases are temporary access and cannot be packed

## Control-flow rule

`call region(...)` is terminating, just like `emit region(...)`.

There is no fallthrough after:

```moonlift
call parse(...; ok = good, err = bad)
```

The lowered switch arms must all terminate by jumping to the mapped continuation targets. The default arm should trap/unreachable because all generated protocol variants are known.

## Interaction with existing regions

Regions stay primary.

A single region definition can serve both composition styles:

```moonlift
emit big_algorithm(...; done = local_done, fail = local_fail)
call big_algorithm(...; done = local_done, fail = local_fail)
```

Changing `emit` to `call` at one use site should not require changing the region definition or writing wrapper boilerplate.

This gives local code-size control:

```text
emit = specialize/inline here
call = share/seal here
```

## Diagnostics and LSP

Diagnostics should make the mode distinction clear:

- unknown called region
- missing/extra continuation fill
- continuation payload cannot be sealed because it contains lease
- region call remained after expansion phase boundary

LSP/editor support:

- `call` keyword completion
- syntax recognition alongside `emit`
- hover/docs wording: `call` seals a region through a generated function boundary

## Tests

Required tests:

1. Parser accepts:

   ```moonlift
   call scan(p; hit = found, miss = done)
   ```

2. Existing `emit` parse/expansion behavior is unchanged.

3. Expansion removes all `RegionUseCall` before Code/backend lowering.

4. Generated result type exists for a called region.

5. Generated wrapper function exists and internally uses `emit`, not `call`.

6. Repeated calls to the same closed region reuse one wrapper.

7. Runtime/backend smoke through ordinary existing pipeline:

   - `call` dispatches `hit`
   - `call` dispatches `miss`
   - multi-parameter continuation payload packs/unpacks correctly

8. `call` is terminating; no fallthrough after dispatch.

9. Lease payload rejection:

   ```moonlift
   region borrow(...; ok(p: lease(store) ptr(T)), err()) ... end
   call borrow(...; ok = use, err = fail)
   ```

   must fail with a clear diagnostic telling the user to use `emit`.

10. LSP completion includes `call`.

## Non-goals

- No backend-specific region-call instruction.
- No new Code ASDL node for region call.
- No new C ABI concept for region protocols.
- No hidden callback model.
- No implicit exception/result convention.
- No anonymous semantic side-table as the source of truth.

## Final invariant

```text
Regions remain primary.
emit chooses inline control composition.
call chooses sealed function composition.
The region protocol is identical in both cases.
The cost boundary is explicit at the use site.
```
