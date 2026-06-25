# Backend JIT value/block numbering bugs 
Investigate and fix the Cranelift JIT backend bugs: value rebound, unknown block, block dup. These occur in complex multi-block control flow (switch, regions) and block compilation output through the JIT pathway.
**Started**: 2026-05-19 00:02:49
---

## Scout Output — 2026-05-19 00:04:40

Now I have a thorough picture. Here is the complete raw-facts report:

---

## Files Retrieved

1. **`src/decode.rs`** (full, 303 lines) — Rust Cranelift IR decoder
2. **`src/wire_tags.rs`** (full, ~200 lines) — Wire format tag definitions
3. **`lua/lalin/back_command_binary.lua`** (full, ~520 lines) — Lua-side binary wire encoder
4. **`lua/lalin/tree_control_to_back.lua`** (full, ~370 lines) — Control flow lowering (switch, regions, blocks)
5. **`lua/lalin/tree_to_back.lua`** (full, 2558 lines) — Main expr/stmt lowering
6. **`lua/lalin/back_validate.lua`** (full, ~430 lines) — Pre-JIT validation

Also read: `src/lib.rs`, `src/ffi.rs`, `lua/lalin/back_jit.lua`, and 3 test files.

---

## Key Code

### 1. `decode.rs` — Rust Cranelift IR decoder

#### `BodyCtx` structure (lines 168-195)
```rust
struct BodyCtx<'a> {
    builder: FunctionBuilder<'a>,
    values: HashMap<u32, Value>,
    blocks: HashMap<u32, Block>,
    stack_slots: HashMap<u32, StackSlot>,
}
```

#### `bind()` — registers a value (line 177-179)
```rust
fn bind(&mut self, id: u32, v: Value) -> Result<(), LalinError> {
    if self.values.insert(id, v).is_some() {
        return Err(LalinError(format!("value {id} rebound")));
    }
    Ok(())
}
```
**Error path**: If `id` already exists in `values`, produces `"value N rebound"`.

#### `val()` — looks up a value (line 181-183)
```rust
fn val(&self, id: u32) -> Result<Value, LalinError> {
    self.values.get(&id).copied()
        .ok_or_else(|| LalinError(format!("unknown value {id}")))
}
```
**Error path**: If `id` not in `values`, produces `"unknown value N"`.

#### `blk()` — looks up a block (line 185-187)
```rust
fn blk(&self, id: u32) -> Result<Block, LalinError> {
    self.blocks.get(&id).copied()
        .ok_or_else(|| LalinError(format!("unknown block {id}")))
}
```
**Error path**: If id not in `blocks`, produces `"unknown block N"`.

#### `slot()` — looks up a stack slot (line 189-191)
```rust
fn slot(&self, id: u32) -> Result<StackSlot, LalinError> {
    self.stack_slots.get(&id).copied()
        .ok_or_else(|| LalinError(format!("unknown slot {id}")))
}
```
**Error path**: If id not in `stack_slots`, produces `"unknown slot N"`.

#### `finalize()` (line 193-196)
```rust
fn finalize(mut self) {
    self.builder.seal_all_blocks();
    self.builder.finalize();
}
```

#### `CreateBlock` decoding (lines 249-251)
```rust
t if t == WireTag::CreateBlock as u32 => {
    let b = ctx.builder.create_block();
    if ctx.blocks.insert(s[0], b).is_some() {
        return Err(LalinError(format!("block {} dup", s[0])));
    }
}
```
**Error path**: If block id already in `blocks`, produces `"block N dup"`.

#### `AppendBlockParam` decoding (lines 255-260)
```rust
t if t == WireTag::AppendBlockParam as u32 => {
    let b = ctx.blk(s[0])?;
    let ty = st(s[1], ptr_ty)?;
    let v = ctx.builder.append_block_param(b, ty);
    ctx.bind(s[2], v)?;
}
```
Calls `ctx.blk()` (can produce "unknown block N") and `ctx.bind()` (can produce "value N rebound"). **Note**: `s[2]` is the value_id — the pair `(s[2], v)` goes into `values` HashMap. The `bind` check ensures each value id is bound only once.

#### Variable-length control flow decoding (lines 390-440):
- **Jump**: `s[0]=dest_block, s[1]=n_args, then reads args`. Calls `ctx.blk(dest)?`, then for each arg `ctx.val(id)?`.
- **Brif**: `s[0]=cond, s[1]=then_block, read_n_args(then_args), read_else_block, read_n_args(else_args)`. All blocks looked up via `ctx.blk()`, all args via `ctx.val()`.
- **SwitchInt**: `s[0]=value, s[2]=n_cases, read default_block, then for each case read lo, hi, dest_block`. All blocks via `ctx.blk()`.
- **CallDirect/CallExtern/CallIndirect**: All args read via `ctx.val()`.

**IMPORTANT**: No decoder-level dedup checking for block params on `AppendBlockParam`. The `bind()` call on `s[2]` is the only guard against duplicate value IDs. If two different `AppendBlockParam` commands use the same `s[2]` value_id, the second will produce "value N rebound". But each block param is an independent value. There's no Cranelift-level check against adding duplicate block params.

#### `decode_module` (lines 296-324): The top-level orchestrator
```rust
pub fn decode_module<M: Module>(buf: &[u8], module: &mut M) -> Result<DecodeResult, LalinError> {
    let mut pos = 0;
    let hdr = read_header(buf, &mut pos)?;
    let decl_end = hdr.decl_offset + hdr.decl_len;
    let state = read_declarations(buf, &mut pos, decl_end, module)?;
    let bodies = read_body_table(buf, &hdr)?;
    let ptr_ty = module.target_config().pointer_type();
    let mut fctx = FunctionBuilderContext::new();

    for (wire_fid, body_off, body_len) in &bodies {
        // ...
        let mut ctx = module.make_context();
        ctx.func.name = UserFuncName::user(0, cfid.as_u32());
        ctx.func.signature = sig.clone();
        let refs = precompute_refs(&mut ctx.func, module, &state);
        {
            let mut bctx = BodyCtx::new(&mut ctx.func, &mut fctx);
            decode_body(bb, ptr_ty, &mut bctx, &refs)?;
            bctx.finalize();
        }
        module.define_function(cfid, &mut ctx)
            .map_err(|e| LalinError(format!("define func {wire_fid}: {e:?}")))?;
        module.clear_context(&mut ctx);
    }
    // ...
}
```
**Note**: `fctx` is reused across all function bodies! `FunctionBuilderContext::new()` is called once and shared for all functions.

---

### 2. `wire_tags.rs` — Wire tag definitions

Defines `WireTag` enum (values 1-191) and `TAG_SLOTS[256]` static array. Key structural tags:

| Tag | Value | Slot count | Slots |
|-----|-------|------------|-------|
| CreateBlock | 1 | 1 | `[block_id]` |
| SwitchToBlock | 2 | 1 | `[block_id]` |
| AppendBlockParam | 3 | 3 | `[block_id, scalar_type, value_id]` |
| CreateStackSlot | 4 | 3 | `[slot_id, size, align_log2]` |
| Jump | 170 | 2+var | `[dest_block, n_args] + args` |
| Brif | 171 | 2+var | `[cond, then_block] + then_args + else_block + else_args` |
| SwitchInt | 172 | 3+var | `[value, scalar_type, n_cases] + cases + default_block` |
| Alias | 190 | 2 | `[dst, src]` |

---

### 3. `back_command_binary.lua` — Binary encoder

#### `renumber()` function (line 113-123)
```lua
local function renumber(bodies)
    for _, b in ipairs(bodies) do
        local nid = 0
        local map = {}
        b.map = map
        b.nid = function(self, x)
            if type(x) == "number" then return x end
            local s = type(x) == "string" and x or x.text
            if map[s] == nil then map[s] = nid; nid = nid + 1 end
            return map[s]
        end
    end
end
```
Each body gets its **own** counter starting at 0. Text IDs are mapped to dense u32s per function body. If the same text string appears twice, `map[s]` is non-nil and returns the existing numeric ID — **no dup detection**, the second occurrence returns the first's ID silently.

#### `fresh_id()` inside `encode_body` (line 142-145)
```lua
local function fresh_id()
    local s = "__a" .. tostring(addr_counter)
    addr_counter = addr_counter + 1
    return s
end
```
Generates unique synthetic IDs for address computation intermediates. These IDs are then passed through `b:nid()` for dense renumbering. Since `fresh_id()` generates new strings each time, they'll get unique numeric IDs from `renumber()`.

#### `CmdBindEntryParams` handling (line 159-168)
```lua
if k == "CmdBindEntryParams" and b.sig then
    for idx, p in ipairs(b.sig.params) do
        local val = cmd.values[idx]
        w4(buf, T.AppendBlockParam)
        w4(buf, b:nid(cmd.block))
        w4(buf, st(p))
        w4(buf, b:nid(val))
    end
end
```
**These emitted `AppendBlockParam` commands use the *value_id* from `cmd.values`** — these become the `s[2]` slot that the Rust decoder passes to `ctx.bind()`. These values may also be used as block params in the same scope.

#### `CmdSealBlock` — silently skipped (line 159)
```lua
elseif k == "CmdSealBlock" or k == "CmdBindEntryParams" then
```
CmdSealBlock is handled as a no-op in the encoder. The Rust decoder doesn't have a SealedBlock tag either (no such WireTag). Block sealing happens through `BodyCtx::finalize()` at the end.

---

### 4. `tree_control_to_back.lua` — Control flow lowering

#### Block ID generation functions (lines 60-73):
```lua
local function block_id(nonce, region_id, label)
    return Back.BackBlockId("ctl:" .. tostring(nonce) .. ":" .. region_id .. ":" .. label.name)
end
local function synthetic_block_id(nonce, region_id, suffix)
    return Back.BackBlockId("ctl:" .. tostring(nonce) .. ":" .. region_id .. ":" .. suffix)
end
```

#### Value ID generation functions (lines 56-58):
```lua
local function value_id(nonce, region_id, label, name)
    return Back.BackValId("ctl:" .. tostring(nonce) .. ":" .. region_id .. ":" .. label.name .. ":" .. name)
end
local function synthetic_value_id(nonce, region_id, suffix)
    return Back.BackValId("ctl:" .. tostring(nonce) .. ":" .. region_id .. ":" .. suffix)
end
```

#### The `nonce` comes from `env_next_block` (line 357):
```lua
local nonce_env, nonce_id = base.env_next_block(env, "ctl.region")
local nonce = nonce_id.text
```
The nonce is the text of a `BackBlockId` created by `env_next_block`. Since `env_next_block` is threaded through the lowering and incremented monotonically, each region gets a unique nonce.

#### `declare_blocks` (lines 178-188):
```lua
local function declare_blocks(cmds, records, exit_block, exit_value, exit_scalar)
    for i = 1, #records do
        cmds[#cmds + 1] = Back.CmdCreateBlock(records[i].block)
        for j = 1, #records[i].params do
            cmds[#cmds + 1] = Back.CmdAppendBlockParam(records[i].block, records[i].params[j].value, shape_scalar(records[i].params[j].scalar))
        end
    end
    cmds[#cmds + 1] = Back.CmdCreateBlock(exit_block)
    if exit_value ~= nil then
        cmds[#cmds + 1] = Back.CmdAppendBlockParam(exit_block, exit_value, shape_scalar(exit_scalar))
    end
end
```
Each block param's `value` is a `BackBackValId` created by `value_id(...)` — unique to (nonce, region_id, label, param_name). These are the **text IDs that get renumbered** in the binary encoder.

#### `lower_region` (lines 345-389):
- Calls `base.env_next_block(env, "ctl.region")` to get a nonce
- Creates `records` with block IDs and param specs
- `lower_entry_jump` emits a Jump from the implicit entry to the entry block
- Then iterates all records, calling `lower_body` for each block's body
- Uses `env_with_counters(current, body_env)` to merge counters between blocks

#### Switch arm lowering (`lower_joining_arms`, lines 201-250):
- Creates arm blocks, default block, join block via `base.env_next_block`
- Each arm's body is lowered with `base.env_with_counters(env, env_current)`
- After each arm, `env_current = base.env_with_counters(env_current, arm_env)`
- If an arm doesn't terminate, emits `CmdJump(join_block, {})`
- **CRITICAL**: Arms use `env_next_block` to create fresh blocks, but if multiple arms jump to the same join_block, that's fine because join_block is created once.

---

### 5. `tree_to_back.lua` — Main lowering

#### `TreeBackEnv` structure:
```lua
Tr.TreeBackEnv(locals, next_value, next_block, ret)
```
- `locals`: list of local entries (scalar, stack, view)
- `next_value`: monotonically increasing integer counter for value IDs
- `next_block`: monotonically increasing integer counter for block IDs
- `ret`: return type info

#### `env_next_value` (lines 138-141):
```lua
local function env_next_value(env, prefix)
    local n = env.next_value + 1
    return Tr.TreeBackEnv(env.locals, n, env.next_block, env.ret),
           Back.BackValId(prefix .. tostring(n))
end
```
**Increments next_value, returns new env + fresh BackValId with prefix**.

#### `env_next_block` (lines 143-145):
```lua
local function env_next_block(env, prefix)
    local n = env.next_block + 1
    return Tr.TreeBackEnv(env.locals, env.next_value, n, env.ret),
           Back.BackBlockId(prefix .. tostring(n))
end
```
**Increments next_block, returns new env + fresh BackBlockId**.

#### `env_with_counters` (lines 112-113):
```lua
local function env_with_counters(env, counters)
    return Tr.TreeBackEnv(env.locals, counters.next_value, counters.next_block, env.ret)
end
```
**Takes `env`'s locals but `counters`'s next_value and next_block**. This is how counter state is threaded across branches.

#### `env_with_locals` (lines 108-110):
```lua
local function env_with_locals(env, locals)
    local out = {}; for i = 1, #locals do out[#out + 1] = locals[i] end
    return Tr.TreeBackEnv(out, env.next_value, env.next_block, env.ret)
end
```

#### Lower-if-expression (lines 869-907):
```lua
local then_block; current, then_block = env_next_block(current, "if.expr.then")
local else_block; current, else_block = env_next_block(current, "if.expr.else")
local join_block; current, join_block = env_next_block(current, "if.expr.join")
local result_value; current, result_value = env_next_value(current, "ifexpr")
```
Creates 3 blocks and 1 value in sequence, using the threaded `current` environment.

Then inside each branch (lines 888-900):
```lua
local then_start = env_with_counters(cond.env, current)
```
**Both then and else branches use `cond.env` as the base for locals and `current` for counters**. The `current` env has the counters after allocating blocks/values.

After branches (line 904):
```lua
return pvm.once(Tr.TreeBackExprValue(
    Tr.TreeBackEnv(cond.env.locals, current.next_value, current.next_block, cond.env.ret),
    cmds, result_value, result_scalar))
```
**Uses `cond.env.locals` and `current.next_value/next_block`** — the locals from the original env (before any in-branch locals), but the counters that were advanced past block/value allocations.

#### Lower-switch-expression (lines 909-968):
Same pattern as if-expression but with N arms. Creates arm_blocks, default_block, join_block, and result_value in sequence. Arms and default use `env_with_counters(value.env, current)` to get the latest counters.

#### Lower-if-statement (lines 1725-1796):
Same block/value creation pattern. Then does **phi analysis** for `LocalCell` bindings (lines 1761-1784):
```lua
for i = 1, #env.locals do
    local local_entry = env.locals[i]
    if pvm.classof(local_entry) == Tr.TreeBackScalarLocal
        and local_entry.binding.class == Bn.BindingClassLocalCell then
        local then_val = env_lookup(then_env, local_entry.binding)
        local else_val = env_lookup(else_env, local_entry.binding)
        local changed = (then_v ~= local_entry.value) or (else_v ~= local_entry.value)
        if changed then
            local phi_env, phi_val = env_next_value(pre_counters, "phi")
            pre_counters = phi_env
            cmds[#cmds + 1] = Back.CmdAppendBlockParam(join_block, phi_val, shape_scalar(local_entry.ty))
            ...
        end
    end
end
```
**Phi values are created via `env_next_value(pre_counters, "phi")`** — these get unique text IDs and are appended as block params to join_block.

#### Counter threading bug pattern: `env_with_counters(env, arm_env)` in the switch stmt (lines 1873-1874):
```lua
local start = env_with_locals(env_with_counters(value.env, current), value.env.locals)
local arm_env, arm_cmds, arm_flow = lower_body(self.arms[i].body, start)
...
current = env_with_counters(current, arm_env)
```
**Note**: For the `then_start`, it wraps: `env_with_locals(env_with_counters(value.env, current), value.env.locals)`. This creates an env with *value.env*'s counters but *thrice-wrapped* — the outer `env_with_locals` creates a *copy* of the env's locals array, but that copy would have been from `env_with_counters(value.env, current)` which has `value.env.locals`. But `current`'s next_value/next_block counters may have been advanced beyond `value.env`'s.

**KEY**: After each arm/block body, `current = env_with_counters(current, arm_env)` — this takes the *arm_env*'s counter values and puts them into `current`, discarding any new locals the arm may have added. But `current` is then passed to `env_with_counters(value.env, current)` for the next arm's start. This means the counters advance across arms sequentially.

---

### 6. `back_validate.lua` — Validation

#### Fact structure per command:
For each command, validation emits facts:
- `BackFactCreateBlock(index, block)` — registers block creation
- `BackFactBlockRef(index, block)` — records block reference
- `BackFactValueDef(index, value)` — registers value definition
- `BackFactValueUse(index, value)` — records value usage

#### Uniqueness checking (lines 103-110):
```lua
local function note_unique(seen, key, issue_fn, issues)
    if seen[key] then
        add_issue(issues, issue_fn())
        return false
    end
    seen[key] = true
    return true
end
```
Used for:
- `BackFactCreateSig` → `BackIssueDuplicateSig`
- `BackFactDeclareData` → `BackIssueDuplicateData`
- `BackFactDeclareFunc` → `BackIssueDuplicateFunc`
- `BackFactDeclareExtern` → `BackIssueDuplicateExtern`
- `BackFactCreateBlock` → `BackIssueDuplicateBlock`
- `BackFactStackSlotDef` → `BackIssueDuplicateStackSlot`
- `BackFactValueDef` → `BackIssueDuplicateValue`
- `BackFactAccessDef` → `BackIssueDuplicateAccess`

#### Missing reference checking:
- `BackFactBlockRef` without prior `BackFactCreateBlock` → `BackIssueMissingBlock`
- `BackFactValueUse` without prior `BackFactValueDef` → `BackIssueMissingValue`
- Similarly for data, func, extern, sig, stack slot, access

#### Key insight: `BackIssueDuplicateBlock`, `BackIssueDuplicateValue` in validation are the counterpart to `"block N dup"` and `"value N rebound"` in the Rust decoder. The validation runs *before* the Rust decoder, but:
1. Validation uses **text IDs** (the `BackBlockId`/`BackValId` text strings)
2. The Rust decoder uses **renumbered u32** IDs (from `back_command_binary.lua` renumbering)
3. **If `renumber()` maps two different text IDs to the same numeric ID**, the Rust decoder would see a dup that validation missed (since validation saw distinct text IDs)
4. **If `renumber()` maps the same text ID to TWO different numeric IDs**, validation would see a dup that the Rust decoder misses

---

## Relationships & Data Flow

### The counter threading chain:

```
env = env_empty(ret)                    # next_value=0, next_block=0

# Inside lower_func_common:
entry block allocated: env_next_block(env, "entry:fnName")
param values allocated: env_next_value(env, ...) for each parameter
    → each call creates a fresh BackValId("prefix:N")

# Inside lower_body:
for each stmt:
    stmt_to_back(stmt, current_env)
        → ExprLit: env_next_value(env, "v")
        → ExprBinary: env_next_value(env, "v")
        → ExprIf:
            env_next_block(current, "if.expr.then")
            env_next_block(current, "if.expr.else")    # uses current's next_block+1
            env_next_block(current, "if.expr.join")    # uses current's next_block+2
            env_next_value(current, "ifexpr")           # uses current's next_value+1
        → and so on...

# After each stmt:
current = result.env   # the env returned by the lowering function

# Inside control region lowering (tree_control_to_back.lua):
nonce_env, nonce_id = base.env_next_block(env, "ctl.region")
# nonce = nonce_id.text — e.g., "ctl.region.7"

# Then for each block label inside the region:
records[i].block = block_id(nonce, region_id, label)
# e.g., BackBackBlockId("ctl:7:region_id:read")

# Each param:
value_id(nonce, region_id, label, param_name)
# e.g., BackBackValId("ctl:7:region_id:read:i")
```

### The renumbering bridge:

1. Lua lowering produces commands with **text IDs** (e.g., `BackBackValId("ctl:7:region_id:read:i")`, `BackBackBlockId("ctl:7:region_id:read")`)

2. `back_command_binary.lua:renumber()` maps each text ID → dense u32 per function body:
   - First text ID → 0, next → 1, etc.
   - **Same text string always maps to same numeric ID** (because `map[s]` cache hit returns existing value)
   - **Different text strings always map to different numeric IDs** (because each gets a new sequentially-increasing value)

3. Rust `decode.rs` receives the flat u32 wire format and checks:
   - `bind(id, val)`: `id` must not already be in `values` HashMap → "value N rebound"
   - `val(id)`: `id` must be in `values` HashMap → "unknown value N"  
   - `blk(id)`: `id` must be in `blocks` HashMap → "unknown block N"
   - `CreateBlock`: `id` must not already be in `blocks` HashMap → "block N dup"

---

## Observations

### Observation 1: `renumber()` creates one continuous namespace for IDs per function

The `renumber()` function in `back_command_binary.lua` maps ALL text IDs (values, blocks, slots) into a **single dense u32 namespace** per function body. This means:

- Value IDs and block IDs share the same numeric space (0, 1, 2, 3, ...)
- If a block ID text string happens to equal a value ID text string, they would get the SAME numeric ID
- **This would cause the Rust decoder to see "block N dup"** — because when it creates a block with id=N, it inserts into `blocks`. Then when it tries to bind a value with id=N, it inserts into `values` (which is a different HashMap, so no error). But actually that's fine because `blocks` and `values` are separate HashMaps.
- **BUT**: The issue is subtler. If the same text string is used for both a block and a value, they get the same numeric ID. The Rust decoder uses separate HashMaps for blocks and values, so this should be fine. But if a *value* is described by a numeric ID that happens to also be a block ID, that depends on the specific encoding.

Actually wait — let me re-examine. In `renumber`: the `.map` stores text→u32 and the `nid` counter is per-function-body. So the first text string seen (whether it's a value, block, or slot) gets ID 0, next gets 1, etc. ALL text IDs across ALL categories share the same namespace per function.

In the Rust decoder:
- `blocks: HashMap<u32, Block>` — maps block numeric IDs to Cranelift Blocks
- `values: HashMap<u32, Value>` — maps value numeric IDs to Cranelift Values
- `stack_slots: HashMap<u32, StackSlot>` — maps slot numeric IDs to Cranelift StackSlots

These are separate maps, so collision between categories is harmless.

The **real** problem would be if the same text string of the *same category* appears twice (but with different semantic meanings). The `renumber` function would return the same numeric ID both times, causing:
- Two `CmdCreateBlock` for the same text → "block N dup"
- Two `CmdAppendBlockParam` for different block params but same value text → "value N rebound"

### Observation 2: Counter confusion in `lower-if-expression`

In `tree_to_back.lua` lines 888-904:
```lua
-- Then branch:
local then_start = env_with_counters(cond.env, current)
local then_result = expr_value(expr_to_back:one_uncached(self.then_expr, then_start))
...
current = env_with_counters(current, then_result.env)

-- Else branch:
local else_start = env_with_counters(cond.env, current)
...
current = env_with_counters(current, else_result.env)
```

The `then_start` uses `cond.env`'s locals and `current`'s counters. The `current` env has higher counters (because of block/value allocation for if/else/join/result). This is correct — the then/else branches should see counters that reflect the blocks created before them.

But then the final result (line 906):
```lua
return pvm.once(Tr.TreeBackExprValue(
    Tr.TreeBackEnv(cond.env.locals, current.next_value, current.next_block, cond.env.ret),
    cmds, result_value, result_scalar))
```

This uses `cond.env.locals` (original locals, not including then/else locals) and `current`'s counters. **Any locals added in the then/else branches are discarded.** This is correct because branches don't escape their locals in expression form.

### Observation 3: Switch arm env threading in `lower_joining_arms`

In `tree_control_to_back.lua`, `lower_joining_arms` (lines 201-250):
```lua
for i = 1, #arms do
    local start = base.env_with_counters(env, env_current)
    ...
    env_current = base.env_with_counters(env_current, arm_env)
end

cmds[#cmds + 1] = Back.CmdSwitchToBlock(default_block)
local default_start = base.env_with_counters(env, env_current)
...
env_current = base.env_with_counters(env_current, default_env)

return Tr.TreeBackStmtResult(base.env_with_counters(env, env_current), cmds, ...)
```

Here `env` is the base env passed to `lower_joining_arms`, and `env_current` carries the cumulative counter state across all arms. Each arm starts with `env_with_counters(env, env_current)` — getting the base locals but the accumulated counters. Then after the arm, `env_current` is updated with the arm's counters.

**Potential issue**: If two arms create values/block params with the same text prefix (e.g., via `env_next_value(start, "v")`), the text IDs would differ because they have different counter values. But `renumber` would then assign different numeric IDs. So this is fine.

**But**: If the same text ID is produced by two arms (e.g., both arms emit a `CmdCreateBlock` with the same `BackBackBlockId`), `renumber` would map them to the same numeric ID, causing "block N dup" in the decoder. **This could happen if a bug causes block_id/block_creation code to run twice with the same text.**

### Observation 4: The nonce collision risk in `lower_region`

In `tree_control_to_back.lua` line 357:
```lua
local nonce_env, nonce_id = base.env_next_block(env, "ctl.region")
local nonce = nonce_id.text
```
The nonce is generated from `env_next_block` — a monotonic counter. If two regions are embedded in the same function body, they get different nonces.

**BUT**: The nonce is the *text* of a block ID created by `env_next_block`. If there's a bug where the counter is not advanced between two calls to `lower_region`, the same nonce could be used for two different regions, causing all their internal IDs to collide.

### Observation 5: `CmdBindEntryParams` expansion in the encoder

In `back_command_binary.lua` lines 159-168:
```lua
elseif k == "CmdSealBlock" or k == "CmdBindEntryParams" then
    if k == "CmdBindEntryParams" and b.sig then
        for idx, p in ipairs(b.sig.params) do
            local val = cmd.values[idx]
            w4(buf, T.AppendBlockParam)
            w4(buf, b:nid(cmd.block))
            w4(buf, st(p))
            w4(buf, b:nid(val))
        end
    end
```
**This silently drops `CmdSealBlock`** — it enters the `elseif` branch for both but only emits for `CmdBindEntryParams`. The `CmdSealBlock` is a no-op in encoding.

But more critically: `CmdBindEntryParams` is expanded into multiple `AppendBlockParam` commands. The value IDs from `cmd.values` are emitted as `s[2]` in the wire format. If the same value ID text appears later in the body (e.g., as a `CmdIntBinary` dst), the `renumber` function will give it the same numeric ID, and the Rust decoder's `bind()` will produce "value N rebound".

**This is EXACTLY the scenario where value rebound happens**: The entry block params are bound to value IDs via `AppendBlockParam`. Then later commands with the same dst value ID will trigger "value N rebound" in the decoder. The entry param values SHOULD be reused as references to the entry param, NOT as destinations for new operations.

### Observation 6: The `nonce` text versus numeric ID relationship

The nonce in `tree_control_to_back.lua` is a block ID text (e.g., `"ctl.region.5"`). When this is fed through `renumber`, it becomes a small u32.

Inside the region lowering:
```lua
records[i].block = block_id(nonce, region_id, label)
-- e.g., "ctl:5:control.find:read"  → numeric N
```

All IDs within a region share the nonce prefix, so they're distinct from IDs in other regions (different nonce). But **within a region**, IDs are:
- Block IDs: `"ctl:5:control.find:read"`, `"ctl:5:control.find:found"`, `"ctl:5:control.find:exit"`
- Value IDs: `"ctl:5:control.find:read:i"`, `"ctl:5:control.find:found:i"`, `"ctl:5:control.find:result"`

These are all distinct text strings, so `renumber` gives them distinct numeric IDs. No collision within a region.

### Observation 7: The special case of `fresh_id()` synthetic IDs

In `back_command_binary.lua`, `fresh_id()` generates `"__a0"`, `"__a1"`, etc. These synthetic IDs are generated *during encoding* for address computation intermediates (when a load/store uses a stack or global data address base). They are passed through `b:nid()` for renumbering.

**Key insight**: These synthetic IDs are produced during encoding, AFTER the Lua lowering has already produced all the "real" text IDs. They get fed into the same renumbering namespace. If they happen to collide with a real text ID... they can't, because `"__aN"` is a distinct text prefix that won't match real lowering-generated IDs.

But there's a subtle issue: `fresh_id()` is called with a `local` counter `addr_counter` inside `encode_body`. Each call to encode_body creates a fresh counter starting at 0. So across multiple function bodies, the same `"__a0"` could appear. But since each body has its own renumbering, that's fine.

### Observation 8: Validation uses text IDs, decoder uses numeric IDs

The validation in `back_validate.lua` checks for duplicate value defs using **text IDs** (the `BackBackValId`/`BackBackBlockId` text). The Rust decoder checks for duplicate value binds using **numeric IDs** (after renumbering).

Since `renumber()` is a bijection between text strings and u32s within a function body (same text → same u32, different text → different u32), the two checks should agree:
- If validation sees duplicate `BackFactValueDef` for the same text ID (duplicate text), the Rust decoder would also see "value N rebound" for the same numeric ID.
- If validation sees a `BackFactValueUse` for a text ID without a prior `BackFactValueDef`, the Rust decoder would also get "unknown value N" for that numeric ID.

**The only way they could disagree** is if `renumber()` has a bug (e.g., returning the wrong numeric ID for a given text).

### Observation 9: `FunctionBuilderContext` reuse

In `decode.rs`:
```rust
let mut fctx = FunctionBuilderContext::new();
for (wire_fid, body_off, body_len) in &bodies {
    // ...
    let mut bctx = BodyCtx::new(&mut ctx.func, &mut fctx);
    decode_body(bb, ptr_ty, &mut bctx, &refs)?;
    bctx.finalize();
    // ...
}
```

`fctx` is reused across all function bodies. `FunctionBuilderContext` in Cranelift tracks internal state (which blocks are sealed, etc.). `seal_all_blocks()` should reset state... but let me check if `FunctionBuilderContext` has any residual state that could affect the next function's decoding.

Actually, looking at Cranelift source: `FunctionBuilderContext` stores a `Vec<SealedBlockInfo>`. When `seal_all_blocks()` is called, it processes all pending blocks. When `finalize()` is called on the `FunctionBuilder`, it may leave some state in `fctx`. If `fctx` retains state from one function to the next, it could cause issues. But typically Cranelift's `FunctionBuilderContext` is designed to be reused.

### Summary of bug-susceptible points:

1. **"value N rebound"**: Can happen if the same text value ID appears in two different `bind()` sites. This could happen if:
   - `CmdAlias` uses a dst that was already bound
   - `CmdBindEntryParams` expansion (in encoder) emits an `AppendBlockParam` for a value that also appears as a later command's dst

2. **"unknown block N"**: Can happen if a block reference (e.g., in `CmdJump`, `CmdBrIf`, `CmdSwitchInt`, `CmdSwitchToBlock`) uses a block ID that was never created via `CmdCreateBlock`.

3. **"block N dup"**: Can happen if `CmdCreateBlock` is emitted twice with the same block text ID. In `renumber()`, the same text maps to the same numeric u32, so the Rust decoder's `CreateBlock` handler would see the duplicate.

## Knowledge-builder Output — 2026-05-19 00:11:50

Now I have the full picture. Let me produce the complete analysis.

---

## What Matters Most for This Problem

The scout found one encoder bug that explains ALL three error types ("value N rebound", "unknown block N", "block N dup") through a single root cause: **the `CmdAppendBlockParam` encoder path omits the value_id from the wire format**, causing a cascading protocol desync that manifests as different errors depending on which byte happens to be consumed.

The relevant dimensions: **wire format stability, data flow correctness (encoder↔decoder agreeing on slot counts), and error localization (one bug producing many seemingly unrelated errors).**

---

## Non-Obvious Observations

### 1. The Root Cause: A Single Missing `w4()` Call

The `CmdAppendBlockParam` encoder in `back_command_binary.lua:155-156` writes **only 2 slots** to the wire (block_id, scalar_type):

```lua
elseif k == "CmdAppendBlockParam" then
    w4(buf, T.AppendBlockParam); w4(buf, b:nid(cmd.block)); w4(buf, st(cmd.ty))
    -- BUG: missing: w4(buf, b:nid(cmd.value))
```

But the Rust decoder in `decode.rs` reads **3 slots** (`TAG_SLOTS[AppendBlockParam] = 3`):

```rust
t if t == WireTag::AppendBlockParam as u32 => {
    let b = ctx.blk(s[0])?;
    let ty = st(s[1], ptr_ty)?;
    let v = ctx.builder.append_block_param(b, ty);
    ctx.bind(s[2], v)?;  // s[2] is the NEXT u32 in the buffer, NOT the value_id
}
```

**This means `s[2]` is always the first u32 of the next command in the wire stream**, because the decoder's position is 4 bytes (one u32) ahead of where the encoder intended. This causes a **persistent +1 slot offset desync** in the wire protocol — the decoder consumes the next command's tag (or its first slot) as the missing value_id.

### 2. Causal Chain: Why "value 1 rebound" Specifically

From my trace of `first_three_or_n` (the first function in the test):

**The wire buffer after the first three commands** (CreateBlock entry, SwitchToBlock entry, BindEntryParams expansion):
```
[1, 0] [2, 0] [3, 0, 4, 1]
```

**Then the buggy CmdAppendBlockParam at position 36 in the buffer:**
- Encoder writes: `[3, 2, 4]` (tag=AppendBlockParam, block_id=2="read", scalar_type=4=i32)
- Only 2 data slots

**Decoder reads 3 slots starting at the same position:**
- s[0] = 2 (correct block_id)
- s[1] = 4 (correct scalar_type)
- s[2] = 1 (the NEXT u32 in buffer — which is the **tag of the next CmdCreateBlock** = `WireTag::CreateBlock`)

Then `ctx.bind(1, v)` fails because **value_id 1 was already bound by the earlier `CmdBindEntryParams` expansion** (value "arg:first_three_or_n:n", the function argument). Hence: "value 1 rebound".

The literal numeric 1 comes from the wire tag value of `CreateBlock` — a complete coincidence of the tag numbering scheme. If the consumed tag had been any other value, a different error would appear.

### 3. All Three Errors Are the Same Desync, Differing Only in What's Consumed

Depending on what the first consumed u32 happens to be:

| Consumed u32 | Error type | Mechanism |
|---|---|---|
| **Tag value 1** (CreateBlock) | "value N rebound" | The consumed tag happens to equal a previously bound value_id |
| **Block ID** (>= 2 typically) | "value N rebound" | Same mechanism if the consumed block ID equals a bound value_id |
| **Any value** not previously bound | "unknown block N" later | The desync shifts the read position, causing subsequent block references to point at wrong numerics |
| **n_args/args data** | "unknown block N" or "block N dup" | After the initial desync, the decoder misinterprets command boundaries, creating phantom blocks or referring to non-existent ones |

For `control_switch` (function 3), my trace showed the consumed u32 is **170** (the tag of the next `CmdJump`). No collision with value 1 (which is "arg:control_switch:n"), so no immediate "value 1 rebound". But the desync causes subsequent misreads — the decoder sees `tag=8`, `tag=9`, `tag=10` in what are actually value_ids (v1, v2, v3), interpreting each as a command tag. This would eventually produce "unknown block N" or other errors.

### 4. The CmdBindEntryParams Expansion Path Is Correct — the Contrast Tells the Story

The `CmdBindEntryParams` encoder path (lines 159-167) correctly writes 3 slots:
```lua
if k == "CmdBindEntryParams" and b.sig then
    for idx, p in ipairs(b.sig.params) do
        local val = cmd.values[idx]
        w4(buf, T.AppendBlockParam)
        w4(buf, b:nid(cmd.block))
        w4(buf, st(p))
        w4(buf, b:nid(val))   -- CORRECT: value_id included
    end
end
```

This path works because it writes `TAG_SLOTS[3] = 3` data slots. All AppendBlockParam commands from `CmdBindEntryParams` work fine. Only `CmdAppendBlockParam` commands (from control region lowering and explicit block param definitions) trigger the bug.

### 5. Why Validation Does Not Catch This

The validator (`back_validate.lua`) operates on the **Lua-side command objects** (text IDs), not the **wire format** (renumbered u32s). It sees:

- `BackFactValueDef` from `CmdBindEntryParams` (correct)
- `BackFactValueDef` from `CmdAppendBlockParam` (correct in the text-ID space)

The validator correctly sees that each value ID appears exactly once in the command list. The bug is in the **encoding of the value_id into the wire format**, which the validator never checks. The validator validates the *lowering*, not the *encoding*.

### 6. The Nonce/Counter Threading Is Actually Correct — a Red Herring

My trace proves that the `env_next_value`/`env_next_block` counter threading in `tree_to_back.lua` and `tree_control_to_back.lua` is **correct**. The value IDs I traced ("v1", "v2", etc.) all get unique text strings and thus unique renumbered IDs. The text IDs for entry params ("arg:funcName:paramName") are completely disjoint from the instruction destination pattern ("vN", "phiN", etc.).

The scout's suspicion about counter confusion was a reasonable hypothesis, but the actual mechanism is the much simpler encoder bug. The counter threading produces correct text IDs; the bug is in the slot count mismatch for `AppendBlockParam`.

### 7. Every Control Region With Block Params Is Affected — Not Just Switch

`declare_blocks` in `tree_control_to_back.lua:178-188` emits `CmdAppendBlockParam` for **every block parameter in every control region**:

```lua
local function declare_blocks(cmds, records, exit_block, exit_value, exit_scalar)
    for i = 1, #records do
        cmds[#cmds + 1] = Back.CmdCreateBlock(records[i].block)
        for j = 1, #records[i].params do
            cmds[#cmds + 1] = Back.CmdAppendBlockParam(records[i].block, records[i].params[j].value, shape_scalar(records[i].params[j].scalar))
        end
    end
    cmds[#cmds + 1] = Back.CmdCreateBlock(exit_block)
    if exit_value ~= nil then
        cmds[#cmds + 1] = Back.CmdAppendBlockParam(exit_block, exit_value, shape_scalar(exit_scalar))
    end
end
```

For `first_three_or_n`:
- Entry block "read" has 1 param → 1 buggy AppendBlockParam (pos 5)
- Block "found" has 1 param → 1 buggy AppendBlockParam (pos 7)
- Exit block has 1 result → 1 buggy AppendBlockParam (pos 9)
- **Total: 3 desync events per function body call**

For `control_switch`:
- Exit block has 1 result → 1 buggy AppendBlockParam
- **Total: 1 desync event, consuming tag=170 (Jump)**

### 8. The `fctx` Reuse Is Not a Factor

The scout raised this as a concern, but each function body creates its own `BodyCtx` (with its own fresh HashMaps). The `FunctionBuilderContext` is designed for reuse and `seal_all_blocks()`/`finalize()` properly resets it. The error is per-body, not cross-body contamination.

### 9. The Text-to-Numeric Renumbering Is a Correct Bijection

My trace confirmed that `renumber()` generates unique numeric IDs for each distinct text string per body. The "value 1 rebound" is NOT caused by two text IDs mapping to the same numeric ID. It's caused by the protocol desync reading a numeric value (tag=1) that happens to collide with a correctly-renumbered value (arg n = 1).

---

## Knowledge Gaps

1. **Vec kernel path**: The `vec_kernel_to_back.lua` also uses `CmdAppendBlockParam` (line 571-574). If vec kernels are compiled through the same binary encoder path, they would also trigger this bug. Confirm by checking whether vec tests pass.

2. **Host export wrapper**: The `lower_host_export_wrapper` function in `tree_to_back.lua` does not use control regions, but does it use `CmdAppendBlockParam`? It uses `CmdBindEntryParams` (which is correctly encoded), but if any `CmdAppendBlockParam` leaks in through the lowering, it would also trigger the bug.

3. **The `reencounter` test**: The test file has 3 functions. My trace shows `first_three_or_n` hits "value 1 rebound". But `control_stmt_exit` (function 2) has no CmdAppendBlockParam (no block params in its region, no exit value), so it might decode successfully despite the desync in function 1. What happens to function 3 (`control_switch`)? It has its own renumbering and would hit a different symptom after the buggy AppendBlockParam consumes tag=170. The decoder might produce "unknown block N" or silently produce wrong Cranelift IR for this function.

## Scout Output — 2026-05-19 00:21:25

## Raw Facts Report

### Files Retrieved
1. `lua/lalin/back_command_binary.lua` (full read, 525 lines) — Binary wire format encoder
2. `lua/lalin/tree_to_back.lua` (lines 39, 627-631, 1029-1037, 1323-1327, 1529-1584) — Lowering logic
3. `src/decode.rs` (full read, 303 lines) — Rust Cranelift IR decoder
4. `src/wire_tags.rs` (full read, ~200 lines) — TAG_SLOTS definitions
5. `tests/test_tree_to_back_control_multiblock.lua` (full read) — Test file
6. `benchmarks/bench_json_stack_decode.lua` — JSON decoder benchmark
7. `examples/json/json_lua_stack_decoder.mlua` — Complex decoder example

### Key Code

#### 1. `CmdPtrOffset` is entirey missing from the encoder

In `back_command_binary.lua:encode_body`, there are 48 `elseif` branches handling various command kinds. **None handle `k == "CmdPtrOffset"`**:

```lua
-- Line 130-525: ~48 elseif branches covering:
-- CmdCreateBlock, CmdSwitchToBlock, CmdAppendBlockParam, CmdCreateStackSlot,
-- CmdSealBlock/CmdBindEntryParams, CmdAlias, CmdStackAddr, CmdDataAddr,
-- CmdFuncAddr, CmdExternAddr, CmdConst, CmdIntBinary, CmdFloatBinary,
-- CmdBitBinary, CmdBitNot, CmdShift, CmdCompare, CmdCast, CmdLoadInfo,
-- CmdStoreInfo, CmdUnary, CmdIntrinsic, CmdMemcpy, CmdMemset,
-- CmdReturnVoid, CmdReturnValue, CmdTrap, CmdJump, CmdBrIf, CmdSwitchInt,
-- CmdSelect, CmdFma, CmdVecSplat, CmdVecInsertLane, CmdVecExtractLane,
-- CmdVecBinary, CmdVecCompare, CmdVecSelect, CmdVecLoadInfo, CmdVecStoreInfo,
-- CmdCall
-- *** NO CmdPtrOffset BRANCH ***
```

The `PtrOffset` tag is defined as `121` (line 51) in the tag table but the encoder branch is absent.

#### 2. How `CmdPtrOffset` is produced in the lowering

In `tree_to_back.lua` lines 1559-1581 (`IndexBasePlace` handler):
```lua
cmds[#cmds + 1] = Back.CmdPtrOffset(addr_val, Back.BackAddrValue(base.value), off_val, 1, 0,
    Back.BackProvDerived("place index address"), Back.BackPtrBoundsUnknown)
return pvm.once(Tr.TreeBackExprValue(env3, cmds, addr_val, Back.BackPtr))
```

The `addr_val` is the value produced by `CmdPtrOffset`. It's then used by `ExprIndex`:

```lua
[Tr.ExprIndex] = function(self, env)
    local lowered = index_addr_to_back:one_uncached(self.base, self.index, expr_ty(self), env)
    -- lowered.value = addr_val (from CmdPtrOffset)
    local env3 = append_load_info(cmds, env2, dst, shape_scalar(scalar), lowered.value, dst.text)
    -- uses lowered.value as address in CmdLoadInfo
```

#### 3. Wire format analysis proves the drop

Python hex dump of Body 0 (parse_array function, first load access):
```
[  788] tag= 16 (ConstInt) slots=[44, 13, 0, 0]     -- const i64 0
[  808] tag=110 (Load) slots=[45, 6, 0, 46]          -- Load(dst=45, u8, flags=0, addr=46)
```

There's `ConstInt` (value 44) then immediately `Load` using address value 46. **No PtrOffset between them.** Value 46 was never defined — the PtrOffset that would produce it was silently dropped.

#### 4. The decoder correctly handles PtrOffset

In `decode.rs`:
```rust
t if t == WireTag::PtrOffset as u32 => {
    let base = ctx.val(s[1])?; let idx = ctx.val(s[2])?;
    let es = s[3] as i64; let coff = (s[4] as i64) | ((s[5] as i64) << 32);
    let ev = ctx.builder.ins().iconst(ptr_ty, es);
    let sc = ctx.builder.ins().imul(idx, ev);
    let total = if coff == 0 { sc } else { ... };
    let result = ctx.builder.ins().iadd(base, total);
    ctx.bind(s[0], result)?;
}
```

TAG_SLOTS[121] = 6: [dst, base, index, elem_size, const_lo, const_hi]. The decoder can handle it — the encoder just doesn't emit it.

#### 5. Every function body has missing values

The Python decoder confirmed missing values in all 4 JSON decoder function bodies:
```
Body 0 (parse_array):     Missing VALUES: [46, 76, 112, 142, 174]
Body 1 (parse_object):    Missing VALUES: [126, 156, 173, ... 30 total]
Body 2 (parse_value):     Missing VALUES: [159, 189, 215, ... 30 total]
Body 3 (decode_json):     Missing VALUES: [36]
```

These are all address values that should have been produced by `CmdPtrOffset`.

#### 6. The `first_three_or_n` test works correctly

The schema-parsed test `test_tree_to_back_control_multiblock.lua` actually produces correct machine code. The only problem is **the test's expected values are wrong**:

```lua
-- control_switch: switch n { case 10: yield 10; case 11: yield 11; default: yield 12 }
assert(h(0) == 10)  -- WRONG: 0 != 10, should be 12 (default)
assert(h(1) == 11)  -- WRONG: 1 != 11, should be 12 (default)
assert(h(2) == 12)  -- CORRECT: 2 != 10/11, default case → 12
```

The actual behavior confirmed by debug run:
```
h(0)  = 12    (default: no match for 0)
h(10) = 10    (matches case 10)
h(11) = 11    (matches case 11)
h(2)  = 12    (default: no match for 2)
```

The test expects h(0) == 10 and h(1) == 11, but these should be 12 (the default case for unmatched values).

#### 7. No other encoder slot-count mismatches found

Every other encoder branch was verified to match TAG_SLOTS counts:
- All constant encodings: ✓
- All binary/float/bit ops: ✓ (3 slots)
- Compare: ✓ (4 slots)
- Cast: ✓ (3 slots)
- Load/Store: ✓ (4 slots)
- Jump: ✓ (2 fixed + variable)
- Brif: ✓ (2 fixed + variable)
- SwitchInt: ✓ (3 fixed + variable)
- CallDirect/Extern/Indirect: ✓ (5 fixed + variable)

### Root Cause Summary

**Bug 1** (`h(0) == 10` fails): The test expectations are simply wrong. The `control_switch` function matches against integer values 10 and 11. `h(0)` should return 12 (default case), not 10.

**Bug 2** (`unknown value 46`): `CmdPtrOffset` is entirely missing from `back_command_binary.lua:encode_body`. When `tree_to_back.lua` lowers a `p[i]` expression (loading from a pointer with an index), it emits:
1. `CmdPtrOffset(addr_val, BackAddrValue(base_ptr), off_val, 1, 0, ...)` — to compute the address
2. `CmdLoadInfo(dst, shape, BackAddress(BackAddrValue(addr_val), zero), ...)` — to load from that address

Since `CmdPtrOffset` is dropped by the encoder, `addr_val` is never bound in the Rust decoder's `values` HashMap. When `CmdLoadInfo` references that value, `ctx.val(id)` returns `Err("unknown value N")`.

The fix is to add a `CmdPtrOffset` encoder branch that writes `T.PtrOffset` with 6 slots: `[b:nid(cmd.dst), b:nid(cmd.base.value), b:nid(cmd.index), cmd.elem_size, const_lo, const_hi]`. The `CmdLoadInfo`/`CmdStoreInfo` handlers for `BackAddrValue` already reference the address correctly — the only missing piece is the `CmdPtrOffset` encoding.

## Scout Output — 2026-05-19 00:24:47

Now I have all the data needed. Here is the complete raw-facts report.

---

## Raw Facts Report

## Files Retrieved
1. `lua/lalin/back_command_binary.lua` (full read, 733 lines) — Binary wire format encoder
2. `src/decode.rs` (full read, 303 lines) — Rust Cranelift IR decoder
3. `src/wire_tags.rs` (full read, ~200 lines) — TAG_SLOTS definitions
4. `lua/lalin/schema/back.lua` (via grep) — `CmdCreateSig`, `CmdDeclareExtern` schema
5. `lua/lalin/back_validate.lua` (full read, ~680 lines) — Validation (not relevant to sig bug)
6. `src/lib.rs` (lines 40-90) — `BackScalar::clif_type()`
7. `lua/lalin/tree_to_back.lua` (via grep) — `lower_extern_direct`, `CmdCall` lowering
8. `examples/json/json_lua_stack_decoder.mlua` (full read) — The test case exhibiting the bug
9. `benchmarks/bench_json_stack_decode.lua` (full read) — Benchmark runner

## Key Code

### Bug #1: Extern declaration `sig_id` is hardcoded to 0

**Encoder** (`back_command_binary.lua` lines 677-688):
```lua
-- Externs
w4(dbuf, #externs)
for i, cmd in ipairs(externs) do
    w4(dbuf, i - 1); w4(dbuf, 0); -- extern_id, sig_id (placeholders)
    local name = cmd.symbol
    w4(dbuf, #name)
    dbuf[#dbuf+1] = name
    local pad = (4 - (#name % 4)) % 4
    if pad > 0 then dbuf[#dbuf+1] = ("\0"):rep(pad) end
end
```
`sig_id` is always written as `0`. The comment says `"placeholders"` but it was never filled in.

**Contrast with `func` encoding** (lines 668-675) which correctly uses `sig_idx`:
```lua
for i, cmd in ipairs(funcs) do
    w4(dbuf, i - 1); w4(dbuf, sig_idx[id(cmd.sig)] or 0); -- func_id, sig_id  ← CORRECT
```

**The `sig_idx` map exists and is populated** (lines 607-611):
```lua
local sig_idx = {}
for i, cmd in ipairs(sigs) do
    sig_idx[id(cmd.sig)] = i - 1
end
```
But it's never used in the extern encoding path.

**Decoder** (`decode.rs` lines 173-185) correctly reads `sig_id` and resolves the signature:
```rust
let eid = read_u32(buf, pos)?;
let sig_id = read_u32(buf, pos)?;
...
let (p, r) = sig_types.get(&sig_id)
    .ok_or_else(|| LalinError(format!("extern {eid}: unknown sig {sig_id}")))?;
let sig = mk_sig(module, p, r);
let cfid = module.declare_function(&sym, Linkage::Import, &sig)
```

Since `sig_id` is always `0`, every extern function is declared with `sig_types[0]` — the **first** signature emitted by `CmdCreateSig`.

### Bug #2: `CmdCall` for externs uses `b.func_map` instead of `b.extern_map`

**Encoder** (`back_command_binary.lua` lines 504-506):
```lua
elseif tgt.kind == "BackCallExtern" then
    tag = T.CallExtern
    target_id = b.func_map[id(tgt.func)] or 0   ← BUG: uses func_map, not extern_map
```
`b.func_map` only contains **internal functions** (declared via `CmdDeclareFunc`), not externs. So this always returns `nil`, and `target_id` is always `0`.

**Contrast with `CmdExternAddr`** (line 181-182) which correctly uses `b.extern_map`:
```lua
elseif k == "CmdExternAddr" then
    w4(buf, T.ExternAddr); w4(buf, b:nid(cmd.dst)); w4(buf, 12); w4(buf, (b.extern_map or {})[id(cmd.func)] or 0)
```

**The `b.extern_map` is attached to each body** (lines 625-626):
```lua
b.func_map = func_map
b.data_map = data_map
b.extern_map = extern_map   ← correct map exists but is not used in CmdCall
```

### How the two bugs combine to produce the exact error

The JSON decoder .mlua declares externs in this order:
```lalin
lua_createtable(L, narr: i32, nrec: i32)     → sig 0: [ptr, i32, i32] → void
lua_pushlstring(L, s: ptr(u8), len: index)    → sig 1: [ptr, ptr, index] → void
lua_pushnumber(L, n: f64)                     → sig 2: [ptr, f64] → void
lua_pushboolean(L, b: i32)                    → sig 3: [ptr, i32] → void
lua_pushnil(L)                                → sig 4: [ptr] → void
lua_settable(L, idx: i32)                     → sig 5: [ptr, i32] → void
lua_rawseti(L, idx: i32, n: i32)              → sig 6: [ptr, i32, i32] → void
```

**Bug #2** makes every extern declared with `sig_id=0` (the `[ptr, i32, i32]` signature of `lua_createtable`).

**Bug #1** makes every `call lua_pushlstring(...)` target extern_id=0 (`lua_createtable`).

So the Cranelift verifier sees:
```
call fn9(v16, v20, v217)  →  call lua_createtable(L, s, len)
```
where:
- v16 = L (a `ptr`, Cranelift type `i64`)
- v20 = s (a `ptr(u8)`, Cranelift type `i64`)
- v217 = len (an `index`, `BackScalar::Index` → `ptr_ty` → `i64` on 64-bit)

But `lua_createtable`'s signature says `[ptr, i32, i32]`, so it expects:
- arg 0: ptr → i64 ✓ (L matches)
- arg 1: i32 ≠ i64 ✗ (v20 is ptr, should be i32)
- arg 2: i32 ≠ i64 ✗ (v217 is index, should be i32)

This produces:
```
call fn9(v16, v20, v217): arg 1 (v20) has type i64, expected i32
call fn9(v16, v20, v217): arg 2 (v217) has type i64, expected i32
```

Both error lines match exactly.

### The `st()` mapping (Schema → Wire → Cranelift) IS correct

**Lua encoder** (`back_command_binary.lua` line 72-78):
```lua
local S = { BackBool=1, BackI8=2, BackI16=3, BackI32=4, BackI64=5,
    BackU8=6, BackU16=7, BackU32=8, BackU64=9, BackF32=10,
    BackF64=11, BackPtr=12, BackIndex=13 }
```

**Rust decoder** (`decode.rs` lines 43-56):
```rust
fn st(code: u32, ptr_ty: Type) -> Result<Type, LalinError> {
    let bs = match code {
        1 => BackScalar::Bool, 2 => BackScalar::I8, 3 => BackScalar::I16,
        4 => BackScalar::I32, 5 => BackScalar::I64, 6 => BackScalar::U8,
        7 => BackScalar::U16, 8 => BackScalar::U32, 9 => BackScalar::U64,
        10 => BackScalar::F32, 11 => BackScalar::F64, 12 => BackScalar::Ptr,
        13 => BackScalar::Index,
        ...
    };
    Ok(bs.clif_type(ptr_ty))
}
```

**Rust `clif_type()`** (`src/lib.rs` lines 49-59):
```rust
fn clif_type(self, ptr_ty: Type) -> Type {
    match self {
        Self::Bool => types::I8,
        Self::I8 | Self::U8 => types::I8,
        Self::I16 | Self::U16 => types::I16,
        Self::I32 | Self::U32 => types::I32,
        Self::I64 | Self::U64 => types::I64,
        Self::F32 => types::F32,
        Self::F64 => types::F64,
        Self::Ptr | Self::Index => ptr_ty,
    }
}
```

All three layers agree. Wire code 4 → `BackScalar::I32` → `types::I32`. Wire code 5 → `BackScalar::I64` → `types::I64`. Wire code 12 → `BackScalar::Ptr` → `ptr_ty`. Wire code 13 → `BackScalar::Index` → `ptr_ty`. **The type code mapping itself is not the problem.**

### The signature encoding/decoding IS correct

**Encoder** (lines 643-652):
```lua
w4(dbuf, #sigs)
for i, cmd in ipairs(sigs) do
    w4(dbuf, i - 1) -- sig_id
    local params = cmd.params
    w4(dbuf, #params)
    for _, p in ipairs(params) do w4(dbuf, st(p)) end
    local results = cmd.results
    w4(dbuf, #results)
    for _, r in ipairs(results) do w4(dbuf, st(r)) end
end
```

**Decoder** (`decode.rs` lines 100-111):
```rust
let n = read_u32(buf, pos)?;
for _ in 0..n {
    let sid = read_u32(buf, pos)?;
    let np = read_u32(buf, pos)?;
    let pc = read_slots(buf, pos, np as usize)?;
    let params: Vec<Type> = pc.into_iter().map(|c| st(c, ptr_ty)).collect::<Result<_,_>>()?;
    let nr = read_u32(buf, pos)?;
    let rc = read_slots(buf, pos, nr as usize)?;
    let results: Vec<Type> = rc.into_iter().map(|c| st(c, ptr_ty)).collect::<Result<_,_>>()?;
    sig_types.insert(sid, (params.clone(), results.clone()));
    let sig = mk_sig(module, &params, &results);
    sigs.insert(sid, sig);
}
```

The signature parameter types are correctly encoded as `[st(p) for each param]` and correctly decoded as `[st(c, ptr_ty) for each code]`. The type codes in the signature are correct. **The problem is that the wrong sig_id (0) is written for the extern declaration**, so the signature lookup picks sig_types[0] instead of the correct sig.

### The `CmdCall` sig_id at the call site is ignored by the decoder

The encoder writes `w4(buf, 0)` for sig_id at the call site (line 522), but the decoder never reads it:

**Decoder** (`decode.rs` lines 515-523):
```rust
t if t == WireTag::CallExtern as u32 => {
    let rt = s[0]; let eid = s[3];  // s[1], s[2], s[4] (sig_id) are IGNORED
    let na = read_u32(buf, &mut pos)? as usize;
    let ids = read_slots(buf, &mut pos, na)?;
    let fr = refs.extern_refs.get(&eid)...  // FuncRef from import declaration
    let inst = ctx.builder.ins().call(fr, &args);  // Cranelift validates args against FuncRef's signature
```

Cranelift's `call(fr, args)` uses the signature embedded in the `FuncRef`, which was set during `module.declare_function()` in the declaration section. So the decoder doesn't need sig_id at the call site — it validates against the import's signature.

### How extern lowering creates the correct sig but the wrong wire ID

**`tree_to_back.lua`** (lines 2368-2373):
```lua
local function lower_extern_direct(func_node)
    local cls = pvm.classof(func_node)
    if cls == Tr.ExternFunc then
        local sig = Back.BackSigId("sig:extern:" .. func_node.symbol)
        local ps, rs = func_sig(func_node.params, func_node.result)
        return Tr.TreeBackItemResult({
            Back.CmdCreateSig(sig, ps, rs),           ← correct params
            Back.CmdDeclareExtern(Back.BackExternId(func_node.symbol), func_node.symbol, sig)
        })
```

`ps` contains the correct `BackScalar` values (e.g., `[BackPtr, BackPtr, BackIndex]` for `lua_pushlstring`).

The `CmdCreateSig` correctly creates the signature with these params. The `CmdDeclareExtern` correctly references `sig`. **The encoder then writes the wrong wire sig_id.**

## Relationships

```
tree_to_back.lua:  lower_extern_direct
    → CmdCreateSig(sig_id= "sig:extern:lua_pushlstring", params=[ptr, ptr, index])
    → CmdDeclareExtern(extern_id="lua_pushlstring", sig="sig:extern:lua_pushlstring")
         │
         ▼
back_command_binary.lua:encode(M.encode)
    → sigs[i] = CmdCreateSig (correct)
    → externs[i] = CmdDeclareExtern
         │
         ├─ sig encoding: st(BackPtr)=12, st(BackPtr)=12, st(BackIndex)=13  ✓
         │
         └─ extern encoding: 
                w4(dbuf, i-1)          ← extern_id correct
                w4(dbuf, 0)            ← sig_id HARDCODED TO 0  ✗ BUG #2
                w4(dbuf, name...)
         │
         ▼
    → body i: CmdCall(target=BackCallExtern("lua_pushlstring"), args=[L, s, len])
         │
         ├─ target_id = b.func_map["lua_pushlstring"] → nil → 0  ✗ BUG #1
         │   (should be b.extern_map["lua_pushlstring"])
         │
         ▼
decode.rs: read_declarations
    → sig_types[0] = [I32, I32] (lua_createtable's params minus L)
      sig_types[1] = [ptr_ty, I64] (lua_pushlstring's params minus L) — never used!
    → externs[0] → declared with sig_types[0] = [I32, I32]
      externs[1] → declared with sig_types[0] = [I32, I32] (because sig_id=0 always)
      ...
    
    decode_body: CallExtern
    → eid = 0 (from BUG #1: target_id always 0)
    → refs.extern_refs[0] = lua_createtable's FuncRef with signature [ptr, I32, I32]
    → ctx.builder.ins().call(fr, [L, s, len])
    → Cranelift verifier: args 1 (s=ptr=I64) and 2 (len=index=I64) expected I32
```

## Observations

1. **Both bugs are in `back_command_binary.lua`**, the encoder. The decoder correctly processes whatever comes over the wire.

2. **Bug #2 (sig_id=0) is the PRIMARY cause** of the type mismatch. It causes all extern functions to have the same wrong signature (`[ptr, i32, i32]`). This is why all extern calls fail with "expected i32" — the first extern's signature happens to have i32 params.

3. **Bug #1 (func_map instead of extern_map) is a secondary issue** that makes all extern calls target the first extern. Without Bug #2, this would cause wrong-function-called bugs. With Bug #2, the symptom is the same — first extern's signature everywhere.

4. **The `st()` mapping is correct** — all 13 scalar type codes (1-13) are consistently mapped between Lua and Rust. The `clif_type()` method properly maps Ptr and Index to `ptr_ty` (I64 on 64-bit).

5. **The call site's sig_id field is irrelevant** — the decoder doesn't use it for extern calls. Cranelift gets the signature from the FuncRef (set during import declaration).

6. **The fix locations** are:
   - `back_command_binary.lua` line 680: change `w4(dbuf, 0)` to `w4(dbuf, sig_idx[id(cmd.sig)] or 0)`
   - `back_command_binary.lua` line 506: change `b.func_map[id(tgt.func)]` to `b.extern_map[id(tgt.func)]`

## Scout Output — 2026-05-19 00:28:14

Now I have comprehensive information. Let me compile the raw facts report.

---

## Raw Facts Report

## Files Retrieved

1. **`lua/lalin/tree_typecheck.lua`** (line 391) — Float literal type inference
2. **`lua/lalin/tree_control_to_back.lua`** (full, 371 lines) — Control region lowering
3. **`lua/lalin/tree_to_back.lua`** (full, 2558 lines) — Main lowering pipeline
4. **`lua/lalin/type_to_back_scalar.lua`** (full, ~60 lines) — Lalin type → BackScalar mapping
5. **`lua/lalin/back_command_binary.lua`** (lines 70-170) — Wire format encoder, `st()` function, `CmdAppendBlockParam` encoding
6. **`src/decode.rs`** (full, 303 lines) — Rust decoder, `st()`, `BodyCtx`, type mapping
7. **`lua/lalin/schema/back.lua`** — `CmdAppendBlockParam`, `CmdJump` schema
8. **`examples/json/json_lua_stack_decoder.mlua`** (full, ~340 lines) — JSON decoder
9. **`src/wire_tags.rs`** (referenced) — TAG_SLOTS

## Key Code

### 1. Float literal type inference: ALL LitFloat → f64 (tree_typecheck.lua:391)

```lua
if cls == C.LitInt then ty = i32_ty()
elseif cls == C.LitFloat then ty = f64_ty()  -- ALWAYS f64, NEVER f32
elseif cls == C.LitBool then ty = bool_ty()
```

**Fact**: The hosted typechecker unconditionally assigns every `LitFloat` the type `f64`. There is no context-dependent f32 inference. A float literal `0.1`, `10.0`, `0.0` is always `f64` at the semantic type level.

### 2. Type → BackScalar mapping faithfully preserves f32/f64 (type_to_back_scalar.lua:28-29)

```lua
[Core.ScalarF32] = function() return pvm.once(Back.BackF32) end,
[Core.ScalarF64] = function() return pvm.once(Back.BackF64) end,
```

And in `tree_to_back.lua:264-267`:
```lua
local function back_scalar(ty)
    local result = scalar_api.result(ty)
    if pvm.classof(result) == Ty.TypeBackScalarKnown then return result.scalar end
    return nil
end
```

**Fact**: The `back_scalar(ty)` function faithfully converts semantic types to `BackScalar`. A type `f64` → `Back.BackF64`, a type `f32` → `Back.BackF32`. Since all LitFloat are typed f64, they always map to `Back.BackF64`.

### 3. ExprLit lowering uses `back_scalar(expr_ty)` for the type (tree_to_back.lua:645-649)

```lua
[Tr.ExprLit] = function(self, env)
    local ty = expr_ty(self)
    local scalar = back_scalar(ty)
    if scalar == nil then return pvm.once(Tr.TreeBackExprUnsupported(...)) end
    local env2, dst = env_next_value(env, "v")
    return pvm.once(Tr.TreeBackExprValue(env2, { Back.CmdConst(dst, scalar, scalar_literal:one_uncached(self.value)) }, dst, scalar))
end
```

**Fact**: `CmdConst` is created with `scalar` = `Back.BackF64` for all float literal expressions. The literal value is a `BackLitFloat(raw)` — a string representation. There is no float-width in the literal itself; the width comes from the scalar type on the `CmdConst`.

### 4. MOM native path also hardcodes float literals as BackF64 (mom/back/expr_lower.mlua:111-113)

```lalin
let scalar: i32 = select(tok_kind == @{T.TK_TRUE} or tok_kind == @{T.TK_FALSE}, @{T.BackBool},
                   select(tok_kind == @{T.TK_FLOAT}, @{T.BackF64},   ← hardcoded BackF64
                          @{T.BackI32}))
```

**Fact**: Both hosted and MOM paths hardcode float literals as f64. There is no mechanism to produce f32 from a float literal in either pipeline.

### 5. Control region block params get their types from region declarations (tree_control_to_back.lua:97-107)

```lua
local function param_specs(nonce, region_id, label, params, is_entry)
    local specs = {}
    for i = 1, #params do
        local scalar = base.back_scalar(params[i].ty)
        if scalar == nil then return nil, "control block param has non-scalar type" end
        ...
        specs[#specs + 1] = {
            name = params[i].name,
            ty = params[i].ty,
            scalar = scalar,
            value = value_id(nonce, region_id, label, params[i].name),
            ...
        }
    end
    return specs, nil
end
```

**Fact**: Block param types come from the Lalin source's explicit type annotations (e.g., `i: i32`). The typed AST already has resolved types (from the typechecker), and `back_scalar()` converts them. For `parse_object`, all params are `i32`.

### 6. Region exit block gets its type from the function result (tree_control_to_back.lua:345-370)

```lua
local function lower_region(region, region_id, entry, blocks, result_scalar, env)
    ...
    local exit_block = synthetic_block_id(nonce, region_id, "exit")
    local exit_value = nil
    if result_scalar ~= nil then exit_value = synthetic_value_id(nonce, region_id, "result") end
    ...
    declare_blocks(cmds, records, exit_block, exit_value, result_scalar)
```

And the entry point for expression regions (tree_control_to_back.lua:75-81):
```lua
control_expr_region_to_back = pvm.phase(..., {
    [Tr.ControlExprRegion] = function(self, env)
        local scalar = base.back_scalar(self.result_ty)
        if scalar == nil then return ... end
        local lowered, err = lower_region(self, self.region_id, self.entry, self.blocks, scalar, env)
```

**Fact**: The exit block param type for a region expression comes from `back_scalar(self.result_ty)`. For `parse_object` which is `-> i32`, the exit block param is `Back.BackI32`.

### 7. `yield val` produces `CmdJump(ctx.exit_block, { value.value })` (tree_control_to_back.lua:111-118)

```lua
[Tr.StmtYieldValue] = function(self, env, ctx)
    ...
    local value = expr_value(base.expr_to_back:one_uncached(self.value, env))
    ...
    ctx.has_exit_jump = true
    local cmds = {}; append_all(cmds, value.cmds)
    cmds[#cmds + 1] = Back.CmdJump(ctx.exit_block, { value.value })
    return pvm.once(Tr.TreeBackStmtResult(value.env, cmds, Back.BackTerminates))
end
```

**Fact**: `yield val` jumps to the exit block with `value.value`. The type of `value` is the scalar attached to the `TreeBackExprValue`, which comes from `back_scalar(expr_ty(yield_value))`. For `yield -1`, the expression `-1` is typed `i32` → `Back.BackI32`.

### 8. The `CmdAppendBlockParam` encoder writes type code correctly (back_command_binary.lua:155-156)

```lua
elseif k == "CmdAppendBlockParam" then
    w4(buf, T.AppendBlockParam); w4(buf, b:nid(cmd.block)); w4(buf, st(cmd.ty)); w4(buf, b:nid(cmd.value))
```

**Fact**: The `st(cmd.ty)` function handles `BackShapeScalar` by looking up `S[s.scalar.kind]`. For `BackShapeScalar(Back.BackF32)` → `S["BackF32"]` = 10. For `BackShapeScalar(Back.BackF64)` → `S["BackF64"]` = 11. The fallback `S[s.kind]` handles plain `BackScalar` values (used by `CmdBindEntryParams` expansion path).

### 9. Rust decoder maps wire codes correctly to Cranelift types (decode.rs:43-56)

```rust
fn st(code: u32, ptr_ty: Type) -> Result<Type, LalinError> {
    let bs = match code {
        10 => BackScalar::F32,
        11 => BackScalar::F64,
        ...
    };
    Ok(bs.clif_type(ptr_ty))
}
```

And `clif_type()` (src/lib.rs:49-59):
```rust
Self::F32 => types::F32,
Self::F64 => types::F64,
```

**Fact**: Wire code 10 → `types::F32`. Wire code 11 → `types::F64`. The mapping is consistent with the Lua encoder.

### 10. `AppendBlockParam` decoder reads exactly 3 slots (decode.rs:249-253)

```rust
t if t == WireTag::AppendBlockParam as u32 => {
    let b = ctx.blk(s[0])?;          // block
    let ty = st(s[1], ptr_ty)?;      // type code
    let v = ctx.builder.append_block_param(b, ty);
    ctx.bind(s[2], v)?;              // value_id
}
```

`TAG_SLOTS[AppendBlockParam] = 3` matching exactly the 3 data slots the encoder writes (block_id, type_code, value_id).

### 11. Jump decoder verifies args against block params (decode.rs:380-386)

```rust
t if t == WireTag::Jump as u32 => {
    let dest = ctx.blk(s[0])?; let na = s[1] as usize;
    let ids = read_slots(buf, &mut pos, na)?;
    let args: Vec<BlockArg> = ids.iter().map(|&id| ctx.val(id).map(BlockArg::Value)).collect()?;
    ctx.builder.ins().jump(dest, &args);   // Cranelift verifies type match
}
```

**Fact**: `ctx.builder.ins().jump(dest, &args)` triggers Cranelift's verifier. If `block14` param 7 (0-indexed) expects f64 but `v1278` has type f32, Cranelift produces exactly the error message `arg v1278 has type f32, expected f64`.

## Type Flow Summary

```
Float literal "0.1" in source
    → tree_typecheck: LitFloat → f64_ty()     (ALWAYS f64)
    → tree_to_back.ExprLit: back_scalar(f64) → Back.BackF64
    → CmdConst(dst=vN, scalar=BackF64, value=BackLitFloat("0.1"))
    → encoder: st(shape_scalar(BackF64)) → wire code 11
    → decoder: st(11) → BackScalar::F64 → types::F64
    → Cranelift f64const(Ieee64)

Block param "i: i32" in source
    → typechecker: resolved to Ty.TScalar(Core.ScalarI32)
    → param_specs: back_scalar(i32_ty) → Back.BackI32
    → CmdAppendBlockParam(block, value, shape_scalar(BackI32))
    → encoder: st(shape_scalar(BackI32)) → wire code 4
    → decoder: st(4) → types::I32
    → Cranelift append_block_param(block, types::I32)

Region entry param init "i: i32 = pos"
    → lower_entry_jump: expr_to_back(pos) → back_scalar(pos.ty)
    → pos is i32 → BackI32
    → CmdJump(entry_block, {pos_value})
    → Cranelift verifies: entry_block param 0 is I32, arg is I32 ✓
```

## Relationships

### Where f32 could theoretically be produced

1. **Source-level `f32` type annotation**: A variable or param declared as `f32` would map through `back_scalar(f32)` → `Back.BackF32` → wire code 10 → `types::F32`. But `parse_object` has no f32 declarations.

2. **Intrinsics**: `CmdIntrinsic(Sqrt, shape_scalar(BackF32), args)` could produce f32. But `parse_object` uses no float intrinsics.

3. **Casts**: `CmdCast(Fdemote, BackF32, f64_val)` could convert f64 → f32. But `parse_object` has no casts.

4. **Extern call results**: `CmdCall(BackCallValue(dst, BackF32), ...)` could produce f32. But all externs in the JSON decoder use i32 or void results.

### How `parse_object` type flow looks (no floats anywhere in source):

```
parse_object params: L(voidp→BackPtr), p(ptr(u8)→BackPtr), n(i32→BackI32), pos(i32→BackI32), buf(ptr(u8)→BackPtr)
Return type: i32 → BackI32 → result_scalars = [BackI32]

All region blocks:
  start() → no params
  check_empty(i: i32) → i is BackI32
  parse_key(i: i32) → i is BackI32
  check_colon(next_i: i32) → next_i is BackI32
  check_colon_char(i: i32) → i is BackI32
  parse_val(i: i32) → i is BackI32
  check_comma(i: i32) → i is BackI32
  fail() → no params

All yield values: yield -1  → -1 is LitInt(i32) → BackI32
                   yield i + 1 → i+1 is i32 arithmetic → BackI32
                   yield next_i → BackI32 (next_i param type)
                   yield after_val → BackI32 (after_val is call result)
```

**Any f32 in parse_object would be a protocol-level corruption**, not a lowering-level type mismatch.

### The f32 could originate from `parse_value` (which uses `parse_number` with float operations)

If the block numbering assigns blocks from multiple function bodies consecutively (which Cranelift doesn't — each function has its own Block numbering), then... no, Cranelift blocks are per-function. `block14` is in function 2's namespace, not shared.

But `parse_value` is function 3 (or function 2, depending on indexing). In `parse_value`, `parse_number` is emitted inline, bringing float operations. After protocol desync, the decoder could:
1. Misread a float operation's destination value as having f32 type
2. Misread a block param type code as 10 (= f32) instead of 4 (= i32)
3. Misread a constant tag and create an f32 constant

## Observations

1. **No f32 is ever produced by float literals**: Both hosted and MOM paths hardcode float literals as f64. The only way to get f32 is through explicit f32 type annotations, f32 calls, f32 casts (fdemote), or wire-format desync.

2. **`parse_object` has zero float operations**: The region blocks use only i32 params. All extern calls pass i32/pointer args. There is no code path that would lower to an f32 Cranelift type.

3. **The f32 mismatch MUST come from a protocol desync**: In `parse_object` specifically, the only way to get `arg v1278 has type f32` is if the decoder misreads the wire format and interprets data as the wrong type tag (wire code 10 = f32 where code 4 = i32 was expected).

4. **`parse_value` uses floats**: Unlike `parse_object`, `parse_value` emits `parse_number` inline, which has f64 operations (`scale * 0.1`, `as(f64, ...)`, `result / 10.0`, etc.). A block desync that leaks from `parse_value` into `parse_object` is not possible (separate function bodies), but within `parse_value`'s own body, if a protocol desync occurs, it could produce f32 misreadings.

5. **The type flow from source → backend is correct for non-desynced code**: `LitFloat → f64 → BackF64 → wire code 11 → types::F64`, and `LitInt → i32 → BackI32 → wire code 4 → types::I32`. The mappings at every level are consistent. The bug is NOT in any of these individual mappings.
