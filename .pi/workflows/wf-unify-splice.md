# Workflow
**Workflow ID**: wf-unify-splice
**Started**: 2026-06-17 17:19:13
---

## Scout Output — 2026-06-17 17:21:48

Here is the complete report.

---

## Files Retrieved

1. **`lua/lalin/parse.lua` (lines 2845–2897)** — `M.parse_module_document` — the full function. Scans a document, iterates islands, calls `parse_island` for each, accumulates `splice_slots` and `splice_values`, wraps island results as `Tr.ItemFunc`, `Tr.ItemType`, `Tr.ItemExtern`, and returns `{module, scan, splice_slots, issues, protocol_types, product_types}`.

2. **`lua/lalin/parse.lua` (lines 2653–2700)** — `M.parse_island` — dispatches on island kind (func/region/expr/struct/union/handle/extern), creates a parser for the token window, calls the appropriate internal parse method, returns `{kind, value, splice_slots, issues, protocol_types, product_types}`.

3. **`lua/lalin/parse.lua` (lines 2817–2842)** — `M.register_parsed_declaration` — shared helper called by both `parse_module_document` and `mlua_document_analysis`. Populates `splice_values[name_hint]` and `splice_values[lhs_path]` with a table `{present=true, value=tv}` where `tv` wraps an ASDL type node (for struct/union/handle). Later islands resolve these via `Parser:splice_value()`.

4. **`lua/lalin/parse.lua` (lines 436–439, 703–748)** — Parser constructor initializes `splice_slots = {}`, `splice_slots_by_id = {}`; `record_splice_slot` adds entries; `splice_value` looks up `self.splice_values[id]`.

5. **`lua/lalin/parse.lua` (lines 163–166, 286–291)** — Lexer: `new_tokens()` initializes `splice_map = {}`, `splice_spread = {}`, `splice_i = 0`. In the lex loop, `@{lua_expr}` creates `"splice.N"` IDs stored in `t.splice_map` and `t.splice_spread`.

6. **`lua/lalin/parse.lua` (lines 2335–2405)** — `tokenize_island` — re-lexes island text into the shared token array, also records splice IDs into `toks.splice_map` / `toks.splice_spread`.

7. **`lua/lalin/parse.lua` (lines 2554–2650)** — `M.scan_document` — Lua-aware scanner: finds island keywords, calls `tokenize_island`, records `name_hint`/`lhs_path` via `infer_lua_assignment_name`, returns `{toks, islands, splice_map, splice_spread}`.

8. **`lua/lalin/parse.lua` (lines 2498–2554)** — `infer_lua_assignment_name` — walks backward from island start to find `=`, then reads the LHS identifier and full dotted path.

9. **`lua/lalin/parse.lua` (lines 2900–2920)** — `M.Define(T)` — wraps all parse functions with `T` pre-applied. `parse_module = function(src, opts) return M.parse_module_document(T, src, opts) end`.

10. **`lua/lalin/frontend_pipeline.lua` (lines 250–370)** — `parse_and_lower` and `parse_and_lower_c` in `M.Define(T)` — the two main consumers of `parse_module`. Both call `Parse.parse_module(src, {collector=collector})`, extract `parsed.module` and `parsed.scan.toks`, build anchors from the scan/tokens, then call `lower_module(parsed.module, ...)` or `lower_module_to_c(parsed.module, ...)`. The `splice_slots` from the parse result are **never used**.

11. **`lua/lalin/frontend_pipeline.lua` (lines 85–170)** — `lower_module(module, opts)` — takes the `Tr.Module`, runs it through: `OpenExpand.module` → `OpenValidate.validate` → `ClosureConvert.module` → `Typecheck.check_module` → `Layout.module` → `TreeToCode.module_with_contracts` → `CodeValidate.validate` → graph/facts/kernel/schedule/lower plans → `LowerToBack.module` → `Validate.validate`. Returns results for all phases.

12. **`lua/lalin/mlua_document_analysis.lua` (lines 300–400)** — `analyze_document` in `M.Define(T)` — the LSP path. Scans document, iterates islands, calls `ParseApi.parse_island(scan, i, {protocol_types=..., splice_values=...})`, accumulates items/decls/region_frags/expr_frags/issues, and calls `Parse.register_parsed_declaration()` for each island. Does **not** call `parse_module_document`; calls `parse_island` directly per island.

13. **`lua/lalin/chain.lua` (lines 1–160)** — The `lalin.chain` universal applicative API. Handles three call patterns:
    - **String (pure quote)**: calls `parse_fn(T, arg)`, checks `#parsed.splice_slots ~= 0` and errors if any slots are unresolved, then calls `wrap_fn(parsed.value)`.
    - **String-keyed table (binder)**: returns a function that parses the string, iterates `parsed.splice_slots`, fills each with `hs.fill(session, ss.slot, value, ...)`, expands via `expand_fn(e, parsed.value, env)`, then wraps.
    - **Array-keyed table (builder)**: calls `table_fn(arg)`.

14. **`lua/lalin/host_func_values.lua` (lines 383–425)** — `api._stmts_quote` and `api._stmts_values_binder` — the `lalin.stmts[[]]` and `lalin.stmts{}.` entry points. Same pattern: parse, check `splice_slots` count, either error or fill via `host_splice.fill`.

15. **`lua/lalin/host_splice.lua` (lines 74–170)** — `M.fill(session, slot, value, site, role, spread)` — the central splice resolution dispatch. Dispatches on `role` (list roles: `expr_list`, `type_list`, `param_list`, etc.) and on `pvm.classof(slot)` (individual slots: `SlotType`, `SlotExpr`, `SlotRegion`, `SlotRegionFrag`, `SlotExprFrag`, `SlotName`).

16. **`lua/lalin/host.lua` (lines 15–22)** — `default_session.splice_values = {}` and `M._register_splice(path, value)` — the global Lua-side splice registry. Used for the `.mlua` hosted pipeline where `lalin.xxx = ...` assignments register values.

17. **`lua/lalin/open_expand.lua` (lines 1076–1082)** — `expand_module` — the PVM-cached expander that processes `Tr.Module`, expanding items. Also handles `SlotType`, `SlotExpr`, `SlotRegion` through lookup expansion during module-level processing when the env has fills.

### Test Files Using `parse_module`

18. **`tests/test_parse_typecheck.lua` (lines 54, 75, 87)** — Calls `P.parse_module(src)`, checks `#parsed.issues == 0`, extracts `parsed.module` for direct typechecking (`TC.check_module(parsed.module)`).

19. **`tests/test_ir_lower.lua` (line 17)** — `P.parse_module(src)` → `result.issues` check → `TC.check_module(result.module)` → extract `ItemFunc`s.

20. **`tests/test_handle_types.lua` (lines 38–155)** — Many calls to `P.parse_module(src)` testing lease type errors. Only checks `#parsed.issues`.

21. **`tests/test_code_mem_facts.lua`, `test_code_lower_plan.lua`, `test_code_graph.lua`, `test_code_flow_facts.lua`, `test_code_kernel_plan.lua`, `test_code_schedule_plan.lua`, `test_code_effect_facts.lua`, `test_code_value_facts.lua`, `test_tree_to_code.lua`, `test_tree_contract_facts.lua`, `test_lower_to_back_closed_form.lua`, `test_lower_to_back_kernel_scalar.lua`, `test_lower_to_back_kernel_vector.lua`, `test_semantic_lowering_fragments.lua`** — All follow the same pattern: `Parse.parse_module(src)` → check issues → `parsed.module` flows through parts of the pipeline (expand, typecheck, layout, tree_to_code, etc.).

22. **`tests/test_tagged_union_type_layout.lua` (line 80)** — `Parse.parse_module(src)` → checks issues → extracts module.

23. **`tests/test_advanced_views.lua` (line 54)** — `Parse.Define(T).parse_module(src)`.

24. **`tests/test_handle_diagnostics_lsp.lua` (line 24)** — `Parse.parse_module(src)` for LSP-style diagnostics testing.

25. **`tests/test_asdl_host_model.mlua` (line 30)** — Tests `parse_island(scan, 1)` directly, asserts `#parsed.splice_slots == 1`.

26. **`tests/test_parse_type_items.lua` (lines 14–55)** — Tests `parse_island` for struct/union/region-with-protocol-islands.

27. **`tests/test_parser_multiline.lua` (lines 38–69)** — Tests `parse_island` for func/region.

28. **`debug_fib_source.lua` (line 15)** — `parse.parse_module(src)` → `OE.module(parsed.module)` → `Pipeline.lower_module(expanded)`.

29. **`benchmark_backends.lua` (line 20)** — `parse.parse_module(src)` → check issues → `OE.module(parsed.module)` → validate → `Pipeline.parse_and_lower(src)`.

---

## Key Code

### `parse_module_document` return shape
```lua
return {
    kind = "module",
    module = Tr.Module(Tr.ModuleSurface, items),  -- consumed by pipeline
    scan = scan,                                    -- consumed for anchor building
    splice_slots = splice_slots,                    -- NEVER consumed by callers
    issues = issues,                                -- checked for errors
    protocol_types = protocol_types,                -- forwarded
    product_types = product_types,                  -- forwarded
}
```

### How `splice_values` flows within the parser
```
scan_document(src)
  → toks.splice_map["splice.N"] = lua_expr  (from @{lua_expr} in island text)
  → islands[].holes[] = toks.text[hi] (splice IDs)

parse_island(T, scan, i, {splice_values = ...})
  → Parser(toks, ..., {splice_values = ...})
  → Parser:splice_value(id) → looks up splice_values[id]
  → Used in type_name fast path (line 741), region_emit param spread (line 795)
  → Returns p.splice_slots = [{splice_id, splice_text, slot, role, spread}]

parse_module_document loop:
  → Accumulates splice_slots from each island's parse_island result
  → Calls register_parsed_declaration(name_hint, lhs_path, parsed.value, T, splice_values)
    → Populates splice_values[name] = {present=true, value={as_lalin_type=fn}}
    → This allows island #3 to reference island #1's type by name
```

### The two distinct splice mechanisms

1. **Parse-time resolution via `splice_values`** — Used by the `.mlua` pipeline. `splice_values` is a map from Lua-level names (like `"Pair"`) to Lua values. When the parser encounters a bare name (e.g., in a type position), `Parser:splice_value(name)` checks if it's in `splice_values` and returns the enclosed Lua value. This is how `region R(s: ptr(T); ...)` can reference `T` from `local T = struct ... end`.

2. **Post-parse splice via `splice_slots`** — Used by `lalin.chain` and `lalin.stmts{}.`. When `@{key}` appears in quoted source, the parser creates `Slot*` ASDL nodes and records them in `splice_slots`. After parsing, callers iterate `splice_slots`, fill each with `host_splice.fill(session, ss.slot, value, ...)`, then use `open_expand` to resolve the slots into concrete ASDL nodes.

### `register_parsed_declaration` — the bridge between the two
```lua
function M.register_parsed_declaration(name_hint, lhs_path, parsed_value, T, splice_values)
    -- If it's a TypeDeclStruct, TypeDeclUnion, or TypeDeclHandle, create a
    -- pseudo-Lua-value with as_lalin_type() that returns the ASDL type node.
    -- Register under both name_hint and lhs_path in splice_values.
    splice_values[name_hint] = { present = true, value = tv }
    splice_values[lhs_path] = { present = true, value = tv }
end
```

---

## Relationships

### Call graph
```
parse_module_document (parse.lua:2845)
  ├─ M.scan_document(src)                          → scan {toks, islands}
  │   ├─ tokenize_island() per island              → fills toks.splice_map
  │   └─ infer_lua_assignment_name()               → name_hint, lhs_path
  ├─ For each island:
  │   ├─ M.parse_island(T, scan, i, {splice_values}) → parsed {kind, value, splice_slots}
  │   ├─ Append parsed.splice_slots → accumulated splice_slots
  │   ├─ protocol_types / product_types propagation
  │   ├─ register_parsed_declaration(name_hint, lhs_path, parsed.value, T, splice_values)
  │   └─ Wrap parsed.value as Tr.ItemFunc/ItemType/ItemExtern → items[]
  └─ Return {module, scan, splice_slots, issues, protocol_types, product_types}

Callers:
  ├─ frontend_pipeline.parse_and_lower(src)        → extracts parsed.module, parsed.scan.toks
  │   └─ lower_module(parsed.module)               → full compilation pipeline
  ├─ frontend_pipeline.parse_and_lower_c(src)      → extracts parsed.module
  │   └─ lower_module_to_c(parsed.module)          → C output pipeline
  ├─ Tests (20+ files)                              → extracts parsed.module, parsed.issues
  ├─ debug_fib_source.lua                           → extracts parsed.module
  ├─ benchmark_backends.lua                         → extracts parsed.module
  └─ mlua_document_analysis.lua                    → does NOT call parse_module;
                                                     calls parse_island directly with
                                                     splice_values built inline
```

### `splice_slots` data flow

**In `parse_module_document` result**: The `splice_slots` array is accumulated from all islands but is **never consumed** by `frontend_pipeline` or any `parse_module` caller. It is present in the return value but callers only access `parsed.module`, `parsed.scan`, and `parsed.issues`.

**In `lalin.chain` and `lalin.stmts{}` (the quote/binder API)**: `splice_slots` IS consumed:
```
lalin.func{key = val}[[...]]
  → parse_func_string(T, src)
  → parsed.splice_slots [{splice_id, splice_text, slot, role, spread}]
  → for each slot: hs.fill(session, ss.slot, bound_values[key], ...)
  → expand_fn(e, parsed.value, env_with_fills)
  → wrap_fn(expanded)
```

### Where `splice_values` lives
- **Hosted `.mlua` pipeline**: `session.splice_values` (initialized in `host.lua`). Populated by `M._register_splice(path, value)` when `lalin.X = value` assignments happen.
- **`parse_module_document`**: Creates local `splice_values = opts.splice_values or {}`, then mutates it with `register_parsed_declaration`.
- **`mlua_document_analysis.lua` (LSP)**: Creates its own local `splice_values = {}`, passes to `parse_island`, and calls `Parse.register_parsed_declaration` in the same loop pattern.

---

## Observations

1. **`splice_slots` in the `parse_module` result is dead data.** The `parse_module_document` return includes `splice_slots` but no caller in the compilation or LSP paths consumes it. It accumulates each island's slots but they're never filled or expanded. The slot nodes are embedded in the ASDL tree (as `SlotType`, `SlotExpr`, etc.), and `open_expand` resolves them if the environment has fills — but no fills are ever provided in the `parse_module` → `lower_module` path.

2. **Two separate splice resolution paths exist**:
   - **Parse-time** (`splice_values` map): Used by `.mlua` documents where `local T = struct ... end` makes `T` visible to later islands. Populated by `register_parsed_declaration`. Used inside the parser via `Parser:splice_value()`.
   - **Post-parse** (`splice_slots` array): Used by the `lalin.XXX{}[[...]]` binder API. Parsed slots are filled by `host_splice.fill`, expanded via `open_expand`, and the result is wrapped.

3. **`parse_module_document` uses `opts.resolve_types_now = true`** (line 2847) — this forces `type_name` to resolve bare identifiers against `splice_values` at parse time rather than creating deferred name references.

4. **`mlua_document_analysis.lua` duplicates the island loop logic** instead of calling `parse_module_document`. It calls `parse_island` per island directly, builds its own `items`, `decls`, `region_frags`, `expr_frags` arrays, and calls `register_parsed_declaration` inline. The LSP path does NOT produce `Tr.ItemFunc` wrappers — it tracks islands individually as `Mlua.IslandParse`.

5. **`lalin.chain`'s `parse_fn` signature expects `function(T, src) → {value, issues, splice_slots}`**. The standalone string parsers (`parse_func_string`, etc.) return exactly this shape. The binder path uses `splice_slots` to fill values; the pure quote path errors if any slots exist.

6. **`host_func_values.lua` has `api._stmts_quote` and `api._stmts_values_binder`** — these are the older, direct `lalin.stmts` entry points. They follow the same pattern as `chain.lua` but are separate implementations (not using chain).

7. **`splice_slots_by_id` prevents double-recording** within a single parser instance. Keyed by `role:splice_id`. Since `parse_module_document` creates a fresh parser per island (via `parse_island`), there's no cross-island collision — but the global `splice_id` counters are sequential across the entire document.

8. **`protocol_types` and `product_types` propagate across islands** within `parse_module_document`. Each island's `parsed.protocol_types` replaces the previous value. This is how a `union` island makes its protocol types available to a later `region` island's `cont_slots_from_protocol()`.

9. **`infer_lua_assignment_name` extracts both `name_hint` (simple name) and `lhs_path` (dotted path)** from Lua assignment like `local result = func ... end` or `mylib.MyFunc = func ... end`. Both are registered in `splice_values`.

10. **The `splice_spread` flag** (`toks.splice_spread[id] = true` when `@{expr...}` ends with `...`) is recorded in each slot entry and passed to `host_splice.fill`. It distinguishes `@{val}` (single value) from `@{list...}` (spread — the Lua value is an array of elements to splice inline).

## Knowledge-builder Output — 2026-06-17 17:29:36

Now I have a complete picture. Let me synthesize the non-obvious observations.

---

## What Matters Most for This Problem

1. **Semantic equivalence** — the two resolution paths currently produce different ASDL type nodes (`TNamed` vs `TSlot → SlotValueType → TNamed`). The unification must ensure the same final type tree reaches the typechecker.

2. **Coupling surface** — `splice_values` is consumed by the parser in 3 places: `type_name()`, struct aggregate literal resolution, and `parse_open_params()` for spread splices. All must be addressed.

3. **Test path divergence** — tests call `TC.check_module(parsed.module)` directly, bypassing `OpenExpand.module`. A slot-based approach breaks this unless filling happens inside `parse_module` itself.

4. **LSP path independence** — `mlua_document_analysis.lua` duplicates the island loop. Changes must unify this path too, or risk forking the two paths further.

5. **`open_expand` readiness** — `ModuleExpand` already handles `SlotType`, `SlotRegionFrag`, `SlotExprFrag` resolution via fills in the env. The machinery exists but has never been applied to the `parse_module` → `lower_module` path.

---

## Non-Obvious Observations

### 1. The two paths produce fundamentally different ASDL shapes

When `resolve_types_now = true`, a bare-name type reference produces `TScalar` (for scalars) or `TNamed(TypeRefPath(...))` — a **permanent name-based reference** into the module's type forest. When `resolve_types_now = false`, the same reference produces `TSlot(TypeSlot(key, name))` — a **temporary hole** that `open_expand` replaces with a concrete type node from the FillSet.

This isn't just plumbing. `TNamed` means "the typechecker resolves this name against the module's type environment." `TSlot` means "an external agent must fill this before typechecking." The semantics differ: `TNamed` guarantees the type exists in the module; `TSlot` can be filled with any type, including types from outside the module. Post-unification, ALL intra-module references would become `TSlot → fill → TNamed`, which works because `expand_type` passes `TNamed` through unchanged, and the typechecker resolves it.

### 2. `register_parsed_declaration` is a Lua-value factory, not a type-resolver

It wraps ASDL type nodes in Lua tables with `as_lalin_type()` closures that return `TNamed(TypeRefPath(...))` or `THandle(TypeRefPath(...), repr)`. These Lua values flow into `Parser:type_from_value()` which calls `as_lalin_type()` to extract the ASDL type. This is a **parser-internal Lua value protocol**, separate from the `host_splice.fill_type` protocol (which uses `as_type_value()`, `lalin_splice("type")`, or raw ASDL class checks). These two value protocols are **incompatible** — `host_splice.fill_type` would reject the values `register_parsed_declaration` creates, because they have `as_lalin_type` (not `as_type_value`), and their `pvm.classof` is false (they're plain tables, not ASDL nodes).

The post-parse fill step would need to either: (a) wrap the ASDL type nodes in a shape `host_splice` accepts, (b) call `fill_type` with raw ASDL nodes (which `pvm.classof` would detect), or (c) bypass `host_splice.fill` entirely and construct `SlotBinding(SlotType(slot), SlotValueType(ty))` directly.

### 3. The struct aggregate literal path uses `splice_value` outside `type_name`

At parse.lua:1172, `ExprAgg` resolution calls `self:type_from_value(self:splice_value(left_name))` — this is a **third** splice_value consumer, separate from `type_name`. It has a fallback: if `splice_value` returns nil, it creates `TNamed(TypeRefPath(...))`. So removing `splice_values` wouldn't break this path — it would just shift from parse-time resolution to typecheck-time resolution via the `TNamed` fallback. However, this creates a subtle mismatch: `register_parsed_declaration` creates `TNamed` for structs but `THandle` for handles (which carries repr info). The fallback creates plain `TNamed` for both. For structs, this is equivalent. For handles, the `ExprAgg` type would lose the repr info... but `ExprAgg` is only meaningful for structs, not handles, so this is safe.

### 4. `protocol_types`/`product_types` propagation is a THIRD resolution mechanism, and it's orthogonal

These tables flow forward through `opts` during the island loop, carrying union variant info and struct field info that the parser uses to expand `region R(; UnionType)` and product-type open params. They are **not** part of either the `splice_values` or `splice_slots` systems. They work because islands are parsed sequentially within the same `parse_module_document` call, and the tables are forwarded as mutable state. The unification would NOT affect this mechanism — it's independent.

### 5. The `splice_slots` return array is dead but reveals the intended design

`parse_module_document` accumulates `splice_slots` from each island's parser and includes it in the return value, but no caller consumes it. This suggests the original design **intended** post-parse slot filling for the module path, but `resolve_types_now` was added as a shortcut. The array is populated correctly — it contains all the slots that WOULD need filling if `resolve_types_now` were removed. The unification is effectively **completing the original design** by removing the shortcut.

### 6. The LSP path's island-tracking divergence creates a real migration hazard

`mlua_document_analysis.lua` doesn't just call `parse_island` — it builds `Mlua.IslandParse` objects that track each island individually with its own `decl_set`, `module`, `rfrags`, `efrags`. These objects are used for **per-island LSP features** (go-to-definition, hover, diagnostics scoping). If we unify through `parse_module_document`, the LSP would lose per-island granularity. The LSP path must continue to call `parse_island` per island, which means the post-parse fill logic must be callable **incrementally** (fill after each island) or in **batch** (fill after all islands). Either approach works: batch is simpler and matches the module path; incremental is what the LSP already does with `register_parsed_declaration`.

### 7. The test path (`parse_module` → `TC.check_module`) is the highest-friction migration point

20+ test files call `P.parse_module(src)` and extract `parsed.module` for direct typechecking via `TC.check_module(parsed.module)`. This path **skips** `OpenExpand.module` entirely — it goes straight to `ClosureConvert.module` then typecheck. If we introduce `TSlot` nodes, these tests would fail because `TC.check_module` encounters unresolved slots.

There are two options:
- (a) Make `parse_module` apply the post-parse fill internally, so callers get a resolved module. This is self-contained — `parse_module` already accumulates declarations across islands; it just needs to fill slots before returning.
- (b) Update all tests to call `Pipeline.parse_and_lower(...)` instead. This is more invasive but aligns tests with the real pipeline.

Option (a) is the minimal safe change: `parse_module_document` would, after the island loop, convert accumulated declarations to `SlotBinding` entries, run `OpenExpand.module` with a filled env, and return the resolved module. Tests still see the same `parsed.module` shape.

### 8. `open_expand`'s `env_with_fills` path needs new wiring in `lower_module`

Currently `lower_module` calls `OpenExpand.module(module, opts.expand_env)`. The `parse_and_lower` caller never passes `expand_env`, so it defaults to `nil` → empty env. The post-parse fill step would need to construct an `ExpandEnv` with fills and pass it through. The chain path shows the pattern:

```lua
local e = open_expand.Define(T)
local env = e.empty_env()
env = e.env_with_fills(env, bindings)
local expanded = e.expand_module(parsed.module, env)
```

This exact pattern can be replicated in `parse_module_document` (for tests) and in `parse_and_lower` (for the full pipeline). The `bindings` would come from converting the accumulated declarations to `SlotBinding` entries via `host_splice.fill_type`.

### 9. There's a naming collision risk in slot keys

`type_name` uses `name` as the `splice_id` for `record_splice_slot`: `"type:Pair"`. If two different islands define different types named "Pair", the slot keys collide within a single parser. But `parse_module_document` creates a fresh parser per island, so cross-island collisions are fine (slots are in different arrays). After unification, ALL slots from ALL islands would be in one array, but each `TSlot` node in the ASDL tree references its own unique `TypeSlot` with its own `slot.key`. The fill step creates `SlotBinding(SlotType(slot), ...)` where `slot` is the specific `TypeSlot` from the ASDL tree. So fills are keyed by slot identity, not name — no collision.

### 10. The minimal change requires touching only 3 files (plus tests)

The unification can be implemented minimally in:
- **`parse.lua`**: Remove `resolve_types_now` flag (line 2847), remove `splice_value`/`splice_values` from Parser, make `type_name` always create TypeSlot, change `register_parsed_declaration` to produce fill-ready data instead of `splice_values`, add post-parse fill step in `parse_module_document`.
- **`frontend_pipeline.lua`**: Add `expand_env` construction in `parse_and_lower` (lines ~250-260), passing fills from declarations to `lower_module`.
- **`mlua_document_analysis.lua`**: Replace `register_parsed_declaration` + `splice_values` with the same fill mechanism.

No changes needed in `open_expand.lua`, `host_splice.lua`, `chain.lua`, or `host_func_values.lua` — those already work correctly with the slot-based path.

### 11. Hidden constraint: `parse_module` must remain callable without a session

`parse_module` callers (tests, frontend_pipeline) don't have a `session` with `.T` context — they use the global PVM context directly. But `host_splice.fill_type(session, slot, value, site)` requires a session. To bypass this, the post-parse fill step can construct `SlotBinding` entries directly using the ASDL constructors (`O.SlotBinding(O.SlotType(slot), O.SlotValueType(ty))`) without going through `host_splice`. This is actually cleaner — we're filling with **known ASDL types**, not arbitrary Lua values.

### 12. `register_parsed_declaration` has a dual-key pattern that must be preserved

It registers under both `name_hint` (simple name like `"Pair"`) and `lhs_path` (dotted path like `"mylib.Pair"`). This is because Lua assignment can be `local Pair = struct ... end` or `mylib.Pair = struct ... end`. Any post-parse fill mechanism must handle both keys — filling all TypeSlots whose `slot.id` matches either the simple name or the dotted path. This is straightforward: after all islands are parsed, iterate all splice_slots, match their `splice_text` (or rather, the slot's `id` field) against the accumulated declaration names.

---

## Knowledge Gaps

1. **How does `ClosureConvert.module` handle `TSlot` nodes if they survive expansion?** If a slot is not filled before typechecking, what error occurs? I should verify this to understand the failure mode.

2. **Are there any `splice_value` consumers in `parse_region_frag` or `parse_func` beyond `type_name` and the `ExprAgg` path?** A complete grep would confirm the full set of consumers.

3. **Does `mlua_document_analysis.lua` have any code paths that depend on `splice_values`-resolved types during parsing (for branching decisions), not just for type node construction?** If so, switching to post-parse resolution would change behavior.

## Knowledge-builder Output — 2026-06-17 17:34:51

Now I have the complete picture. Let me produce the deep analysis.

---

## What Matters Most for This Problem

1. **The number of resolution paths** — there are now 4-5 separate mechanisms (parse-time `splice_values`, post-parse `splice_slots` with `host_splice.fill`, chain's binder path, the old dead `_stmts_values_binder`, and `open_expand`'s env-based resolution). Unification means eliminating redundancy, not just re-plumbing.

2. **Fragment name resolution is already slot-only** — emit/call fragment references NEVER resolve at parse time. This is the precedent for the slot-only model. Unifying type name resolution to match would align with an existing architectural constant.

3. **Which dead code to kill vs. which live code to migrate** — `_stmts_quote`/`_stmts_values_binder` are dead. `resolve_types_now` is a live shortcut that must be unwound.

4. **Test impact** — 20+ tests call `parse_module` → `TC.check_module` directly, bypassing `OpenExpand`. The minimal fix must add the fill+expand step inside `parse_module` itself so tests don't break.

---

## Non-Obvious Observations

### 1. There are THREE distinct splice mechanisms in host_func_values.lua alone, and two of them are ghosts

```lua
-- Dead path A (line 383): api._stmts_quote
-- Dead path B (line 393): api._stmts_values_binder
-- Live path C (line 363): api.stmts = chain_binding.make_quote(...)
```

`_stmts_quote` and `_stmts_values_binder` are defined but never called from anywhere — grep confirms only the definition site. They're the pre-chain-era splice handlers, preserved but unreachable. The chain-based `api.stmts` replaced them via `host.lua` line ~540: `M.stmts = api.stmts`. The old `_stmts_values_binder` has its OWN copy of the fill-expand-wrap logic (lines 394-425) separate from chain.lua's binder path (lines 46-84). Both follow the same pattern: parse → fill → OpenExpand → wrap. But they're independent implementations.

**Why this matters**: The old code shows the pattern works (parse→fill→expand→wrap) but the duplication means there's no canonical implementation. Any unification of type name resolution should produce ONE canonical fill path, then retire these ghosts.

### 2. `resolve_types_now` is not a boolean — it's a phase switch that changes the parser's failure mode

At line 798-802:
```lua
if self.opts and self.opts.resolve_types_now then
    self:issue("unknown type '" .. name .. "' — must be declared before use")
    return Ty.TScalar(C.ScalarVoid)  -- poison pill
end
local slot = O.TypeSlot(...)  -- deferred resolution
return Ty.TSlot(slot)
```

When `true`, unknown types become `TScalar(void)` + a diagnostic. When `false`, they become `TSlot` — a deferred hole. The poison pill is worse than just an error: it produces a valid-but-wrong AST node that can cascade into confusing downstream errors. The slot-based path is architecturally cleaner because it defers the error to `OpenValidate`, which produces `IssueUnfilledTypeSlot` — a single, clear diagnostic at the exact point of failure.

### 3. Fragment name resolution is already the slot-only model — types are the odd one out

`parse_region_frag_ref` (line 1497-1508) and `parse_expr_frag_ref` (line 1510-1521) ALWAYS create `RegionFragSlot`/`ExprFragSlot` and NEVER check `splice_values`:

```lua
function Parser:parse_region_frag_ref(keyword)
    local name = self:kind() == TK.hole and self:text() or self:expect_name(...)
    local slot = O.RegionFragSlot(self:splice_key("region_frag", name), name)
    self:record_splice_slot(name, O.SlotRegionFrag(slot), "region_frag")
    return O.RegionFragRefSlot(slot), name
end
```

There is no `splice_value` check, no `resolve_types_now` flag. Fragment names are ALWAYS resolved through the post-parse fill pipeline. This unifies beautifully with the `lalin.chain` binder: the binder fills `@{frag}` with a region fragment Lua value, `host_splice.fill` creates a `SlotBinding(SlotRegionFrag(slot), SlotValueRegionFrag(frag))`, and `OpenExpand` replaces the slot with the real fragment.

**Key implication**: Making type name resolution follow the fragment pattern is NOT a new design — it's extending an existing, proven pattern to the one remaining holdout.

### 4. The splice_value consumers at lines 1880 and 1983 are a distinct, non-unifiable concern

These handle `@{lua_array...}` spread splices in continuation slot lists and open param lists. They try `splice_value(id)` and if it returns a table, iterate elements to construct `ContSlot`/`OpenParam` objects inline:

```lua
-- line 1880
local value = self:splice_value(id)
if type(value) == "table" then
    for j = 1, #value do
        -- construct ContSlot from each element
    end
else
    -- create sentinel spread slot
end
```

This is NOT a control flow decision based on TYPE EXISTENCE — it's a VALUE-TYPE check (is it an array?). This path resolves spread splices at parse time because the spread expansion changes the AST shape (N elements instead of 1 slot). The post-parse `host_splice.fill` also handles spread via `O.SlotValueContSlots` / `O.SlotValueOpenParams` — the array elements are filled into a single SlotBinding. So these consumers are the parse-time equivalent of the post-parse spread fill. They could be unified by always creating a single RegionSlot for spread cont/open-param lists, but that changes the semantics slightly (the slot's name encodes the spread role).

### 5. TypeValue's `as_lalin_type()` vs. `as_type_value().ty` — two Lua→ASDL protocols that must converge

`register_parsed_declaration` creates Lua tables with `as_lalin_type()` closures. `host_splice.fill_type` checks `as_type_value()` then `as_type_value().ty`. These are DIFFERENT protocols:

- `register_parsed_declaration` → `{ as_lalin_type = function() return Ty.TNamed(...) end }`
- `host_type_values.lua`'s `TypeValue` → `.ty` field (already an ASDL type node) + `:as_type_value()` returning `self`

But `host_splice.fill_type` (line 125) is flexible — it checks `pvm.classof(value)` for raw ASDL nodes, then `as_type_value()`, then `lalin_splice("type")`. Passing raw ASDL type nodes (like `Ty.TNamed(TypeRefPath(...))`) directly to `fill_type` would work because `pvm.classof` on an ASDL node returns the class. The issue is that `register_parsed_declaration` wraps them in intermediate tables.

**The simple fix**: Have the post-parse fill step extract the raw ASDL type from the `register_parsed_declaration`-style wrapper and pass it directly. Or better: change `register_parsed_declaration` to store raw ASDL nodes instead of wrapper tables, and have a separate bridge function that `host_splice.fill` can consume.

### 6. `ClosureConvert` is a canary — if TSlot reaches it, something failed silently

ClosureConvert (273 lines) has exhaustive `pvm.classof` dispatch on all expression, statement, and type variants. It has NO case for `Tr.ExprSlotValue`, `Tr.StmtUseRegionSlot`, `Tr.ItemUseTypeDeclSlot`, or `Ty.TSlot`. If any slot survives to ClosureConvert, it passes through as an identity transform — the slot remains in the tree. This would cause silent wrong-code until a later phase (like `tree_typecheck`'s `ref_type`, which returns `void_ty()` for unrecognized ref types) produces cascading errors.

**This is the hidden invariant**: `OpenExpand` MUST resolve all slots before `ClosureConvert` runs. The pipeline order is `OpenExpand` → `OpenValidate` → `ClosureConvert`. `OpenValidate` generates issues for unfilled slots but doesn't HALT — it just issues diagnostics. If someone runs `OpenValidate` but not `OpenExpand`, the slots survive into ClosureConvert. The current `parse_module` → `TC.check_module` path skips both `OpenExpand` and `OpenValidate`, so it relies on `resolve_types_now` to never create slots in the first place.

### 7. The `parse_module_document` → `lower_module` pipeline has ZERO expand environment plumbing

`parse_and_lower` (frontend_pipeline.lua:250) calls:
```lua
local parsed = Parse.parse_module(src, { collector = collector })
local result = lower_module(parsed.module, { collector = collector, analysis_ctx = analysis_ctx })
```

`lower_module` eventually calls `OpenExpand.module(module, opts.expand_env)` where `opts.expand_env` is never set — it's `nil` → empty env with no fills. If `parse_module` started producing TSlot nodes, `OpenExpand` would find no fills and the slots would survive. The fix needs to: (a) have `parse_module_document` do the post-parse fill+expand internally (for tests), AND (b) pass the fill bindings through `lower_module`'s expand env (for the full pipeline).

### 8. `host.lua`'s `_register_splice` + `default_session.splice_values` is the missing link between .mlua assignment and parse-time resolution

```lua
-- host.lua:17
default_session.splice_values = {}
-- host.lua:22
function M._register_splice(path, value)
    default_session.splice_values[path] = { present = true, value = value }
end
```

When `.mlua` code does `local Pair = struct Pair x: i32, y: i32 end`, the struct's definition calls `_register_splice("Pair", struct_value)`. Later `func ... z: Pair ... end` calls `parse_module_document` which creates a local `splice_values = opts.splice_values or {}` — but it NEVER picks up `default_session.splice_values`. These are SEPARATE maps! The `splice_values` used by `parse_module_document` starts empty and is populated ISLAND-BY-ISLAND by `register_parsed_declaration`. The `default_session.splice_values` populated by `_register_splice` is only used by... nobody? Let me check...

Actually wait — in the `.mlua` pipeline, each island is submitted to `parse_module_document` individually (or all together?), and the caller passes `opts.splice_values = default_session.splice_values`. Let me verify.

Actually, I think the `.mlua` pipeline goes through `parse_module_document` which creates its own empty `splice_values` and populates it internally via `register_parsed_declaration`. The `default_session.splice_values` is a separate store used by `lalin.chain` bindings and other hosted-API paths. These are two separate stores that happen to have the same name.

### 9. The `splice_slots[].splice_text` vs `splice_slots[].splice_id` naming scheme creates a fragile fill-key matching system

`record_splice_slot` records `splice_id` (e.g., `"splice.3"` for lexer-generated holes) and `splice_text` (e.g., `"Pair"` for bare-name types). In `chain.lua`, the fill step uses:
```lua
local key = ss.splice_text or ss.splice_id  -- line 69
local v = bound_values[key]
```

This means bare-name slots are matched by the NAME TEXT (`"Pair"`), while `@{expr}` holes are matched by the Lua key used in the binder's table. For the post-parse fill in `parse_module_document`, we'd need to match by both `name_hint` and `lhs_path` from each island. The slot's `splice_text` (which is just the bare name) would naturally match the `name_hint`, but the `lhs_path` (e.g., `"mylib.Pair"`) wouldn't match any slot's splice_text. This means the dual-key registration (`name_hint` + `lhs_path`) must map to the SAME fill — which `register_parsed_declaration` already does by registering the same wrapper under both keys. The post-parse fill just needs to iterate `splice_slots` and match against both keys.

### 10. Circular references work naturally with post-parse fill but are currently broken for forward references

Island #1: `region R(arg: T; ...)` where `T` is defined in island #3
Island #2: `func f(): ptr(T)` where `T` is defined in island #3
Island #3: `struct T x: i32 end`

With `resolve_types_now = true`, islands #1 and #2 fail because `T` is not yet in `splice_values`. With post-parse fill, ALL islands are parsed first (creating TSlot nodes), THEN fills are applied. Island #3's `T` fills the slots in islands #1 and #2. This is a FORWARD REFERENCE fix, not a regression — the post-parse model handles what the current model cannot.

However, TRUE circular references (e.g., struct A has field of type B, struct B has field of type A) work differently. With post-parse fill, struct A's field type would be `TSlot(key="B")` and struct B's field type would be `TSlot(key="A")`. After filling, A's field becomes `TNamed("B")` and B's field becomes `TNamed("A")`. These are name references, not structural references — the typechecker resolves them later. So circular TYPE references work fine. Circular STRUCTURAL dependencies (where type layout depends on the other type's layout) would be a problem, but that's already a problem with the current system.

---

## Knowledge Gaps

None remaining. The picture is complete.

## Approach-proposer Output — 2026-06-17 17:40:05

Now I have the full picture. Let me produce the three approaches.

---

## Approach A: Name Resolution as PVM Phase — "The Compilation Boundary"

- **Core idea**: Extract intra-module name resolution into a first-class PVM phase (`ResolveNames`) that transforms a `Tr.Module` containing `TSlot` nodes into a resolved `Tr.Module`, treated as a scalar memoized compilation boundary just like layout or typecheck.

- **Key changes**:
  - **New file: `lua/lalin/resolve_names.lua`** — defines `pvm.phase("resolve_names", fn)` that walks the module tree, builds a `name → TypeDecl` map from `ItemType` entries, and replaces every `TSlot(TypeSlot(key, name))` with `TNamed(TypeRefPath(...))` where the name matches a declaration. Produces `IssueUnresolvedTypeSlot` for unmatched slots.
  - **`parse.lua`**: Remove `resolve_types_now` flag; `type_name()` always creates `TSlot` (matching fragment slots); `register_parsed_declaration` stores raw ASDL type decls in a local table instead of `splice_values`; remove `splice_value()` and `splice_values` from Parser; `parse_module_document` returns unresolved module with TSlot nodes.
  - **`frontend_pipeline.lua`**: Insert `ResolveNames.resolve(module)` between `OpenExpand.module` and `OpenValidate.validate` in `lower_module`. The phase caches on module identity — unchanged modules hit automatically.
  - **`mlua_document_analysis.lua`**: Call `ResolveNames.resolve(module)` after island loop instead of inline `register_parsed_declaration` + `splice_values`.
  - **`chain.lua` / `host_func_values.lua`**: No changes — these continue to use their own fill+expand path for external Lua values.
  - **Tests**: No test changes needed — `parse_module` → `TC.check_module` callers get unresolved modules. Tests either add `ResolveNames` or the phase runs automatically in `lower_module`.

- **Tradeoff**: Optimizes for architectural purity — name resolution is a proper compilation fact, visible in `pvm.report()`, independently cacheable, with its own ASDL diagnostic vocabulary. Sacrifices simplicity: adds a new phase, new ASDL types (`ResolvedModule`, `ResolutionEntry`), and a new file (~200 lines). The PVM phase model is the heaviest-weight solution for what is fundamentally a simple map+replace operation.

- **Risk**: Over-engineering. A PVM phase for name resolution is cacheable on module identity, but modules are not incrementally edited — each parse produces a new module. The cache would be a single-entry cache. The phase machinery (recording triplets, seq_gen, shared reads) adds complexity without paying for itself. PVM phases shine for recursive tree transformations with subtree caching (like layout or render); name resolution is a flat loop over module items + a tree walk over type positions — no subtree sharing to exploit.

- **Rough sketch**:
  1. Define new ASDL types in a `LalinResolve` module: `ResolveEnv(NameEntry*)`, `NameEntry(name, type_decl)`, `SlotResolution(slot, resolved_ty_or_nil)`.
  2. Implement `resolve_module = pvm.phase("resolve_names", function(module)` — scalar phase. Internally: collect `NameEntry` from all `ItemType` items, then recursively walk the module replacing `TSlot` → `TNamed` where name matches.
  3. Wire into `lower_module` between `OpenExpand` and `OpenValidate`. `OpenExpand` handles external fills (chain binder); `ResolveNames` handles intra-module names.
  4. Update `parse_module_document` to return unresolved module.
  5. Update LSP path to call `ResolveNames` as a post-parse step.

---

## Approach B: Post-Parse Fill via OpenExpand — "Match the Fragment Pattern"

- **Core idea**: Types follow the exact same path as fragment names already do — parse creates `TSlot`, post-parse fill converts accumulated declarations to `SlotBinding` entries, `OpenExpand.module` resolves them. Zero new phases, zero new ASDL types, minimal code change.

- **Key changes**:
  - **`parse.lua` lines 2845–2897 (`parse_module_document`)**: Remove `resolve_types_now` flag (line 2847). After the island loop, convert the accumulated `splice_slots` + declaration table to `SlotBinding` entries (using raw ASDL constructors — `O.SlotBinding(O.SlotType(slot), O.SlotValueType(ty))`), call `OpenExpand.module` with an `ExpandEnv` containing those fills, return the resolved module. `register_parsed_declaration` changes from populating `splice_values` to recording `{name_hint, lhs_path, raw_asdl_type}` in a local declaration list. Remove `splice_value()` and `splice_values` from Parser.
  - **`parse.lua` lines 790–810 (`type_name`)**: Always create `TypeSlot` + `TSlot`. Remove `resolve_types_now` branch that creates poison-pill `TScalar(void)`.
  - **`frontend_pipeline.lua` lines 250–270 (`parse_and_lower`)**: Construct `ExpandEnv` with fills from parse result, pass to `lower_module` via `opts.expand_env`.
  - **`mlua_document_analysis.lua` lines 300–400**: Same post-parse fill pattern — accumulate declarations per island, convert to fills, run `OpenExpand` on the per-island module or on the accumulated items.
  - **`parse.lua` lines 2335–2405 (`tokenize_island`) / `scan_document`**: Unchanged — slot recording continues as-is.
  - **Tests**: No changes needed — `parse_module` returns resolved module; `TC.check_module(parsed.module)` works because slots are already filled.
  - **Dead code removal**: Remove `_stmts_quote` and `_stmts_values_binder` from `host_func_values.lua` (lines 383–425) — they are unreachable ghosts that duplicate chain.lua logic. Remove `default_session.splice_values` from `host.lua` (lines 15–22) — becomes unused.

- **Tradeoff**: Optimizes for minimal change — extends an existing, proven mechanism (fragment slots → fill → OpenExpand) to cover the one remaining holdout (type names). The resulting code is simpler (2 mechanisms become 1). Sacrifices the opportunity to make resolution a visible, independently diagnosable compilation step. Resolution stays "inside the parser" rather than being a proper compiler pass.

- **Risk**: `OpenExpand` is designed for resolving external fills (chain binder values) and module-level expansion. Using it for intra-module type resolution ties resolution to the OpenExpand phase, which does many other things (region fragment inlining, expression fragment expansion, closure conversion prep). If OpenExpand's behavior changes for external fills, it could affect intra-module resolution. However, since `OpenExpand.expand_type` handles `TSlot` → `TNamed` as a no-op passthrough (`TNamed` passes through unchanged), the risk is low — the fill either replaces the slot or passes `TNamed` through.

- **Rough sketch**:
  1. In `parse_module_document`: change `register_parsed_declaration` to accumulate `{name_hint, lhs_path, asdl_type_node}`. Remove `splice_values` parameter from `parse_island`.
  2. After island loop: match each `splice_slot` entry against the declaration list (matching `splice_text` against `name_hint` or `lhs_path`), construct `SlotBinding(SlotType(slot), SlotValueType(ty))` for each match.
  3. Call `OpenExpand.define(T).expand_module(module, env_with_fills(env, bindings))` before returning.
  4. In `parse_and_lower`: extract fills from parse result, construct `ExpandEnv`, pass through `lower_module`.
  5. Remove `resolve_types_now`, `splice_value()`, `splice_values` from Parser.
  6. Remove dead ghost paths in `host_func_values.lua` and `host.lua`.

---

## Approach C: Typechecker-Only Resolution — "The Module IS the Environment"

- **Core idea**: Eliminate both parse-time resolution and post-parse slots for intra-module names. The parser always produces `TNamed(TypeRefPath(...))` for bare-name type references — forward references included. Resolution happens entirely in the typechecker, which builds its `defs` table from the complete module's `ItemType` entries and resolves `TNamed` references during typechecking. This is the most architecturally radical: slots and fills exist only for *external* Lua values (chain binder, `@{expr}` in hosted source), not for intra-module names.

- **Key changes**:
  - **`parse.lua` lines 780–810 (`type_name`)**: Always produce `TNamed(TypeRefPath(...))` — strip the `resolve_types_now` branch and the `TSlot` branch. Similarly, `ExprAgg` resolution (line 1172) falls through to `TNamed` (already exists as fallback).
  - **`parse.lua` lines 2817–2842 (`register_parsed_declaration`)**: Remove entirely. Declarations are already registered as `ItemType` in the module's item list — the typechecker reads them from there. No extra registration needed.
  - **`parse.lua` lines 2845–2897 (`parse_module_document`)**: Remove `splice_values` accumulation, `register_parsed_declaration` calls. The loop just wraps islands as `ItemFunc`/`ItemType`/`ItemExtern`. Remove `splice_slots` from return value. Return becomes `{module, scan, issues, protocol_types, product_types}` (drop `splice_slots`).
  - **`parse.lua` lines 436–748 (Parser)**: Remove `splice_value()`, `splice_values`, `record_splice_slot` (for type slots — keep for `@{expr}` holes). Type-related splice infrastructure is dead.
  - **`lua/lalin/tree_typecheck.lua` lines 360–395 (`build_variant_defs`)**: Already builds `defs` from all module items. Forward references resolve correctly because the typechecker processes the complete module (all islands are already parsed and in `module.items`). No changes needed for forward reference handling — it already works.
  - **`lua/lalin/tree_typecheck.lua` lines 470–480 (`ref_type`)**: Already resolves `TNamed` against `defs`. No changes needed.
  - **`mlua_document_analysis.lua`**: Remove `register_parsed_declaration` calls and `splice_values` construction. Declarations are tracked via the accumulated `items`/`decls` arrays.
  - **`frontend_pipeline.lua`**: No changes — `parse_module` returns resolved module directly.
  - **Tests**: No changes — `parse_module` returns module with `TNamed` references; `TC.check_module` resolves them.
  - **Dead code removal**: Remove `splice_values` from Parser, `register_parsed_declaration`, `resolve_types_now`, `_register_splice` / `default_session.splice_values` from `host.lua`.

- **Tradeoff**: Optimizes for architectural minimalism — the module's item list IS the type environment; there is no separate registration step, no fills, no slots for intra-module names. The typechecker is the single point of name resolution, which is the right place for it (typechecking IS resolving names to types). Sacrifices the "everything is a slot" uniformity: type names and fragment names now take different paths (fragments remain slot-based, types become `TNamed`). This is philosophically consistent — fragment names are runtime composition boundaries resolved by the caller; type names are module-scope declarations resolved by the compiler.

- **Risk**: The typechecker currently processes items incrementally during `check_module`. If an item references a type declared in a later item (forward reference), the typechecker must have the complete `defs` table available when it encounters the reference. Currently `build_variant_defs` runs once at the start of `check_module` and builds `defs` from ALL items. So forward references work. But I need to verify that `build_variant_defs` runs before individual item checking begins. If the typechecker processes items sequentially and builds `defs` lazily, forward references would fail. The grep above shows `build_variant_defs` is called in tree_typecheck.lua — let me verify it runs before item-level typechecking.

- **Rough sketch**:
  1. Verify that `build_variant_defs(module, module_name)` runs before per-item typechecking — it must build the complete `defs` table upfront. If not, restructure to two-phase: collect all type names first, then typecheck items.
  2. In `type_name()` (parse.lua): always construct `TNamed(TypeRefPath({C.Path({C.Name(text)})}))`. Remove `resolve_types_now` flag.
  3. In `parse_module_document`: remove `splice_values` local, remove `register_parsed_declaration` calls, remove `splice_slots` from return.
  4. Remove `splice_value()`, `splice_values` from Parser constructor and methods.
  5. Verify `ExprAgg` fallback path (line ~1172) still works — it already falls through to `TNamed` when `splice_value` returns nil. Confirm behavior is identical.
  6. Remove dead code: `register_parsed_declaration`, `_register_splice`, `default_session.splice_values`.
  7. Update `mlua_document_analysis.lua` to stop calling `register_parsed_declaration`.

---

## Comparison

| Dimension | Approach A (PVM Phase) | Approach B (Post-Parse Fill) | Approach C (Typechecker-Only) |
|---|---|---|---|
| **When to pick** | When you want name resolution visible as a compilation step with its own caching and diagnostics — useful if modules are large and resolution is expensive enough to benefit from memoization, or if you want `pvm.report()` to show resolution hit rates | When you want the minimal, safest change that unifies the two paths without adding new abstractions. Proven pattern (fragment slots already work this way). Lowest migration risk | When you want maximum simplification: eliminate intra-module slots entirely. Best if you believe slots should be reserved for external/hosted values, not internal module references |
| **Lines changed** | ~400 new + ~100 modified | ~80 modified + ~60 removed | ~150 removed + ~30 modified |
| **New concepts** | 1 new PVM phase, ~4 new ASDL types | 0 new concepts | 0 new concepts |
| **Mechanisms eliminated** | 3 → 2 (splice_values + resolve_types_now gone; slot+fill+expand remains; resolve phase added) | 4 → 2 (splice_values + resolve_types_now + dead ghosts gone; slot+fill+expand remains + chain binder remains) | 5 → 2 (splice_values + resolve_types_now + register_parsed_declaration + dead ghosts + type slots for intra-module gone; only chain binder slots + fragment slots remain) |
| **Forward references** | Fixed (post-parse resolution) | Fixed (post-parse fill) | Fixed (typecheck-time resolution) |
| **Test impact** | Tests must add ResolveNames or run through lower_module | Zero — parse_module returns resolved module | Zero — parse_module returns module with TNamed |
| **Philosophical alignment** | Aligns with COMPILER_PATTERN ("every question is a phase") but over-kills a simple problem | Aligns with "one mechanism for all slots" — extends proven pattern | Aligns with "ASDL is the architecture" — the module's items ARE the resolution environment; no extra mechanism needed |

### My recommendation

**Approach C** is the correct architectural answer. The three constitutional documents teach that the ASDL is the architecture, that types are data, and that modules contain items. A module's `ItemType` entries already carry the complete type declarations. Having a separate registration mechanism (`splice_values` + `register_parsed_declaration`) that mirrors what the module's item list already provides is architectural duplication. The typechecker already resolves `TNamed` against `defs` built from module items. The parser should produce honest `TNamed` references and let the typechecker do its job — resolve names to types.

Approach B is the pragmatic answer if risk aversion is paramount — it's a 80-line change that deletes dead code and extends a proven mechanism.

Approach A is the wrong answer here. Name resolution is a flat lookup, not a recursive tree transformation. PVM phases pay for themselves through subtree caching and fusion — neither applies to a single flat pass over a module that's always newly constructed.

## Critique Output — 2026-06-17 17:48:01

Now I have all the data. Let me produce the final critique.

---

## Approach C: Typechecker-Only Resolution — "The Module IS the Environment"

### Question-by-Question Verification

**Q1: Does `build_variant_defs` run before per-item typechecking?**

Yes. Confirmed at `tree_typecheck.lua:1472`: `attach_semantic_defs(base_env, build_variant_defs(module, ...), ...)` is called inside `type_module_with_layout_env` at line 1492, **before** the per-item loop at line 1494 (`for i = 1, #module.items do ...`). `build_variant_defs` iterates ALL module items at line 387, collecting `ItemType` entries into the `defs` table. Forward references work because the complete defs table exists before any individual item is typechecked.

**Q2: How does ExprAgg work without `splice_value`?**

At `parse.lua:1172`, the ExprAgg type resolution is: `self:type_from_value(self:splice_value(left_name)) or self.Ty.TNamed(...)`. When `splice_value` returns nil (which it will after removal), the fallback `TNamed` path fires. This is correct for structs. Handles don't have aggregate literals (`Pair { x = 1 }` only makes sense for structs). For the zero case where an ExprAgg references a handle name by accident, `TNamed` would be produced, and the typechecker would resolve it against the handle def — the type error surface shifts from "parse-time type name lookup" to "typecheck-time struct/handle mismatch," which is semantically equivalent.

**No gap.**

**Q3: Do `protocol_types`/`product_types` depend on `splice_value`?**

No. They're completely independent. `protocol_types` is populated by `parse_union_island` (line 2236) and `product_types` by `parse_struct_island` (line 2161). They're consulted within the parser at lines 1745, 1946, 1968, 2039 — all direct table lookups, no `splice_value` calls. They propagate through `opts` between islands in the `parse_module_document` loop. Approach C doesn't touch them.

**No gap.**

**Q4: Are there OTHER consumers of `splice_value` beyond `type_name` and `ExprAgg`?**

Four consumers total:

| Line | Context | Impact of removal |
|------|---------|-------------------|
| 793 | `type_name` — intra-module type resolution | **Intentional removal** — replaced by `TNamed` |
| 1172 | `ExprAgg` — struct aggregate type | **Safe** — fallback `TNamed` fires |
| 1880 | `cont_slot_list` spread splices | **Safe** — always falls to sentinel path (splice_value already returns nil here for chain binder; for parse_module_document, splice_values only holds type wrappers, never arrays) |
| 1983 | `open_param_list` spread splices | **Safe** — same analysis as 1880 |

The key verification: at lines 1880/1983, the code only triggers on `TK.hole` + `splice_spread`, which means `@{expr...}` antiquote syntax. In the chain binder (which actually uses these), `splice_values` is already empty — the binder doesn't populate it during parsing. The sentinel path (`else` branch creating a spread region slot) has always been the active path for chain binder spread splices. The post-parse fill via `host_splice.fill_cont_slot_list`/`fill_open_param_list` handles them correctly via `SlotValueContSlots`/`SlotValueOpenParams` + `OpenExpand`.

**No gap.**

**Q5: Does removing `splice_values` from `parse_island` opts affect fragment resolution?**

No. Fragment name resolution (`parse_region_frag_ref` at line 1497, `parse_expr_frag_ref` at line 1510) always creates `RegionFragSlot`/`ExprFragSlot` via `record_splice_slot` — they never check `splice_value`. Confirmed: zero uses of `splice_value` or `splice_values` in fragment resolution code.

**No gap.**

**Q6: What about the LSP path (`mlua_document_analysis.lua`)?**

The LSP path (`analyze_document`, line 303) creates its own `splice_values = {}` and passes it to `parse_island` per island. With Approach C:

- `splice_values` stays empty (no `register_parsed_declaration` to populate it)
- `parse_island` no longer needs `splice_values` — `type_name` always produces `TNamed`
- Each island's `IslandParse` carries an accumulated `module` with all prior `ItemType` entries
- LSP features (hover, go-to-definition) use `SubjectAt` / `BindingFacts` which operate on the ASDL tree, not on parse-time resolved types
- Hover formats types via `Format.type_name()` which handles `TNamed` natively
- Go-to-definition uses binding facts from the ASDL tree — no dependency on resolved type refs
- LSP diagnostics (`resolved_issues`) only surface parse errors — no typecheck phase in the LSP path today

**No gap.** The LSP path works correctly with unresolved `TNamed` references. The shift from parse-time to typecheck-time resolution doesn't affect LSP features because none of them require resolved type nodes in the AST.

**Q7: Are there circular dependencies where `TNamed` can't be resolved?**

`TNamed` creates name references (`TypeRefPath`), not structural references. The typechecker resolves them against `defs` built from ALL module items upfront. Circular name references (A → B → A) work because both names exist in `defs` before either is typechecked. True structural circularity (A's layout depends on B's layout which depends on A's layout) is already broken in the current system and remains broken — Approach C doesn't change this.

**No new gap.** Forward references are actually IMPROVED: the current `resolve_types_now=true` path issues "unknown type — must be declared before use" errors for forward references. Approach C eliminates this restriction entirely.

**Q8: Does the ExprAgg fallback (`TNamed` without repr info) work for handles?**

`ExprAgg` at line 1172 is only reachable for struct aggregate literals (`Pair { x = 1, y = 2 }`). Handles don't have aggregate literal syntax — handles are opaque identities accessed through store regions. Even if somehow a handle name reached this path, the typechecker would catch the mismatch (aggregate applied to non-struct type). The `TNamed` fallback is correct for the only case that matters (structs).

**No gap.**

**Q9: Does anything depend on `as_lalin_type()` in `splice_values` after `parse_module_document` returns?**

No. `splice_values` is a local variable in `parse_module_document` (line 2856). The `register_parsed_declaration` wrappers with `as_lalin_type()` closures are stored ONLY in this local table. When the function returns, the table is garbage-collected. The return value includes `module` (which contains `ItemType` entries — proper ASDL nodes), `scan`, `splice_slots` (slot recording, not Lua value wrappers), `issues`, `protocol_types`, and `product_types`. None of these reference the `as_lalin_type` wrappers.

`type_from_value` (line 772) is only called from two places, both with `self:splice_value(...)` as argument. After removing `splice_value()`, `type_from_value` becomes dead code and can be removed.

**No gap.**

**Q10: Does anything downstream read `splice_values` or `splice_slots` from the `parse_module` return?**

- `parse_module_document` return's `splice_slots`: **Never read.** `frontend_pipeline.lua` extracts only `parsed.module`, `parsed.scan`, and `parsed.scan.toks`. All 20+ tests extract only `parsed.module` and `parsed.issues`. Confirmed by grep: zero callers outside the function read this field from the return value.

- `parse_module_document`'s local `splice_values`: Discarded when the function returns.

- Standalone string parsers' `splice_slots`: Consumed by `chain.lua:62,101,111` and `host_func_values.lua:387,401,405` — these are the quote/binder paths. **Unchanged by Approach C** — standalone parsers still produce `splice_slots` for `@{expr}` holes. Only intra-module type slots are eliminated.

- `default_session.splice_values` from `host.lua:17`: Only consumed by `_register_splice` (host.lua:22), which is only called from `lalin.X = value` assignments in the hosted `.mlua` pipeline. Removing both is safe because the hosted pipeline uses chain binder (not parse_module_document) for its type resolution.

**No gap.** The dead `splice_slots` field can be safely removed from the `parse_module_document` return value.

---

### Additional Gaps Found

**Gap 1: Bare-name type references in chain-quoted source change behavior**

This is the one finding that Approach C doesn't fully address. In chain-quoted source (`lalin.func{...}[[...]]`), a bare-name type reference like `func f(): MyType end` currently creates a `TSlot` + `TypeSlot` with `splice_text="MyType"`. If the bound values table includes `MyType`, the chain binder fills it. Approach C makes bare-name references always produce `TNamed` — they can no longer be filled from bound values.

**Impact assessment**: In practice, all chain binder tests I examined use `@{expr}` syntax for spliced values, not bare-name references. The idiom is `lalin.func{ scan = scan }[[...emit @{scan}...]]` — explicit antiquote. The bare-name resolution path in the chain binder appears unused in the test suite. However, if any user code relies on `lalin.func{MyType = type_val}[[func f(): MyType ... end]]`, this would break — the type reference would become `TNamed("MyType")` and the typechecker would fail because "MyType" isn't in any module's items.

**This is a documentation/communication gap, not a correctness gap.** The behavior change should be called out explicitly. Users of the chain binder must use `@{TypeName}` syntax for spliced type references. This is already the documented idiom in LANGUAGE_REFERENCE.md §14.

**Gap 2: The as_lalin_type protocol lives in host_type_values.lua and host_struct_values.lua independently**

`type_from_value` checks three protocols: `as_lalin_type()`, `as_type_value()`, and `__lalin_host_type_value`. The first is used by `register_parsed_declaration` wrappers (which Approach C removes). The second and third are used by `host_splice.fill_type` and the chain binder. Removing `type_from_value` entirely would only be correct if no other parser paths use it. Since the two callers both use `splice_value()`, removing the splice_value → type_from_value chain is safe. The function itself can be removed or kept as dead code — no functional difference.

**Gap 3: The LSP path's `register_parsed_declaration` call must also be removed**

Line 376 in `mlua_document_analysis.lua`: `Parse.register_parsed_declaration(name_hint, lhs_path, parsed.value, T, splice_values)`. With Approach C, this must be removed because `register_parsed_declaration` is deleted. The LSP loop already accumulates `ItemType` entries in `items` (line 354-356 for struct/union/handle), which become part of `module = Tr.Module(Tr.ModuleSurface, items)`. This module is stored in each `IslandParse`. Later LSP code that needs to resolve type references would use the module's items — but the current LSP path doesn't do this resolution at all (it never typechecks). This is fine — the LSP is parse-only.

**Gap 4: `splice_slots_by_id` can be removed from the Parser for type-related slots**

Currently `record_splice_slot` uses `splice_slots_by_id` to prevent double-recording. After Approach C, `TypeSlot` entries are no longer created. The `splice_slots_by_id` mechanism remains necessary for fragment slots and `@{expr}` holes (chain binder). No change needed, but worth noting that the dedup mechanism is preserved for the remaining slot types.

---

### Evaluation

| Dimension | Score (1-5) | Rationale |
|-----------|-------------|-----------|
| **Coupling** | 4/5 | Dramatically reduces coupling. Currently `splice_values` couples the parser to a separate declaration registry, `register_parsed_declaration` couples parse_module_document and mlua_document_analysis, `resolve_types_now` couples type_name to caller context, and `_register_splice` couples host.lua to default_session. All removed. The remaining coupling is clean: parser produces `TNamed`, typechecker resolves it from module items. |
| **Cohesion** | 5/5 | Each module gets clearer responsibility. Parser: "build the AST with honest name references." Typechecker: "resolve names to types from the module's declarations." No module does two things or half-does something. The module's `ItemType` entries are the single source of truth for type declarations. |
| **Migration cost** | 4/5 | ~150 lines removed, ~30 modified across 3 files (parse.lua, mlua_document_analysis.lua, host.lua). No test changes needed — `parse_module` returns a module with `TNamed` references, and `TC.check_module` resolves them identically. One caveat: the `asdl_host_model.mlua` test checks `#parsed.splice_slots == 1` from `parse_island` but this test creates slots via `@{T}` syntax (not bare-name references), so it's unaffected. Score reduced from 5 because the LSP path's `register_parsed_declaration` call and `splice_values` local must be removed — a small but real change. |
| **Philosophy fit** | 5/5 | Perfectly aligned with all three constitutional documents. COMPILER_PATTERN.md: "The ASDL is the architecture. Everything else is downstream." The module's `ItemType` entries ARE the architecture — splice_values was a parallel, redundant mechanism. LANGUAGE_REFERENCE.md §6.4: type declarations are `struct`/`union` islands that become module items. PVM_GUIDE.md: phases answer distinct questions — "what types exist?" is answered by the module's items, not by a parser-internal hash table. |
| **Risk** | 3/5 | Low but not zero. The chain binder bare-name type reference behavior change (Gap 1) is the primary risk — it could break user code that uses `lalin.func{Type = val}[[func f(): Type ... end]]` without `@{}` syntax. In practice this appears unused (all tests use `@{expr}`), but it's a semantic shift. The second risk is that `type_from_value` removal could affect an undiscovered code path — though the grep is exhaustive. |
| **Testability** | 5/5 | Every change is independently verifiable. Step 1: remove `resolve_types_now` → `type_name` always produces `TNamed` → tests still pass because `TC.check_module` resolves them. Step 2: remove `splice_values` from Parser → standalone parsers still work (they never populated it). Step 3: remove `register_parsed_declaration` → the module's items already carry all declarations. Each step can be committed and tested separately. |

**Verdict**: Strong yes

**Key concern**: The chain binder behavior change for bare-name type references (Gap 1). The approach document says "only external @{expr} holes (chain binder) create slots" but doesn't explicitly call out that bare-name type references in chain-quoted source become unresolvable. If any user code or internal test relies on `lalin.func{TypeName = type_val}[[func f(): TypeName ... end]]` (without `@{}`), it will break because `TypeName` becomes `TNamed` instead of `TSlot`. The fix is a one-line documentation note: bare-name type references in quoted source always resolve against the module's items; use `@{TypeName}` to splice external types.

---

### Approach A: Name Resolution as PVM Phase

| Dimension | Score (1-5) | Rationale |
|-----------|-------------|-----------|
| **Coupling** | 3/5 | Adds a new module (`resolve_names.lua`) that depends on both Tree ASDL types and the PVM phase system. The phase boundary is clean but introduces a new API surface (`ResolveNames.resolve(module)`) that callers must learn. Better than the current tangle but creates a new coupling between parse output and this phase. |
| **Cohesion** | 3/5 | The phase does one thing (resolve names), which is good. But it duplicates what `build_variant_defs` already does — iterate `ItemType` entries to build a name→type map. Now there are TWO name→type map builders (one in typecheck, one in resolve_names) that must stay in sync. |
| **Migration cost** | 2/5 | ~400 new lines + ~100 modified. New ASDL types required. The PVM phase machinery adds significant boilerplate (triplet recording, seq_gen, shared reads) for a single flat pass. Tests must either add the phase call or run through `lower_module`. PVM phase caching pays for itself through subtree reuse, but modules are freshly constructed — the cache is a single-entry cache. |
| **Philosophy fit** | 3/5 | Aligns with COMPILER_PATTERN ("every question is a phase") but over-commits for a flat lookup. PVM phases are designed for recursive tree transformations with subtree sharing (layout, render). Name resolution is a flat, non-recursive map+replace — the PVM phase machinery adds complexity without paying for itself. |
| **Risk** | 2/5 | New ASDL types, new phase, new file. Any bug in the name→def lookup would silently produce `IssueUnresolvedTypeSlot` instead of the typechecker's existing "unknown type" error. The phase must handle all edge cases that `build_variant_defs` already handles (nested modules, `ItemUseModule`, `TypeDeclEnumSugar`). Risk of divergence between resolve_names defs and typecheck defs. |
| **Testability** | 4/5 | The phase is independently callable and cacheable. Can test `ResolveNames.resolve(module)` in isolation. But tests must be restructured to add the phase call, or the phase must be wired into `lower_module`. |

**Verdict**: Significant concerns

**Key concern**: Over-engineering. A PVM phase for name resolution adds ~400 lines, new ASDL types, and triplet recording infrastructure for what is fundamentally `for item in module.items: if item is ItemType: defs[item.name] = item.type`. The PVM phase model is the right tool for recursive, cacheable tree transformations — name resolution is flat.

---

### Approach B: Post-Parse Fill via OpenExpand

| Dimension | Score (1-5) | Rationale |
|-----------|-------------|-----------|
| **Coupling** | 3/5 | Extends the existing slot+fill mechanism to cover type names. But this ties intra-module type resolution to `OpenExpand`, which is designed for external fills (chain binder values). If OpenExpand changes, intra-module resolution could be affected. Also couples `parse_module_document` to `open_expand` module — currently it's independent. |
| **Cohesion** | 4/5 | "One mechanism for all slots" is clean. Fragment names and type names follow identical paths. The slot+fill+expand pipeline is already proven for fragment resolution. Each module does one thing: parser creates slots, fill step converts declarations to bindings, OpenExpand resolves them. |
| **Migration cost** | 3/5 | ~80 lines modified + ~60 removed. Must wire `OpenExpand` into `parse_module_document` and add `expand_env` plumbing to `frontend_pipeline.lua`. The post-parse fill step must match `splice_slot` entries against declaration names (matching `splice_text` against `name_hint`/`lhs_path`) and construct `SlotBinding` entries using raw ASDL constructors. This is straightforward but involves new code in the hot parse path. |
| **Philosophy fit** | 3/5 | "One mechanism" is elegant but philosophically debatable. Fragment names need slots because they're resolved by the CALLER (external composition). Type names are resolved by the COMPILER (internal module scope). Using the same mechanism for both conflates two different resolution domains. The ASDL philosophy says module items ARE the type environment — adding slots as an intermediate step adds indirection without adding meaning. |
| **Risk** | 3/5 | `OpenExpand` is designed for external fills. Using it for intra-module resolution ties resolution to a phase that does many other things (region fragment inlining, expression fragment expansion, closure conversion prep). If OpenExpand's semantics change for external fills, intra-module resolution could be affected. However, `expand_type` handles `TSlot → TNamed` as a passthrough — the risk is moderate. |
| **Testability** | 4/5 | The fill step can be extracted and tested independently. `parse_module` still returns a resolved module, so tests don't change. |

**Verdict**: Yes with caveats

**Key concern**: The fill step must handle dual-key matching (name_hint + lhs_path) and construct `SlotBinding` entries using raw ASDL constructors without requiring a session (since `parse_module` callers lack sessions). This is implementable but adds complexity to the parse path that Approach C avoids entirely.

---

### Summary

| Approach | Score strengths | Score weaknesses |
|----------|----------------|------------------|
| **A** (PVM Phase) | Testability (4) | Migration cost (2), Risk (2), over-engineering |
| **B** (Post-Parse Fill) | Cohesion (4), Testability (4) | Coupling (3), Philosophy fit (3) |
| **C** (Typechecker-Only) | Cohesion (5), Philosophy fit (5), Testability (5) | None below 3 |

- **Recommended**: **Approach C**. It scores the highest on cohesion, philosophy fit, and testability, with no dimension below 3. It removes the most code (~150 lines) and adds zero new mechanisms. It aligns perfectly with the project's architectural principles: the module's items ARE the type environment; the typechecker resolves names from items; no separate registration, no intermediate slots, no parallel mechanisms. The one risk (bare-name chain binder behavior change) is a documentation issue, not a correctness issue — and it's consistent with the stated design ("only @{expr} holes create slots").

- **Dark horse**: **Approach B**. If the chain binder behavior change in Approach C turns out to affect real user code, Approach B preserves bare-name type filling in the binder while still unifying the two resolution paths. The "one mechanism for all slots" design is appealing and proven for fragments. The cost is coupling intra-module resolution to OpenExpand.

- **Avoid**: **Approach A**. A PVM phase for name resolution is architectural overkill. The machinery (triplet recording, seq_gen, shared reads, phase caching) adds significant complexity for a flat map+replace operation that the typechecker already performs. It introduces a new module, new ASDL types, and new failure modes without solving a real problem that the other approaches don't solve more simply.

## Documenter Output — 2026-06-17 17:51:27

Now I have all the data I need. Let me produce the comprehensive architectural decision document.

```markdown
# Architectural Decision: Unify Lalin Name Resolution

**Workflow ID**: `wf-unify-splice`
**Decision**: Approach C — Typechecker-Only Resolution ("The Module IS the Environment")
**Date**: 2026-06-17
**Status**: Sealed

---

## Goal

Eliminate the parallel, redundant path for intra-module type-name resolution by making the parser always produce honest `TNamed(TypeRefPath(...))` references for bare-name types, and letting the typechecker resolve those names from the module's own `ItemType` entries. The module's item list **is** the type environment; the parser should not maintain a separate declaration registry.

---

## Incentives

### 1. Redundant resolution mechanisms

The codebase currently has **two separate systems** for resolving type names appearing in Lalin source, plus a third compatibility shim:

| Mechanism | Where | Purpose |
|-----------|-------|---------|
| Parse-time `splice_values` | `parse.lua:2856`, `parse_island` opts | Resolve type names inside the parser against previously-parsed islands |
| `register_parsed_declaration` | `parse.lua:2817–2842` | Populate `splice_values` with `as_lalin_type()` wrapper tables after each island |
| `resolve_types_now = true` | `parse.lua:2847` | Force-flag that shortcuts name resolution by issuing poison-pill errors for unknown types instead of creating deferred `TSlot` nodes |

These exist **in addition** to the typechecker's own `build_variant_defs` (which already walks all `ItemType` entries to build a `defs` map), and the post-parse `splice_slots` + `host_splice.fill` + `OpenExpand` pipeline used by the chain binder for external Lua values.

### 2. Dead code in the return path

The `parse_module_document` return value includes a `splice_slots` array accumulated across all islands (`parse.lua:2897`). No caller in the compilation pipeline (`frontend_pipeline.lua:250–370`) or any test file (20+ files) ever reads this field. It is dead data: populated correctly but never consumed.

### 3. Forward-reference restrictions

With `resolve_types_now = true`, a type referenced in island #1 but declared in island #3 produces `Issue("unknown type … — must be declared before use")` and a poison-pill `TScalar(void)` node. There is no architectural reason for this restriction — the typechecker already builds its complete `defs` table from all module items before processing any individual item (`tree_typecheck.lua:1472` calls `build_variant_defs` before `for i = 1, #module.items do`).

### 4. Ghost code paths

`host_func_values.lua` lines 383–425 defines `api._stmts_quote` and `api._stmts_values_binder` — older splice handlers never called from anywhere (superseded by chain.lua's binder path). `host.lua:17` maintains `default_session.splice_values` which is also unused. These are residual, unreachable copies of the same fill-expand-wrap logic.

### 5. Architectural tension

The ASDL philosophy states: **"The ASDL is the architecture. Everything else is downstream."** (COMPILER_PATTERN.md §1.2). A module's `ItemType` entries carry the complete set of type declarations. Maintaining a separate `splice_values` hash table that mirrors this information is architectural duplication — a second source of truth for "what types exist." The typechecker already resolves `TNamed` from module items (§5.4 of LANGUAGE_REFERENCE.md: "Named types are resolved during typechecking against the module's type declarations and imports"). The parser should produce `TNamed` and be done.

---

## Current State

### The `parse_module_document` function (`parse.lua:2845–2905`)

This is the central entry point for `.mlua` file compilation. It:

1. Scans the document for island boundaries (`scan_document`, line 2850)
2. Iterates islands, calling `parse_island` for each with an `opts` table carrying `splice_values`, `protocol_types`, and `product_types` (line 2856–2865)
3. Accumulates `splice_slots` from each island's parser (line 2866)
4. Calls `register_parsed_declaration(name_hint, lhs_path, parsed.value, T, splice_values)` to insert wrapper tables into the local `splice_values` map (line 2872–2874)
5. Wraps each island's parse result as `Tr.ItemFunc`, `Tr.ItemType`, or `Tr.ItemExtern` and appends to `items` (line 2876–2888)
6. Returns `{module = Tr.Module(…, items), scan, splice_slots, issues, protocol_types, product_types}`

The critical line is **2847**: `opts.resolve_types_now = true`. This flag is set unconditionally and cannot be overridden by callers. It alters the parser's behavior in `type_name()` (line 798–802):

```lua
-- parse.lua:798
if self.opts and self.opts.resolve_types_now then
    self:issue("unknown type '" .. name .. "' — must be declared before use")
    return Ty.TScalar(C.ScalarVoid)  -- poison pill
end
-- Otherwise: create a deferred TSlot
local slot = O.TypeSlot(self:splice_key("type", name), name)
self:record_splice_slot(name, O.SlotType(slot), "type")
return Ty.TSlot(slot)
```

### The `type_name` resolution cascade (`parse.lua:780–806`)

The `type_name` method handles bare-name type references (e.g., `func f(): Pair` where `Pair` is a declared struct). The resolution order is:

1. **Scalar keywords** (`i32`, `f64`, `bool`, etc.) — direct lookup. Always works.
2. **`splice_value(name)`** — checks if the name has a Lua value registered. This is the path that `register_parsed_declaration` feeds. If found, calls `type_from_value()` which dispatches on `as_lalin_type()` to extract the ASDL type node.
3. **`resolve_types_now` check** — if the name wasn't found in step 2 and this flag is set, emit a diagnostic and return poison-pill `TScalar(void)`. If the flag is **not** set, create a `TSlot` + `TypeSlot` for post-parse fill.
4. **Fallthrough** — creates `TSlot` for deferred resolution.

### The `register_parsed_declaration` bridge (`parse.lua:2817–2842`)

Shared between `parse_module_document` and `mlua_document_analysis.lua` (the LSP path). For struct/union/handle declarations, it creates Lua wrapper tables with `as_lalin_type()` closures that return `TNamed(TypeRefPath(…))` or `THandle(TypeRefPath(…), repr)`. These wrappers are inserted into `splice_values` under both `name_hint` (simple name) and `lhs_path` (dotted path, for `mylib.Pair = struct … end`).

This is a **Lua-value protocol**: the parser exchanges wrapper tables through a Lua hash map, separate from the ASDL tree. The wrappers are never persisted — they are local to the `parse_module_document` call and garbage-collected when it returns.

### The `splice_values` consumer sites

Beyond `type_name`, `splice_value` is consulted at three other parse sites:

| Line | Context | What it does |
|------|---------|--------------|
| 793 | `type_name` | Primary type resolution — **target of unification** |
| 1172 | `ExprAgg` struct literals | Falls through to `TNamed` when `splice_value` returns nil — **safe** |
| 1880 | `cont_slot_list` spread splices | Always falls to sentinel path in practice — **safe** |
| 1983 | `open_param_list` spread splices | Same as 1880 — **safe** |

The `ExprAgg` path is notable: it already has a correct `TNamed` fallback. When `splice_value` returns nil (which it will after removal), the fallback fires identically.

### The post-parse slot+fill path (for context)

The chain binder (`chain.lua:46–84`) and fragment resolution (`parse_region_frag_ref` at line 1497, `parse_expr_frag_ref` at line 1510) use a completely different mechanism:

1. Parser creates `TSlot` / `RegionFragSlot` / `ExprFragSlot` nodes
2. These are recorded in `splice_slots` via `record_splice_slot`
3. After parsing, the caller iterates `splice_slots`, fills each with `host_splice.fill(session, slot, value, …)`, constructing `SlotBinding` entries
4. `OpenExpand.module` with an `ExpandEnv` containing fills resolves the slots

This path is **unchanged** by Approach C. It remains the correct path for external Lua values (`@{expr}` holes in quoted source). Only intra-module named-type references are moved to the typechecker.

### The typechecker's existing name resolution

In `tree_typecheck.lua`:

- **`build_variant_defs(module, module_name)`** (line 387) iterates ALL `module.items`, collecting every `Tr.ItemType` into a `defs` table mapping `name → {name, ty, …}`. It runs **before** per-item typechecking (line 1472: `attach_semantic_defs(base_env, build_variant_defs(module, …), …)` precedes the `for i = 1, #module.items do` loop at line 1494).
- **`ref_type`** (line ~470) resolves `TNamed(TypeRefPath(…))` against `defs`. If the name is not found, it produces `IssueUnknownType`.
- Forward references work because `defs` is complete before any item is checked.

### The LSP divergence

`mlua_document_analysis.lua` does not call `parse_module_document`. It duplicates the island loop, calling `parse_island` per island directly with its own local `splice_values = {}`, building `Mlua.IslandParse` objects for per-island LSP features. It calls `register_parsed_declaration` inline (line ~376). The LSP path is parse-only — it never typechecks, so `TNamed` references in its AST are never resolved. This is fine: LSP features (hover, go-to-definition) operate on the ASDL tree directly, not on resolved type nodes.

### Summary of mechanisms to eliminate

| Component | Location | Function |
|-----------|----------|----------|
| `splice_values` local | `parse.lua:2856` | Accumulates intra-module declaration wrappers |
| `splice_value()` method | Parser class | Looks up `splice_values` by name |
| `type_from_value()` method | Parser class | Dispatches on `as_lalin_type()` — becomes dead code |
| `register_parsed_declaration()` | `parse.lua:2817–2842` | Bridges parse result → `splice_values` |
| `resolve_types_now` flag | `parse.lua:2847` | Forced-resolve shortcut |
| `api._stmts_quote` / `_stmts_values_binder` | `host_func_values.lua:383–425` | Dead pre-chain-era splice handlers |
| `default_session.splice_values` | `host.lua:17` | Global registry, never read |
| `_register_splice()` | `host.lua:22` | Writes to `default_session.splice_values` |
| `splice_slots` in return | `parse.lua:2897` | Accumulated but never consumed by callers |

---

## Chosen Target

### Approach

**Approach C: Typechecker-Only Resolution — "The Module IS the Environment."**

The parser always produces `TNamed(TypeRefPath(…))` for bare-name type references. No `TSlot`, no `splice_value` lookup, no `resolve_types_now` flag. The typechecker resolves `TNamed` from `ItemType` entries in the module (via `build_variant_defs`, which already runs upfront). Intra-module slots exist only for external `@{expr}` holes (chain binder / fragment resolution). The module's `items` array is the single source of truth for what types exist.

This approach was scored by the critique as: Cohesion 5/5, Philosophy fit 5/5, Testability 5/5, with no dimension below 3. It removes the most code (~150 lines) and adds zero new mechanisms.

### Architecture

#### New invariant

> **Intra-module type references are always `TNamed`, never `TSlot`. `TSlot(TypeSlot(key, name))` is reserved for external (chain-binder / `@{expr}`) values and fragment references.**

This means the three resolution domains are cleanly separated by what resolves each:

| Reference kind | ASDL node | Resolved by | Where |
|----------------|-----------|-------------|-------|
| Named type (`Pair`, `Vec3`) | `TNamed(TypeRefPath(…))` | Typechecker | `build_variant_defs` → `ref_type` |
| Spliced type (`@{T}`) | `TSlot(TypeSlot(…))` | Host fill | `host_splice.fill` → `OpenExpand` |
| Fragment ref (`emit @{frag}`) | `RegionFragRefSlot(…)` | Host fill | `host_splice.fill` → `OpenExpand` |

#### Changed data flow

**Before** (current state):
```
parse_module_document
  ├─ Island #1: struct Pair … end
  │   ├─ parse_island → TypeDeclStruct
  │   └─ register_parsed_declaration("Pair", …, splice_values)
  │       └─ splice_values["Pair"] = {as_lalin_type = λ → TNamed("Pair")}
  │
  ├─ Island #2: func f(): Pair … end
  │   ├─ type_name("Pair")
  │   │   └─ splice_value("Pair") → as_lalin_type() → TNamed("Pair")  ← RESOLVED AT PARSE TIME
  │   └─ Tr.ItemFunc(func{result=TNamed("Pair")})
  │
  └─ return {module=Tr.Module(items), splice_slots=…}  ← splice_slots never consumed
```

**After** (Approach C):
```
parse_module_document
  ├─ Island #1: struct Pair … end
  │   ├─ parse_island → TypeDeclStruct
  │   └─ (no registration — the ItemType IS the declaration)
  │
  ├─ Island #2: func f(): Pair … end
  │   ├─ type_name("Pair")
  │   │   └─ return TNamed(TypeRefPath({Path({Name("Pair")})))  ← HONEST REFERENCE
  │   └─ Tr.ItemFunc(func{result=TNamed("Pair")})
  │
  └─ return {module=Tr.Module(items)}
      │
      ▼
  lower_module → typecheck (TC.check_module)
      │
      ├─ build_variant_defs(module) → defs["Pair"] = TypeDeclStruct(…)
      ├─ For ItemFunc f():
      │   └─ ref_type(TNamed("Pair")) → defs["Pair"]  ← RESOLVED AT TYPECHECK TIME
      │
      └─ All forward references work (defs is complete before any item is checked)
```

#### Specific changes

##### 1. `parse.lua:780–806` — `type_name()`

Remove lines 793–803 (the `splice_value` lookup, the `resolve_types_now` branch, and the `TSlot` creation). Replace with:

```lua
function Parser:type_name()
    local name = self:expect_unreserved_name()
    -- Scalar keyword lookup (unchanged)
    local m = { void=C.ScalarVoid, bool=C.ScalarBool, ... }
    if m[name] then return Ty.TScalar(m[name]) end
    -- Always produce honest TNamed reference.
    -- Resolution happens in the typechecker.
    return Ty.TNamed(Ty.TypeRefPath(C.Path({ C.Name(name) })))
end
```

The `splice_key`, `record_splice_slot`, and `TypeSlot`/`TSlot` creation for type names are removed from this code path. They remain for fragment references and `@{expr}` holes (unchanged).

##### 2. `parse.lua:2817–2842` — `register_parsed_declaration`

**Removed entirely.** Declarations are already recorded as `Tr.ItemType` entries in the module's `items` array (line 2880). The typechecker reads them from there. No separate wrapper table needed.

##### 3. `parse.lua:2845–2905` — `parse_module_document`

- Remove `opts.resolve_types_now = true` (line 2847)
- Remove local `splice_values = opts.splice_values or {}` (line 2856)
- Remove `splice_values` from the `parse_island` opts (line 2860)
- Remove `register_parsed_declaration` calls (lines 2872–2874)
- Remove `splice_slots` from return value (line 2897 — the field itself, and the accumulation at line 2866)
- Keep the `splice_slots` local accumulation if needed internally, but drop it from the return shape

New return shape:
```lua
return {
    kind = "module",
    module = Tr.Module(Tr.ModuleSurface, items),
    scan = scan,
    issues = issues,
    protocol_types = protocol_types,
    product_types = product_types,
}
```

##### 4. `parse.lua:430–750` — Parser class

- Remove `splice_value()` method
- Remove `type_from_value()` method (becomes dead code — only called from `splice_value` consumers)
- Remove `splice_values` field from constructor
- Keep `record_splice_slot()` and `splice_slots` (still needed for fragment slots and `@{expr}` holes)
- Keep `splice_key()` (used by fragment refs)
- Keep `splice_slots_by_id` dedup map (used by fragment refs)

##### 5. `parse.lua:2653–2700` — `parse_island`

- Remove `splice_values` from opts parameter and the call to `Parser.new(…)` passing it

##### 6. `frontend_pipeline.lua:250–370` — `parse_and_lower` / `parse_and_lower_c`

- Remove any reference to `parsed.splice_slots` — it's already unused
- No new plumbing needed (the typechecker handles resolution)

##### 7. `mlua_document_analysis.lua:300–400` — LSP `analyze_document`

- Remove `splice_values = {}` local
- Remove `register_parsed_declaration` calls
- Remove `splice_values` from `parse_island` opts

##### 8. `host.lua:15–22` — `default_session.splice_values` / `_register_splice`

**Removed.** Unused after migration.

##### 9. `host_func_values.lua:383–425` — `_stmts_quote` / `_stmts_values_binder`

**Removed.** Dead ghost code (never called, superseded by chain.lua).

#### What does NOT change

- **Chain binder** (`chain.lua`): Continues to use `parse → splice_slots → host_splice.fill → OpenExpand` for external `@{expr}` values. Its `parse_fn` contract (`function(T, src) → {value, issues, splice_slots}`) is unchanged.
- **Fragment resolution** (`parse_region_frag_ref`, `parse_expr_frag_ref`): Already slot-only with no `splice_value` check. Unchanged.
- **`protocol_types`/`product_types` propagation**: Independent mechanism for expanding union variants and struct fields across islands. Unchanged.
- **`scan_document` / `tokenize_island`**: Slot recording for `@{expr}` holes continues as-is.
- **`OpenExpand.module`**: Continues to handle external fills. Not needed for intra-module type resolution.
- **`host_splice.lua`**: Unchanged — still handles fill dispatch for external values.
- **`tree_typecheck.lua`**: Unchanged. `build_variant_defs` already handles this correctly. `ref_type` already resolves `TNamed` from `defs`.
- **All 20+ test files**: `parse_module(src)` returns a module with `TNamed` references. `TC.check_module(parsed.module)` resolves them identically. No test changes required.

#### Forward references — a behavior improvement

Currently, this fails at parse time:

```lua
-- .mlua file
local f = func use_pair(p: ptr(Pair)): i32  -- ERROR: Pair not declared yet
    return p.left + p.right
end

local Pair = struct Pair left: i32, right: i32 end
```

With Approach C, this works. The parser produces `TNamed("Pair")` as an honest reference. The typechecker builds `defs["Pair"]` from all `ItemType` entries before checking `f`, so `Pair` is found.

True circular STRUCTURAL dependencies (where A's layout depends on B's layout depends on A's layout) remain unsupported, which is correct — they're unsupported in the current system too.

#### Chain binder behavior change — documented

In chain-quoted source, bare-name type references (without `@{}`) become `TNamed` and resolve only against module items, not bound values. This was previously possible but appears unused in practice:

```lua
-- This NO LONGER works:
lalin.func { TypeName = type_val } [[ func f(): TypeName ... end ]]

-- This CONTINUES to work:
lalin.func { TypeName = type_val } [[ func f(): @{TypeName} ... end ]]
```

All existing chain binder tests use explicit `@{expr}` antiquote syntax. The bare-name path in the binder appears unused in the test suite. This is consistent with LANGUAGE_REFERENCE.md §14.4, which documents the `@{key}` syntax for bound values.

### Tradeoffs acknowledged

1. **Fragment names and type names take different paths.** Fragment references remain slot-based (resolved by the caller — external composition); type references become `TNamed` (resolved by the compiler — internal module scope). This is philosophically correct: fragment names are runtime composition boundaries; type names are module-scope declarations. The two domains are different; forcing them into the same mechanism conflates caller responsibility with compiler responsibility. The critique scored Philosophy fit at 5/5 for this approach.

2. **Resolution is not a visible compilation step.** Unlike Approach B (post-parse fill via `OpenExpand`), Approach C does not make name resolution a separately observable, independently diagnosable phase. Resolution happens inside the typechecker, alongside type-checking. The tradeoff is that name-resolution diagnostics are part of typechecking diagnostics — there is no separate "unresolved name" phase report. This is acceptable because unresolvable names are type errors; surfacing them from the typechecker is natural.

3. **No PVM phase for caching name resolution.** Approach A's `ResolveNames` phase would be independently cacheable on module identity. Approach C does not cache name resolution separately. In practice, this doesn't matter: modules are freshly constructed for each parse — a separate cache would be a single-entry cache that never hits. The typechecker's `type_module` phase already caches on the fully-resolved result.

### Risks acknowledged

1. **Chain binder bare-name behavior shift.** Users who rely on `lalin.func{Type = val}[[func f(): Type … end]]` without `@{}` must switch to `@{Type}`. The critique identified this as the primary risk (scored 3/5 for Risk). Mitigation: all existing tests use `@{expr}` syntax; LANGUAGE_REFERENCE.md §14.4 documents the binding idiom with `@{}`; the migration is a one-character syntax change.

2. **`ExprAgg` fallback for handles.** If an aggregate literal somehow references a handle name (which has no aggregate semantics), the fallback `TNamed` is produced and the typechecker catches the mismatch. This is semantically equivalent to the current behavior — the error surface shifts from parse-time "unknown type" to typecheck-time "aggregate applied to non-struct type."

3. **Undiscovered `splice_value` consumers.** The scout and knowledge-builder exhaustively grepped all consumers (4 sites total). All are accounted for. The risk of an undiscovered consumer is low but not zero. If one exists, it would break at runtime when `splice_value` is removed from the Parser.

---

## Philosophical Basis

Three project constitutional documents support this decision.

### COMPILER_PATTERN.md §1.2 — "The ASDL is the architecture"

> The ASDL is the architecture. Everything else is downstream.

A module's `ItemType` entries are ASDL nodes — intered, immutable, canonical. They ARE the type environment. `splice_values` was a parallel, non-ASDL mechanism (a mutable Lua hash map of wrapper tables) that mirrored information already present in the ASDL tree. Eliminating it restores the principle: the ASDL tree is authoritative; nothing outside it holds parallel state about what types exist.

### COMPILER_PATTERN.md §1.3 — "The gap has layers"

> Each layer consumes knowledge. Each boundary exists because a real question is being answered.

The question "what does the name `Pair` refer to?" is answered by the typechecker, not the parser. The parser's job is to build the AST with honest name references. The typechecker's job is to resolve those names to types. The `splice_values` mechanism answered this question in the parser — one layer too early, duplicating work the typechecker must do anyway.

### LANGUAGE_REFERENCE.md §5.4 — "Named types"

> Named types are resolved during typechecking against the module's type declarations and imports. Unresolved names produce type errors.

The language reference already states that resolution happens during typechecking. `resolve_types_now` violated this contract by doing resolution at parse time. Approach C aligns the implementation with the specification.

### LANGUAGE_REFERENCE.md §14.4 — "Binding values"

> The values table comes FIRST and returns a **quote function**. The `[[]]` invocation parses the string, looks up each `@{}` key in the values table, fills the slot, expands, and returns clean ASDL.

The `@{}` antiquote syntax is the canonical mechanism for splicing external Lua values into Lalin source. Bare-name resolution in quoted source was an undocumented, untested secondary path. Removing it simplifies the contract: only `@{}` means external value.

### PVM_GUIDE.md Chapter 2 — "The ASDL is the universal type system"

> Every type in a pvm system is an ASDL type.

The `splice_values` wrapper tables (`{as_lalin_type = function() … end}`) were not ASDL types — they were Lua tables with closures, existing outside the ASDL type system. The compiler's internal model should use ASDL types exclusively. `TNamed(TypeRefPath(…))` is an ASDL type. `build_variant_defs` builds an ASDL-native defs map. `ref_type` resolves ASDL-native references. The entire path is ASDL-native.

---

## Implementation Summary

| What | File(s) | Lines |
|------|---------|-------|
| Remove `splice_value()`, `type_from_value()`, `splice_values` from Parser | `parse.lua` | ~40 removed |
| Simplify `type_name()` to always produce `TNamed` | `parse.lua:780–806` | ~15 modified |
| Remove `register_parsed_declaration()` | `parse.lua:2817–2842` | ~25 removed |
| Clean `parse_module_document` (remove `splice_values`, `resolve_types_now`, `register_parsed_declaration` calls, `splice_slots` from return) | `parse.lua:2845–2905` | ~20 removed, ~10 modified |
| Clean `parse_island` (remove `splice_values` from opts) | `parse.lua:2653–2700` | ~5 modified |
| Remove `register_parsed_declaration` calls and `splice_values` from LSP | `mlua_document_analysis.lua:300–400` | ~15 removed |
| Remove `default_session.splice_values` and `_register_splice()` | `host.lua:15–22` | ~8 removed |
| Remove `_stmts_quote` and `_stmts_values_binder` | `host_func_values.lua:383–425` | ~40 removed |
| **Total** | 3 files changed, 2 files cleaned | ~150 removed, ~30 modified |

Zero test changes required. Zero new files. Zero new ASDL types. Zero new PVM phases.
```

This is a faithful, self-sustaining architectural decision document. It draws directly from the scout's exhaustive code survey, the knowledge-builder's second-order analysis (the 12 non-obvious observations, particularly #1 about the two paths producing different ASDL shapes, #5 about `splice_slots` being dead data, #6 about the LSP divergence, #10 about forward references), the approach-proposer's three articulated approaches, and the critique's dimension-by-dimension scoring. The constitutional documents (COMPILER_PATTERN.md, PVM_GUIDE.md, LANGUAGE_REFERENCE.md) are quoted precisely to ground the decision in project philosophy. Specific line numbers, function names, and file paths are included throughout so the document is navigable without the workflow context.
