# MWUI LSP Audit + Compiler Namespace Cleanup 
**Workflow ID**: wf-mwui-lsp-audit
**Started**: 2026-06-17 08:54:04
---

## Scout Output — 2026-06-17 08:59:14

Now I have all the data. Let me compile the complete picture:

---

## Files Retrieved

### 1. `lua/lalin/parse.lua` — Type parsing and name resolution at parse time

**`parse_type` function (lines 764-841)** — The main entry point for all type parsing:
```lua
function Parser:parse_type()
    -- 1. Hole/splice: @{type_value}
    if self:kind() == TK.hole then ... return Ty.TSlot(slot) end
    -- 2. Array: [N]T
    -- 3. view(T), lease(T), handle(T, repr), func(...), closure(...)
    -- 4. Bare name — prefix check for ptr(T)
    local name = self:expect_name("expected type")
    if name == "ptr" and self:accept(TK.lparen) then ... return Ty.TPtr(elem) end
    -- 5. Qualified path: A.B.C
    if self:kind() == TK.dot then ... return Ty.TNamed(Ty.TypeRefPath(...)) end
    -- 6. Bare name → delegate to type_name
    return self:type_name(name)
end
```

**`type_name` function (lines 713-722)** — Where scalar names and ambient Lua types are resolved:
```lua
function Parser:type_name(name)
    local C, Ty = self.C, self.Ty
    local m = { void=C.ScalarVoid, bool=C.ScalarBool, i8=C.ScalarI8, ...,
        index=C.ScalarIndex, ptr=C.ScalarRawPtr }
    if m[name] then return Ty.TScalar(m[name]) end           -- ← BUILT-IN SCALARS
    local ambient = self:type_from_value(self:splice_value(name))  -- ← AMBIENT LUA VALUE
    if ambient ~= nil then return ambient end
    return Ty.TNamed(Ty.TypeRefPath(C.Path({ C.Name(name) })))  -- ← UNRESOLVED BARE NAME
end
```

**Key insight**: There are exactly 3 resolution tiers for a bare name:
1. Built-in scalars (void, bool, i8-64, u8-64, f32, f64, index, ptr)
2. Ambient Lua values registered in the session (via `splice_value` → `type_from_value`)
3. **Fallback**: Creates `Ty.TNamed(Ty.TypeRefPath(...))` — an unresolved path that the typechecker later resolves

**Where ambient Lua values come from** — `type_from_value` (lines 700-711):
```lua
function Parser:type_from_value(v)
    if type(v) == "table" then
        if type(v.as_lalin_type) == "function" then return v:as_lalin_type() end
        if type(v.as_type_value) == "function" then ... end
        if v.ty ~= nil and (v.__lalin_host_type_value or ...) then return v.ty end
    end
    return nil
end
```
This means `@{T.SomeType}` works when `T.SomeType` is a LalinType host value (from `lalin.struct`, `lalin.handle`, etc.) loaded into the Lua global scope. The `splice_value` check (line 668-671) looks up the ambient splice map.

**`splice_value` (lines 668-671)**:
```lua
function Parser:splice_value(id)
    local rec = self.splice_values and self.splice_values[id]
    if type(rec) == "table" and rec.present then return rec.value end
    return rec
end
```

### 2. `lua/lalin/parse.lua` — Where types are registered during struct/union parsing

**`parse_struct_island` (lines 2043-2088)** — When parsing `struct RingBuf ... end`:
```lua
function Parser:parse_struct_island()
    ...
    self.product_types[name] = fields   -- line 2080
    return { name = name, decl = Tr.TypeDeclStruct(name, fields), ... }
end
```

**`parse_union_island` (lines 2094-2168)**:
```lua
    self.protocol_types[name] = variants  -- line 2155
```

**CRITICAL**: `self.product_types[name]` and `self.protocol_types[name]` are **NOT used for type name resolution**. They are only used for **product-type parameter expansion** (lines 1664, 1887) — when a struct name appears in a parameter list without `:`, its fields are expanded as individual parameters.

**`parse_module_document` (lines 2711-2752)** — Propagates `product_types` and `protocol_types` across islands:
```lua
    local protocol_types = opts.protocol_types or {}
    local product_types = opts.product_types or {}
    for i = 1, #scan.islands do
        local parsed = M.parse_island(T, scan, i, {
            protocol_types = protocol_types, product_types = product_types })
        protocol_types = parsed.protocol_types or protocol_types  -- propagate
        product_types = parsed.product_types or product_types      -- propagate
        ...
    end
```

### 3. `lua/lalin/tree_typecheck.lua` — Where bare names are actually resolved at typecheck time

**`canonical_type` (lines 103-127)** — The core resolution function:
```lua
canonical_type = function(env, ty)
    local cls = pvm.classof(ty)
    if cls == Ty.TNamed and pvm.classof(ty.ref) == Ty.TypeRefPath
       and #ty.ref.path.parts == 1 then
        return env_lookup_type(env, ty.ref.path.parts[1].text) or ty  -- ← LOOKUP
    elseif cls == Ty.THandle and pvm.classof(ty.ref) == Ty.TypeRefPath
           and #ty.ref.path.parts == 1 then
        local found = env_lookup_type(env, ty.ref.path.parts[1].text)
        if found ~= nil and pvm.classof(found) == Ty.THandle then return found end
        return ty
    ...
end
```

**`env_lookup_type` (lines 96-100)** — Searches env.types for a matching name:
```lua
local function env_lookup_type(env, name)
    for i = #env.types, 1, -1 do
        if env.types[i].name == name then return env.types[i].ty end
    end
    return nil
end
```

**Where `env.types` is populated** — `tree_module_type.lua` `module_env` phase (lines 185-212):
```lua
module_env = pvm.phase("lalin_tree_module_env", {
    [Tr.Module] = function(module, target)
        ...
        local types = {}
        for i = 1, #module.items do
            local entries = pvm.drain(item_env_entries(module.items[i], mod_name))
            for j = 1, #entries do
                if pvm.classof(entries[j]) == B.TypeEntry then
                    types[#types + 1] = entries[j]
                end
            end
        end
        ...
        return pvm.once(B.Env(mod_name, values, types, layouts))
    end,
})
```

**`type_entry` in `tree_module_type.lua` (lines 70-81)** — How each type decl creates an env entry:
```lua
type_entry = pvm.phase("lalin_tree_type_entry", {
    [Tr.TypeDeclStruct] = function(self, mod_name)
        return pvm.once(B.TypeEntry(self.name,
            Ty.TNamed(Ty.TypeRefGlobal(mod_name, self.name))))  -- ← GLOBAL REF
    end,
    [Tr.TypeDeclUnion] = function(self, mod_name)
        return pvm.once(B.TypeEntry(self.name,
            Ty.TNamed(Ty.TypeRefGlobal(mod_name, self.name))))
    end,
    [Tr.TypeDeclHandle] = function(self, mod_name)
        return pvm.once(B.TypeEntry(self.name,
            Ty.THandle(Ty.TypeRefGlobal(mod_name, self.name), self.repr)))
    end,
    ...
})
```

**`type_module_with_layout_env` (lines 1470-1477)** — Where everything ties together:
```lua
local function type_module_with_layout_env(module, extra_layout_env, target)
    local base_env = module_type_api.env(module, target)  -- builds env.types
    attach_semantic_defs(base_env,
        build_variant_defs(module, base_env.module_name),
        build_handle_defs(module, base_env.module_name),
        build_func_effect_defs(module))
    local module_env = merge_env_layouts(base_env, extra_layout_env)
    ...
end
```

**Variant defs / handle defs** — Also resolve bare names:
- `build_variant_defs` (lines 362-392): builds `defs[name]` for tagged unions
- `build_handle_defs` (lines 394-410): builds `defs[name]` for handles
- Resolution via `variant_def_for_value_ty` (lines 474-480):
  ```lua
  if rcls == Ty.TypeRefPath and #ref.path.parts == 1 then
      return defs[ref.path.parts[1].text]
  end
  ```

**Unresolved path error** (lines 941-947):
```lua
if pvm.classof(ref) == Ty.TypeRefPath then
    issues[#issues + 1] = Tr.TypeIssueUnresolvedPath(ref.path)
```

### 4. `lua/lalin/schema/type.asdl` — ASDL type definitions

Lines 2-4 and 28:
```
TypeRef = TypeRefPath(LalinCore.Path path) unique
     | TypeRefGlobal(string module_name, string type_name) unique
     | TypeRefLocal(LalinCore.TypeSym sym) unique

Type = ... | TNamed(LalinType.TypeRef ref) unique | ...
```

The resolution path is:
- **Parse time**: bare name → `Ty.TNamed(Ty.TypeRefPath({C.Name("RingBuf")}))`
- **Typecheck time**: `canonical_type` matches `TypeRefPath` with 1 part → `env_lookup_type` → finds `B.TypeEntry("RingBuf", Ty.TNamed(Ty.TypeRefGlobal("", "RingBuf")))` → returns the global-ref type

### 5. `lua/lalin/host_type_values.lua` — Scalar type values registered as ambient Lua values

Lines 88-96:
```lua
scalar("void", C.ScalarVoid)
scalar("bool", C.ScalarBool)
scalar("i8", C.ScalarI8) ... scalar("u64", C.ScalarU64)
scalar("f32", C.ScalarF32); scalar("f64", C.ScalarF64)
scalar("index", C.ScalarIndex)
api.rawptr = type_value(Ty.TScalar(C.ScalarRawPtr), "ptr(void)")
```

These are registered on the `lalin` API table (e.g., `lalin.i32` is a TypeValue). When you write `@{lalin.i32}` in a type position, the parser calls `type_from_value(splice_value("lalin.i32"))` which finds the ambient Lua value.

### 6. `lua/lalin/host_splice.lua` — Splice type resolution

Lines 97-127 — `fill_type` for `@{}` type splices:
```lua
function M.fill_type(session, slot, value, site)
    -- 1. Protocol method (TypeValue returns self.ty)
    local p = protocol(value, "type", session, site)  -- calls lalin_splice("type")
    -- 2. Duck-typed: as_type_value()
    -- 3. Raw ASDL type node passed directly
    ...
    return O.SlotBinding(O.SlotType(slot), O.SlotValueType(ty))
end
```

### 7. `lua/lalin/frontend_pipeline.lua` — Full pipeline assembly

Lines 243-260 — `parse_and_lower` calls parse then typecheck:
```lua
local parsed = Parse.parse_module(src, { collector = collector })
...
local checked = Typecheck.check_module(closed, { ... })
```

### 8. Example .mlua files

**`stdlib/arena.mlua`** (lines 1-38):
- `struct Arena ... end` declares "Arena" → parse creates `TypeRefPath("Arena")`, typecheck resolves via `env.types`
- `func arena_new(size: index): Arena` — "Arena" as return type → bare name resolved by typechecker
- `func arena_alloc(a: ptr(Arena), ...)` — "Arena" inside `ptr(...)` → bare name resolved by typechecker

**`daw_lalin_type_cfg_design_v3.mlua`** (lines 1-100+):
- Dozens of structs/unions defined, then used as bare names in field positions
- `value: TextRef`, `severity: IssueSeverity`, `issues: view(Issue)` — all bare names

---

## Key Code

### The resolution flow (end-to-end):

```
.mlua source: struct RingBuf ... end
                    │
                    ▼
parse_struct_island() → Tr.TypeDeclStruct("RingBuf", fields)
  + self.product_types["RingBuf"] = fields  ← NOT for name resolution!
                    │
                    ▼
parse_module_document → Tr.Module(Tr.ModuleSurface, items)
  where items[1] = Tr.ItemType(Tr.TypeDeclStruct("RingBuf", ...))
                    │
                    ▼
type_module_with_layout_env() → builds env.types:
  type_entry(Tr.TypeDeclStruct("RingBuf")) → B.TypeEntry("RingBuf",
    Ty.TNamed(Ty.TypeRefGlobal("", "RingBuf")))
                    │
                    ▼
Now parsing field `rx: RingBuf`:
  parse_type() → type_name("RingBuf")
    → not scalar, not ambient → Ty.TNamed(Ty.TypeRefPath({Name("RingBuf")}))
                    │
                    ▼
typecheck: canonical_type(env, Ty.TNamed(Ty.TypeRefPath({Name("RingBuf")})))
  → env_lookup_type(env, "RingBuf") → finds B.TypeEntry("RingBuf", ...)
  → returns Ty.TNamed(Ty.TypeRefGlobal("", "RingBuf"))
```

### The 3-tier name resolution in `type_name`:

| Tier | Example names | Resolution |
|------|--------------|------------|
| 1. Built-in scalars | `void`, `bool`, `i8`-`i64`, `u8`-`u64`, `f32`, `f64`, `index`, `ptr` | Returns `Ty.TScalar(...)` |
| 2. Ambient Lua values | `@{T.RingBuf}` | `splice_value` → `type_from_value` → `v:as_lalin_type()` |
| 3. Unresolved bare name | `RingBuf`, `Arena`, `IssueSeverity` | Returns `Ty.TNamed(Ty.TypeRefPath(...))` — resolved later by typechecker |

### The typechecker's resolution in `canonical_type`:

| Ref type | Resolution |
|----------|-----------|
| `TypeRefPath` with 1 part | `env_lookup_type(env, name)` — searches `env.types` |
| `TypeRefPath` with N parts | Not resolved (returns `ty` unchanged) |
| `TypeRefGlobal` | Already resolved (used by host types, not .mlua types) |
| `TypeRefLocal` | Already resolved (used for open types) |

---

## Relationships

1. **Parse-time vs. typecheck-time resolution split**: The parser intentionally defers bare-name resolution to the typechecker. It creates a `TypeRefPath` with the bare name as a single-element path. The typechecker's `canonical_type` and `env_lookup_type` resolve it against `env.types`. This is the "hidden namespace."

2. **`product_types` is a red herring for name resolution**: Despite its name, `self.product_types[name] = fields` is set during struct parsing but only used for parameter-list product-type expansion — NOT for field type resolution.

3. **Three separate def mechanisms in the typechecker**:
   - `env.types` (from `type_entry`): struct, union, handle, open struct/union
   - `__variant_defs` (from `build_variant_defs`): enum/tagged-union variant info
   - `__handle_defs` (from `build_handle_defs`): handle representation info

4. **LSP completion** (`editor_completion_items.lua` line 58) lists `.mlua`-declared types via `add_tree_types` which iterates `analysis.parse.combined.module.items` for `Tr.ItemType`. This is independent of the hidden namespace resolution.

5. **Host types vs. .mlua types**: Host types (from Lua `lalin.struct{...}`) produce `TypeRefGlobal` or `TypeRefLocal` which are already fully resolved. .mlua types produce `TypeRefPath` at parse time and are resolved to `TypeRefGlobal` during typechecking.

---

## Observations

1. **The hidden namespace is the typechecker's `env.types`**. To disable it: the parser's `type_name` would need to stop falling through to `Ty.TNamed(Ty.TypeRefPath(...))` for bare names that aren't built-in scalars. Instead, it should either (a) error, or (b) only accept `@{lua_expr}` splices for user-defined types.

2. **All .mlua files rely on this**. Every field declaration like `rx: RingBuf`, `value: TextRef`, `severity: IssueSeverity` in existing .mlua files depends on tier 3 fallback resolution.

3. **The parser does NOT maintain a type namespace**. The `product_types`/`protocol_types` tables are only for product-type parameter expansion. Name resolution is entirely a typechecker concern via `canonical_type` → `env_lookup_type`.

4. **`ptr` is special**: In `parse_type`, `ptr` is checked as a prefix BEFORE `type_name` is called (line 827). But `type_name` also maps `ptr` → `ScalarRawPtr` for standalone use. The standalone `ptr` (as a scalar, not `ptr(T)`) is in the built-in map but may not be commonly used.

5. **Disabling the hidden namespace would require**: Every user-defined type in .mlua files would need to be provided via `@{...}` splices. This means either:
   - Loading types into Lua global scope (e.g., `local RingBuf = ...` then `@{RingBuf}`)
   - Using a module path (e.g., `@{mymod.RingBuf}`)
   - The parser would need to reject bare non-scalar names (tier 3), possibly with a clear error message.

6. **The `splice_value` mechanism already exists** to support `@{expr}` in type position. The pipe from Lua host values to parser type slots works via `host_splice.lua` → `fill_type` → `as_type_value().ty`.

## Scout Output — 2026-06-17 10:12:29

Here is the complete survey of all `@{...}` hole sites in `parse.lua`:

---

## Files Retrieved

**`lua/lalin/parse.lua`** — 2877 lines. This is the only file. All hole sites live here.

---

## Key Code

### 1. TYPE POSITION — `parse_type` (lines 764–841)

**Two kinds of hole/splice for types:**

**1a. Explicit `@{expr}` hole** (lines 768–773):
```lua
-- Hole: @{type_value}
if self:kind() == TK.hole then
    local id = self:text(); self.i = self.i + 1
    local slot = O.TypeSlot(self:splice_key("type", id), id)
    self:record_splice_slot(id, O.SlotType(slot), "type")
    return Ty.TSlot(slot)
end
```
This creates a `TypeSlot` — the parser's ASDL node for a deferred type resolution. The slot's key is `"splice:type:<id>"`.

**1b. Dotted qualified path** (lines 828–837):
```lua
-- Qualified path: A.B.C — evaluate as Lua splice (the Lua environment IS the namespace).
if self:kind() == TK.dot then
    local parts = { name }
    while self:accept(TK.dot) do parts[#parts + 1] = self:expect_name("expected qualified type field") end
    local expr = table.concat(parts, ".")
    local slot = O.TypeSlot(self:splice_key("type", expr), expr)
    self:record_splice_slot(expr, O.SlotType(slot), "type")
    return Ty.TSlot(slot)
end
```
**Critical**: Any `A.B.C` in type position is treated as a Lua splice — it joins with `"."` and creates a `TypeSlot`. This is already direct Lua evaluation without `@{}`. The comment even says "the Lua environment IS the namespace."

**1c. Bare name fallback** — `type_name` (lines 713–722):
```lua
function Parser:type_name(name)
    ...
    if m[name] then return Ty.TScalar(m[name]) end       -- built-in scalars
    local ambient = self:type_from_value(self:splice_value(name))  -- ambient Lua value
    if ambient ~= nil then return ambient end
    return Ty.TNamed(Ty.TypeRefPath(C.Path({ C.Name(name) })))  -- unresolved bare name
end
```
Bare scalar names (`void`, `bool`, `i8`, etc.) are hardcoded. Ambient Lua values use `splice_value` (the pre-loaded splice map populated by `@{...}` at the module document level — NOT the lexical `@{...}` in type position). If neither matches, it creates an unresolved `TypeRefPath` that the typechecker later resolves via its `env.types` hidden namespace.

| Aspect | Detail |
|--------|--------|
| Bare name accepted? | **Yes** — via tier 3 fallback (unresolved `TypeRefPath`) |
| Dotted name accepted? | **Yes** — parsed as dotted path → becomes `TypeSlot` (Lua splice) |
| Hole the only way? | **No** — dotted names already bypass `@{}` |
| Difficulty to eliminate `@{}` from type position | **Trivial** — dotted names already work as direct Lua expressions. Bare names need a decision: either (a) force all user types through ambient Lua values (tier 2), (b) error on bare non-scalar names, or (c) treat bare names as Lua expressions too. |

---

### 2. FRAGMENT POSITION — `parse_region_frag_ref` / `parse_expr_frag_ref` (lines 1424–1442)

These are called by `parse_emit_stmt`, `parse_call_stmt`, and `parse_emit_expr`.

**Region fragment reference** (lines 1424–1433):
```lua
function Parser:parse_region_frag_ref(keyword)
    local O = self.O
    if self:kind() == TK.hole then
        local id = self:text(); self.i = self.i + 1
        local slot = O.RegionFragSlot(self:splice_key("region_frag", id), id)
        self:record_splice_slot(id, O.SlotRegionFrag(slot), "region_frag")
        return O.RegionFragRefSlot(slot), "@" .. id
    end
    local name = self:expect_name("expected region fragment name after " .. (keyword or "emit/call"))
    return O.RegionFragRefName(name), name
end
```

**Expression fragment reference** (lines 1435–1442):
```lua
function Parser:parse_expr_frag_ref()
    local O = self.O
    if self:kind() == TK.hole then
        local id = self:text(); self.i = self.i + 1
        local slot = O.ExprFragSlot(self:splice_key("expr_frag", id), id)
        self:record_splice_slot(id, O.SlotExprFrag(slot), "expr_frag")
        return O.ExprFragRefSlot(slot), "splice." .. id
    end
    local name = self:expect_name("expected expression fragment name after emit")
    return O.ExprFragRefName(name), name
end
```

| Aspect | Detail |
|--------|--------|
| Bare name accepted? | **Yes** — `emit fragName(...)` / `call someRegion(...)` |
| Dotted name accepted? | **No** — only `TK.name` or `TK.hole`. `A.B` would be a name squashed into `A` then `.` would be unexpected. |
| Hole the only way? | Hole is the only way to pass a **Lua variable or module path** as a fragment reference |
| Difficulty to extend | **Easy** — add a dotted-path branch (like `parse_type` does at lines 828–837): read dotted names, join with `"."`, treat as Lua expression. Same pattern as type-position dotted names. |

---

### 3. NAME POSITION — island/declaration names

Two distinct functions control name acceptance:

**3a. `name_or_hint_before_lparen`** (lines 599–608) — used by `parse_extern`, `parse_func`:
```lua
function Parser:name_or_hint_before_lparen(msg)
    if self:kind() == TK.lparen then
        if self.name_hint then return self.name_hint end
        self.anonymous = true
        return "_anon_" .. tostring(self.anon_counter)
    end
    return self:expect_name(msg)
end
```
**NO hole support.** Only accepts `TK.name` or anonymous. Extern and func names CANNOT be `@{...}` holes. This means an extern declared as `extern @{SomeLuaVar}(...) end` would not parse. Users must use `name_hint` (Lua assignment inference) for dynamic names.

**3b. `name_ref_or_hint_before_lparen`** (lines 610–625) — used by `parse_region_frag`, `parse_expr_frag`:
```lua
function Parser:name_ref_or_hint_before_lparen(msg)
    local O = self.O
    if self:kind() == TK.lparen then
        if self.name_hint then return O.NameRefText(self.name_hint) end
        self.anonymous = true
        return O.NameRefText("_anon_" .. tostring(self.anon_counter))
    end
    if self:kind() == TK.hole then
        local id = self:text(); self.i = self.i + 1
        local slot = O.NameSlot(self:splice_key("name", id), id)
        self:record_splice_slot(id, O.SlotName(slot), "name")
        return O.NameRefSlot(slot)
    end
    return O.NameRefText(self:expect_name(msg))
end
```
**HOLE SUPPORTED.** Region and expression fragment names CAN be `@{lua_expr}` — this creates a `NameRefSlot`. The output is an `O.NameRefText` or `O.NameRefSlot`.

**3c. Struct/union/handle names** — NO dedicated name-ref function. Each island has its own inline logic:

- **`parse_struct_island`** (lines 2044–2087): `name = self:expect_name(...)`, NO hole. Only `TK.name` or `name_hint`/anonymous.
- **`parse_union_island`** (lines 2091–2162): `name = self:expect_name(...)`, NO hole. Only `TK.name` or `name_hint`/anonymous.
- **`parse_handle_island`** (lines 2164–2191): `name = self:expect_name(...)`, NO hole. Only `TK.name` or `name_hint`.

| Position | Function | Hole OK? | Bare name? | Dotted name? |
|----------|----------|----------|------------|--------------|
| `func` / `extern` | `name_or_hint_before_lparen` | **No** | Yes | No |
| `region` / `expr frag` | `name_ref_or_hint_before_lparen` | **Yes** | Yes | No |
| `struct` | inline logic | **No** | Yes | No |
| `union` | inline logic | **No** | Yes | No |
| `handle` | inline logic | **No** | Yes | No |

**Difficulty to extend to dotted/expression names**: For `name_ref_or_hint_before_lparen` (which already has hole support), adding dotted-name support would be the same pattern as `parse_type` line 828 — read dotted names as a Lua expression path. For the others (`name_or_hint_before_lparen`, struct/union/handle), the question is whether they should support dynamic names at all. Currently they don't even have hole support.

---

### 4. EXPRESSION POSITION — `nud()` (lines 876–885)

```lua
function Parser:nud()
    ...
    -- Hole: @{expr_value}
    if k == TK.hole then
        local slot = O.ExprSlot(self:splice_key("expr", text), text, nil)
        self:record_splice_slot(text, O.SlotExpr(slot), "expr")
        return Tr.ExprSlotValue(Tr.ExprSurface, slot)
    end
    ...
```
This is the **only** way to embed a Lua value in an expression position. The parser creates an `ExprSlotValue`. There is no dotted-name path for expressions.

| Aspect | Detail |
|--------|--------|
| Bare name accepted? | Only as a binding reference (`Tr.ExprRef`) — this refers to Lalin variables (SSA values), not Lua values |
| Dotted name accepted? | **No** — `led()` handles `TK.dot` as field access on an existing expression (dot operator), not as a Lua module path |
| Hole the only way? | **Yes** — `@{expr}` is the sole mechanism for embedding Lua values in expressions |
| Difficulty to extend | **Medium**. You'd need to add a prefix check in `nud()`: if a name (or dotted name sequence) is encountered but NOT found in `self.value_env`, fall through to Lua evaluation (like type position dotted-names). But this creates ambiguity: is `some_var` a Lalin binding or a Lua module reference? |

---

### 5. SPREAD POSITIONS — `@{...}` in lists

The spread flag is set by the lexer when the Lua expression inside `@{...}` ends with `...`:

```lua
-- line 174-178
local function split_splice_expr(lua_expr)
    local stripped = lua_expr:match("^(.-%S)%s*%.%.%.%s*$")
    if stripped then return stripped, true end
    return lua_expr, false
end
```

So `@{my_list...}` produces `splice_spread[id] = true`.

**All spread sites (15 total in parse.lua):**

| Line | Context | Role | What it creates |
|------|---------|------|-----------------|
| 731 | `parse_callable_type` param list | `"type_list"` | `Ty.TSlot(spread_type_slot)` |
| 1032 | Function call args (`led` for `TK.lparen`) | `"expr_list"` | `Tr.ExprSlotValue` |
| 1211 | `parse_switch_stmt` arm list | `"switch_stmt_arm_list"` | `Tr.SwitchStmtArm(sentinel, {})` |
| 1249 | `parse_switch_expr` arm list | `"switch_expr_arm_list"` | `Tr.SwitchExprArm(sentinel, {}, lit0)` |
| 1330 | `parse_multi_control_expr` block list | `"control_block_list"` | `Tr.ControlBlock(sentinel, {}, {})` |
| 1370 | `parse_block_params` (entry/block) | `"entry_param_list"` / `"block_param_list"` | `EntryBlockParam` or `BlockParam` with sentinel |
| 1455 | `parse_region_use_stmt` emit/call args | `"expr_list"` | `Tr.ExprSlotValue` |
| 1506 | `parse_emit_expr` args | `"expr_list"` | `Tr.ExprSlotValue` |
| 1677 | `parse_param_list` (func/extern params) | `"param_list"` | `Ty.Param(sentinel, void)` |
| 1779 | `parse_cont_params` inner (cont param block params) | `"block_param_list"` | `Tr.BlockParam(sentinel, void)` |
| 1798 | `parse_cont_params` outer (cont slot spread) | `"cont_slot_list"` | `O.ContSlot(sentinel, sentinel, {})` — or inspects value table for structured objects |
| 1901 | `parse_open_params` (region/expr frag params) | `"open_param_list"` | `O.OpenParam(sentinel, sentinel, void)` — or inspects value table |
| 1997 | `parse_region_frag` block list | `"control_block_list"` | `Tr.ControlBlock(sentinel, {}, {})` |
| 2060 | `parse_struct_island` field list | `"field_list"` | `Ty.FieldDecl(sentinel, void)` |
| 2114 | `parse_union_island` variant list | `"variant_list"` | `Ty.VariantDecl(sentinel, void, {})` |

**Plus one non-spread statement-position hole** (line 1555):
```lua
if self:kind() == TK.hole then
    local id = self:text(); self.i = self.i + 1
    local slot = self.O.RegionSlot(self:splice_key("region_body", id), id)
    self:record_splice_slot(id, self.O.SlotRegion(slot), "region_body")
    return Tr.StmtUseRegionSlot(Tr.StmtSurface, slot)
end
```
This is for splicing region body statements (e.g., `@{body_stmts}` in statement position). NOT a spread — it's a single-hole replacement.

### The `splice_value` pipeline (lines 668–711)

All hole resolution eventually delegates to `splice_value`:
```lua
function Parser:splice_value(id)
    local rec = self.splice_values and self.splice_values[id]
    if type(rec) == "table" and rec.present then return rec.value end
    return rec
end
```
This looks up the pre-loaded splice map — built during module document scanning by evaluating `@{...}` Lua expressions. The `splice_values` table maps splice IDs to Lua values.

---

## Relationships — Complete Data Flow

```
Source text:  func @{name}(...): @{ret_ty} ... @{stuff...} ...
                    │
                    ▼
┌─ LEXER (tokenize) ──────────────────────────────────────────────────────────┐
│  '@{name}' → TK.hole "splice.1", splice_map["splice.1"] = "name"            │
│  '@{stuff...}' → TK.hole "splice.2", splice_spread["splice.2"] = true      │
│  '@{ret_ty}' → TK.hole "splice.3", splice_map["splice.3"] = "ret_ty"       │
└─────────────────────────────────────────────────────────────────────────────┘
                    │
                    ▼
┌─ SCANNER (scan_document) ───────────────────────────────────────────────────┐
│  Identifies islands, collects holes[] for each island                       │
│  Calls external code to evaluate @{...} Lua expressions                    │
│  Populates splice_values map: {"splice.1" → Lua_value, ...}                │
└─────────────────────────────────────────────────────────────────────────────┘
                    │
                    ▼
┌─ PARSER (parse_island) ─────────────────────────────────────────────────────┐
│  Receives pre-filled splice_values                                         │
│  For each TK.hole, creates an ASDL slot node (deferred resolution):         │
│    - TypeSlot (type position)                                               │
│    - ExprSlot (expression position)                                         │
│    - NameSlot (name position, region/expr frag)                             │
│    - RegionFragSlot (region use)                                            │
│    - ExprFragSlot (expr frag use)                                           │
│    - RegionSlot (statement/body splice)                                     │
│  These slots carry keys like "splice:type:splice.3"                         │
│  The actual Lua value (via splice_value) is used at fill time in           │
│    host_splice.lua → fill_type / fill_expr / fill_region_frag / etc.       │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Observations

1. **Dotted names in type position already bypass `@{}`**. Lines 828–837 treat `A.B.C` in type position as a Lua splice. This is the exact mechanism that would need to be replicated for fragment and name positions. The pattern is: read dotted name sequence → `table.concat(parts, ".")` → create a slot with the expression as the lookup key.

2. **The two name-ref functions are inconsistent**. `name_ref_or_hint_before_lparen` (region/expr frag) supports holes but not dotted names. `name_or_hint_before_lparen` (func/extern) supports neither. Struct/union/handle have inline logic with neither. To eliminate `@{}` from name positions consistently, all name-accepting sites would need dotted-path parsing.

3. **Expression position is the hardest**. The parser currently uses `self.value_env` to distinguish Lalin bindings from Lua values. A bare name like `foo` is either a SSA value reference or a Lua module reference — there's an ambiguity. Dotted names (`a.b.c`) are unambiguous since they can't be Lalin bindings. But the `led` already consumes `TK.dot` as field access, so a dotted path in expression position would need lexer-level disambiguation or a prefix check in `nud()`.

4. **Spread values sometimes inspect the Lua value table**. Notably `parse_cont_params` (line 1798) and `parse_open_params` (line 1901) have two code paths: if `splice_value(id)` returns a table, they iterate it and extract structured ASDL objects (`ContSlot`, `Param`, etc). If not a table, they create a sentinel placeholder. This means the spread mechanism already handles structured Lua data.

5. **Func/extern names have NO hole support at all**. This is by design — `name_or_hint_before_lparen` only accepts `TK.name`. Dynamic extern/function names come exclusively through `name_hint` (Lua assignment inference, e.g., `local foo = lalin.extern(...)` → `extern ... end`).

6. **The dotted-name type-position path at line 828 is a model for extension**. To eliminate `@{}` from fragment and name positions, you'd replicate this exact pattern: after consuming a `TK.name`, check for `TK.dot`, build up the dotted path, join with `"."`, and create the appropriate slot. The key insight is that the comment on line 828 explicitly states the design philosophy: *"the Lua environment IS the namespace"*.
