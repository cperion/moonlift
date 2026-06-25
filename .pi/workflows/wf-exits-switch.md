# lalin.exits and lalin.switch_arms — Splice System Audit
Investigate splice fill dispatch and switch arm infrastructure for unified lalin.exits builder and lalin.switch_arms builder.
**Started**: 2026-05-19 20:53:45
---

## Scout Output — 2026-05-19 21:02:18

Now I have all the information needed. Here's the comprehensive report:

---

## Files Retrieved

### 1. `lua/lalin/host_splice.lua` (full file, 515 lines)
**The single coercion point** for splice-hole filling.
- **Top-level dispatch** (lines 64-86): `M.fill(session, slot, value, site, role, spread)` — the central dispatcher that routes to specific `fill_*` functions based on `role`. It also checks `pvm.classof(slot)` for non-list roles (SlotType, SlotExpr, SlotRegion, etc.).
- **Fill functions**: `fill_type`, `fill_expr`, `fill_expr_list`, `fill_type_list`, `fill_param_list`, `fill_field_list`, `fill_variant_list` (line 271), `fill_switch_stmt_arm_list` (line 294), `fill_switch_expr_arm_list`, `fill_open_param_list`, `fill_block_param_list`, `fill_entry_param_list`, `fill_cont_slot_list` (line 383), `fill_control_block_list`, `fill_region_body`, `fill_region_frag`, `fill_expr_frag`, `fill_name`.
- **Protocol dispatch** (lines 49-54): `protocol(value, role, session, site)` calls `value:lalin_splice(role, session, site)` — this is the polymorphic dispatch that allows a single value to respond differently to different roles.
- **Critical gap**: `fill_variant_list` and `fill_cont_slot_list` are completely separate functions that consume different SlotValue types (`SlotValueVariants` vs `SlotValueContSlots`). There is NO unified `ExitProtocol` that can serve both roles.

### 2. `lua/lalin/parse.lua` — Splice role determination
- **`record_splice_slot`** (line 605): records `{splice_id, splice_text, slot, role, spread}` — the `role` string is the sole discriminator.
- **`spread_expr_slot`** (line 616): creates `ExprSlot` with role, records as `SlotExpr`
- **`spread_type_slot`** (line 622): creates `TypeSlot` with role, records as `SlotType`
- **`spread_region_slot`** (line 628): creates `RegionSlot` with role, records as `SlotRegion` — used for `variant_list`, `cont_slot_list`, `switch_stmt_arm_list`, `switch_expr_arm_list`, `control_block_list`, `param_list`, `block_param_list`, `entry_param_list`, `open_param_list`, `field_list`
- **`spread_sentinel`** (line 634): creates placeholder AST nodes with `"__lalin_spread_" .. role .. ":" .. slot.key` as sentinel names

### 3. `lua/lalin/parse.lua` — Union and region cont parsing (key sections)
- **`parse_union_island`** (line 1871): Only handles SPREAD splices (`self:kind() == TK.hole and self.toks.splice_spread[self:text()]`). No non-spread value splice path for variant_list. The variant_list spread slot records as `role = "variant_list"`.
- **`parse_cont_params`** (line 1591): Handles BOTH spread and value splices. The spread check at line 1598 checks `self.toks.splice_spread`, then calls `self:splice_value(id)`. If value is a table, it iterates and creates ContSlot nodes directly (the "value splice" path). Falls through to spread sentinel only if value is nil. The cont_slot_list spread records as `role = "cont_slot_list"`.
- **`cont_slots_from_protocol`** (line 1669): Converts union variants into ContSlots by iterating `protocol_types[name]` and creating `ContSlot` from each `VariantDecl`. This is the bridge between union variants and region continuations.
- **`parse_switch_stmt`** (line 1078): Handles spread splices for `"switch_stmt_arm_list"` role.
- **`parse_switch_expr`** (line 1108): Handles spread splices for `"switch_expr_arm_list"` role.

### 4. `lua/lalin/schema/type.lua` — `VariantDecl`
```
A.product "VariantDecl" {
    A.field "name" "string",
    A.field "payload" "LalinType.Type",
    A.field "fields" (A.many "LalinType.FieldDecl"),
    A.unique,
},
```
- Has: `name`, `payload`, `fields` (typed fields, for record-style variants)
- NO `params` — uses `fields` for record variants, `payload` for payload variants

### 5. `lua/lalin/schema/open.lua` — `ContSlot`
```
A.product "ContSlot" {
    A.field "key" "string",
    A.field "pretty_name" "string",
    A.field "params" (A.many "LalinTree.BlockParam"),
    A.unique,
},
```
- Has: `key`, `pretty_name`, `params` (typed block params)
- Different from `VariantDecl`: uses `params` instead of `payload`/`fields`, has a `key` for identity

### 6. `lua/lalin/schema/tree.lua` — `BlockParam`, `SwitchStmtArm`, `SwitchExprArm`
```
A.product "BlockParam" {
    A.field "name" "string",
    A.field "ty" "LalinType.Type",
    A.unique,
},
A.product "SwitchStmtArm" {
    A.field "raw_key" "string",
    A.field "body" (A.many "LalinTree.Stmt"),
    A.unique,
},
A.product "SwitchExprArm" {
    A.field "raw_key" "string",
    A.field "body" (A.many "LalinTree.Stmt"),
    A.field "result" "LalinTree.Expr",
    A.unique,
},
```

### 7. `lua/lalin/schema/open.lua` — `SlotValue` variants
```
SlotValueVariants { variants (many VariantDecl) }     -- for variant_list
SlotValueContSlots { conts (many ContSlot) }           -- for cont_slot_list
SlotValueSwitchStmtArms { arms (many SwitchStmtArm) }  -- for switch_stmt_arm_list
SlotValueSwitchExprArms { arms (many SwitchExprArm) }  -- for switch_expr_arm_list
```

### 8. `lua/lalin/host_struct_values.lua` (lines 210-255)
**`api.variant(name, ty)`** — returns `{ kind="variant", name, type, decl=VariantDecl(name, ty.ty, {}) }`
**`api.variants(specs)`** — list builder (array of variants). Supports:
  - Array of specs: `lalin.variants{ {name="ok", payload=i32}, {name="err", payload=i64} }`
  - String-keyed map form: `lalin.variants{ ok = i32, err = i64 }`

### 9. `lua/lalin/host_region_values.lua` (lines 105-145)
**`api.entry_params(specs)`** — list builder returning `EntryBlockParam` array
**`api.cont(params)`** — single cont value `{ kind="cont", params, block_params }`
**`api.conts(specs)`** — returns a STRING-KEYED MAP `{ [name] = ContValue }` (unlike `variants` which returns an array)
**`api.blocks(specs)`** — returns array of `ControlBlock`

### 10. `lua/lalin/open_expand.lua` — Expansion phase
- **`expand_variants`** (line 169): Looks up `SlotValueVariants` and expands each variant's payload and fields
- **`expand_cont_slots`** (line 237): Looks up `SlotValueContSlots` and expands each cont's block params
- **`expand_switch_stmt_arms`** (line 302): Looks up `SlotValueSwitchStmtArms` and expands arms
- **`expand_switch_expr_arms`** (line 322): Looks up `SlotValueSwitchExprArms` and expands arms

### 11. `lua/lalin/host.lua` — Builder API surface
- `M.conts = api.conts` (line 179) — string-keyed map builder
- `M.variants = make_quote(parse_variants_quote, wrap_variants_quote, expand_variants_quote, api.variants)` (line 275) — quote+builder
- `M.blocks = api.blocks` (line 180) — list builder
- `M.entry_params = api.entry_params` (line 181) — list builder
- No `lalin.exits` or `lalin.switch_arms` exists

### 12. `examples/json/json_lua_stack_decoder.lua` — Switch arm usage
The `literal_arms` are built as plain Lua tables `{raw_key, body}`:
```lua
return {
    raw_key = tostring(bytes[1]),
    body = lalin.stmts(table.concat(lines, "\n")),
}
```
These are spread with `@{literal_arms...}` in switch context. The `as_switch_stmt_arm` function in host_splice.lua (line 291) duck-types: checks for `v.raw_key ~= nil and type(v.body) == "table"` and creates `SwitchStmtArm(raw_key, body)`.

### 13. `lua/lalin/host_region_values.lua` — `lalin_splice` protocol example
```lua
function RegionFragValue:lalin_splice(role, session, site)
    if role == "region_frag" then return self.frag end
    error((site or "splice") .. ": region fragment value cannot splice as " .. role, 2)
end
```
This is the pattern a unified `ExitProtocol` value would use to dispatch to `variant_list` vs `cont_slot_list`.

### 14. `tests/test_spread_splice_regions.lua` — conts usage pattern
Conts are constructed as raw tables and spread:
```lua
local conts = {
    {name="ok", params=lalin.params{ {name="pos", type=lalin.i32} }},
    {name="fail", params=lalin.params{ {name="code", type=lalin.i32} }},
}
return region scan(@{params...}; @{conts...})
```

---

## Key Code

### Dispatch chain for spread splices
```
Parser selects role (e.g., "variant_list")
  → record_splice_slot(id, SlotRegion, role)
  → host_splice.fill(session, slot, value, site, role, spread)
      → if role == "variant_list" → fill_variant_list() → SlotValueVariants
      → if role == "cont_slot_list" → fill_cont_slot_list() → SlotValueContSlots
  → open_expand replaces sentinel AST nodes with expanded values
```

### Value types and their shapes
```
VariantDecl: { name, payload: Type, fields: [FieldDecl] }     -- for unions
ContSlot:    { key, pretty_name, params: [BlockParam] }        -- for regions
BlockParam:  { name, ty: Type }                                -- cont/block params
FieldDecl:   { field_name, ty: Type }                          -- record variant fields

SwitchStmtArm: { raw_key: string, body: [Stmt] }
SwitchExprArm: { raw_key: string, body: [Stmt], result: Expr }
```

---

## Relationships

1. **Union variants ↔ region conts via protocol**: `Parser:cont_slots_from_protocol` (parse.lua:1669) converts `VariantDecl` → `ContSlot` by mapping `fields → params`. This is the existing bridge but it's parser-internal and only used for the `protocol: TypeName` syntax in region declarations.

2. **Splice role as sole discriminator**: The `role` string is the ONLY way the system knows what a value means. `fill_variant_list` and `fill_cont_slot_list` are identical in structure but produce different `SlotValue` variants. They could be unified if a new `ExitProtocol` value type self-dispatches via `lalin_splice(role)`.

3. **String-keyed vs list builders**: `api.variants` returns an ordered list. `api.conts` returns a string-keyed map `{[name]=ContValue}`. This asymmetry exists because unions need ordered variants (first variant = tag 0) while region conts are accessed by name. A unified `lalin.exits` would need to handle BOTH forms.

4. **Switch arms are duck-typed in host_splice but lack a builder**: The `as_switch_stmt_arm` and `as_switch_expr_arm` helpers in host_splice.lua accept `{raw_key, body}` tables. No `lalin.switch_arm` or `lalin.switch_arms` builder exists — arms are constructed manually like the JSON decoder does.

5. **Protocol method dispatch already exists**: `protocol(value, role, session, site)` in host_splice.lua calls `value:lalin_splice(role, session, site)`. A unified `ExitProtocol` value would implement this method to return `SlotValueVariants` for `"variant_list"` and `SlotValueContSlots` for `"cont_slot_list"`.

---

## Observations

### For `lalin.exits` unification:

**What exists today:**
- `api.variants(specs)` → ordered list of `{kind="variant", name, type, decl=VariantDecl}`
- `api.conts(specs)` → string-keyed map of `ContValue{kind="cont", params, block_params}`
- Both represent the same semantic shape: named typed exits
- The parser's `cont_slots_from_protocol` already bridges `VariantDecl → ContSlot`
- The `lalin_splice` protocol method already supports role-based dispatch
- `fill_variant_list` and `fill_cont_slot_list` in host_splice.lua are structurally identical (iterate table, coerce, produce SlotBinding)

**What would need to change:**
- **Schema level**: Create a `UnityExitDecl` type? Actually, NO — the ASDL types `VariantDecl` and `ContSlot` are already correct for their respective contexts. The unification is at the HOST VALUE level, not ASDL.
- **Host value level**: Create a new `ExitProtocol` metatable/value type with `lalin_splice(role, session, site)` that dispatches to produce the right SlotValue based on role. This value wraps the abstract "list of named typed exits" and materializes into `VariantDecl[]` or `ContSlot[]` depending on context.
- **host_splice level**: Add `fill_exit_protocol_list` or modify `fill_variant_list` and `fill_cont_slot_list` to also accept the `ExitProtocol` value via the protocol method. The existing `protocol()` helper already calls `lalin_splice`, so if the `ExitProtocol` value implements it, no change is needed here — except the protocol function must be called BEFORE the existing duck-typing.
- **Parser level**: No changes needed — the parser already correctly sets `role = "variant_list"` or `role = "cont_slot_list"` based on context, and the dispatch in host_splice.fill routes accordingly.
- **`api.exits(specs)`**: New builder that returns an `ExitProtocol` value capable of serving BOTH roles. Internally it constructs the abstract exit list.
- **Deprecation**: `api.variants` and `api.conts` become aliases to `api.exits` for backward compatibility.

**Difficulty assessment**: **Moderate**. The core dispatch mechanism already exists. The main work is:
1. Creating the `ExitProtocol` host value type with `lalin_splice` dispatching
2. Ensuring `fill_variant_list` and `fill_cont_slot_list` check for the protocol method
3. The `api.conts` is string-keyed while `api.variants` is list-based — need to decide the canonical shape
4. Updating tests

### For `lalin.switch_arms`:

**What exists today:**
- `as_switch_stmt_arm` and `as_switch_expr_arm` in host_splice.lua already accept duck-typed `{raw_key, body}` tables
- Switch arm lists are spread with `@{arms...}` in switch context
- The JSON decoder demonstrates the pattern: `literal_arms` as an array of `{raw_key, body}` tables
- No formal builder API — arms are constructed manually

**What would need to change:**
- **`api.switch_stmt_arm(raw_key, body)`**: Returns `SwitchStmtArm` ASDL node directly
- **`api.switch_expr_arm(raw_key, body, result)`**: Returns `SwitchExprArm` ASDL node directly
- **`api.switch_arms(arms)`**: Table builder that returns an array of switch arms
- **host_splice level**: Already works — `as_switch_stmt_arm` / `as_switch_expr_arm` already accept the ASDL types and duck-typed tables
- **Parser level**: No changes needed — already handles `@{arms...}` in switch with `switch_stmt_arm_list` / `switch_expr_arm_list` roles
- **Quoted form**: Could add `lalin.switch_arms[[case 32 then ...; case 10 then ...; default then ...]]` as a parse-and-wrap quote like `lalin.params` works

**Difficulty assessment**: **Trivial to moderate**. The infrastructure already exists — the only missing piece is the builder API on the `lalin` table. Add `api.switch_stmt_arm`, `api.switch_expr_arm`, `api.switch_arms` to `host_func_values.lua` or a new host file, then export from `host.lua` and `init.lua`. Optionally add a quote form for parsing switch arm source strings.

### Summary table

| Change | Level | Difficulty | Notes |
|--------|-------|------------|-------|
| `lalin.exits` value type | Host value | Moderate | New `ExitProtocol` metatable with `lalin_splice` dispatching |
| `lalin.exits` builder | host_struct/region_values | Moderate | Unify `api.variants` + `api.conts` → `api.exits` |
| Splice fill dispatch | host_splice.lua | Trivial | Protocol method already exists; just needs ExitProtocol to implement it |
| Parser roles | parse.lua | None | Already correct for variant_list/cont_slot_list |
| Schema types | schema/*.lua | None | ASDL types are correct as-is; unification is at host value level |
| `lalin.switch_arms` builder | host_values | Trivial | Already supported by host_splice duck-typing |
| `lalin.switch_arms` quote | host.lua | Trivial | Could add parse-and-wrap like lalin.params |
| Backward compat | host.lua | Trivial | Keep old names as aliases |
