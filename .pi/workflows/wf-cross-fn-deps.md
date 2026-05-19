# Cross-function dependency resolution for moon.func callables 
**Started**: 2026-05-19 11:35:46
---

## Scout Output — 2026-05-19 11:37:06

Now I have a thorough understanding of all the relevant code. Here's the comprehensive report:

---

## Files Retrieved

1. **`lua/moonlift/host_module_values.lua`** (lines 1-252) — ModuleValue, CompiledModule, CompiledFunction types with :compile(), :get(), :__call(), :add_func(), :add_region(), :add_type(), layout_env, to_asdl, C ABI helpers
2. **`lua/moonlift/host_func_values.lua`** (lines 1-433) — FuncValue, FuncBuilder, ParamValue; make_func() for local/export/extern, builder methods (emit, return_, jump, if_, let, var, etc.), api._module_func/export/extern, api.stmts dispatch
3. **`lua/moonlift/host_region_values.lua`** (lines 1-290) — RegionFragValue, BlockValue, ContValue, RegionBuilder, BlockBuilder; region_frag creation, block building, emit within regions, return_region
4. **`lua/moonlift/host_struct_values.lua`** (lines 1-177) — StructValue, DraftStructValue, TypeDeclValue, FieldValue; struct/union/enum/tagged_union creation, draft/seal pattern, type value construction
5. **`lua/moonlift/frontend_pipeline.lua`** (lines 1-66) — Pipeline.Define(T) with parse_and_lower() and lower_module(): parse → open_expand → open_validate → closure_convert → typecheck → layout_resolve → tree_to_back → back_validate
6. **`lua/moonlift/host.lua`** (lines 1-282) — Unified moon.XXX API: CallableFunc with lazy compile-on-first-call, scalar types, compound types, quotes (type/expr/func/region/struct/union/extern), module builder
7. **`lua/moonlift/mlua_run.lua`** (lines 1-1030) — The .mlua runtime: FuncValue:compile() (standalone), FuncValue:__call(), Runtime:eval_island(), loadstring carrier generation, CompiledFunction
8. **`lua/moonlift/back_jit.lua`** (lines 1-186) — Rust Cranelift JIT FFI: Jit:compile() encodes via flatline v4 binary wire format, calls libmoonlift
9. **`lua/moonlift/init.lua`** (lines 1-185) — Public facade: loadstring/loadfile/dofile/eval (hosted), native_loadstring/loadfile/dofile (MOM), emit_object/emit_shared, moon.XXX quote re-export
10. **`lua/moonlift/host_session.lua`** (lines 1-80+) — Session creation, api() registry (installs all host_*_values modules), symbol_key, id, host value management
11. **`lua/moonlift/pvm_surface_cache_values.lua`** (lines 1-102) — add_one_result_cache: generates cache-checking export functions from PVM phase definitions

---

## Key Code

### make_func — The FuncValue constructor (host_func_values.lua:277-312)

```lua
local function make_func(module_value, visibility, name, params, result, builder_fn)
    -- Validates name, params, builds param declarations
    -- Creates a FuncBuilder with arg bindings
    -- If builder_fn is passed, calls it; if it returns a value, auto-returns it
    -- Produces either Tr.FuncExport or Tr.FuncLocal
    -- Returns a FuncValue metatable:
    --   { kind="func", name=name, visibility=visibility, params=ps, result=ret,
    --     func=func, item=Tr.ItemFunc(func), type=api.func_type(...) }
end
```

Key: FuncValue wraps the ASDL `func` node and an `item` (ItemFunc). It is **not callable by itself** — it's a data carrier.

### ModuleValue:compile — The module compile path (host_module_values.lua:203-214)

```lua
function ModuleValue:compile(opts)
    local program = self:_lower_program(opts)  -- MODULE-level lowering
    local Jit = require("moonlift.back_jit")
    local jit = jit_api.jit()
    for name, ptr in pairs(self.extern_symbols or {}) do jit:symbol(name, ptr) end
    for name, ptr in pairs(opts.symbols or {}) do jit:symbol(name, ptr) end
    local artifact = jit:compile(program)
    return setmetatable({ module = self, artifact = artifact, T = T, functions = {} }, CompiledModule)
end
```

The module `:_lower_program(opts)` calls `frontend_pipeline.lower_module(self:to_asdl(), opts)`, which runs the **full pipeline** — open expand, facts, validate, closure convert, typecheck, layout resolve, tree_to_back, back_validate — on the whole module's ASDL.

### ModuleValue:to_asdl (host_module_values.lua:68-74)

```lua
function ModuleValue:to_asdl()
    -- seals all drafts first
    -- collects all self.items (ItemFunc, ItemExtern, ItemType, etc.)
    -- returns Tr.Module(Tr.ModuleTyped(self.name), items)
end
```

This produces a **single MoonTree Module** containing every function, type, and extern that was added to the module. Cross-references resolve within this single ASDL module.

### ModuleValue:add_func / :add_region / :add_type (host_module_values.lua)

```lua
function ModuleValue:add_func(value)
    if value.visibility == "export" then self.exports[value.name] = value end
    return append_item(self, value)
end

function ModuleValue:add_region(value)
    if value.frag then self.region_frags[#self.region_frags + 1] = value.frag end
    return value
end

function ModuleValue:add_type(value) return append_item(self, value) end
```

`append_item` stores the `.item` or `.as_item()` in `self.items[]`, and also tracks type_values separately. Exported functions are indexed by name in `self.exports`.

### ModuleValue:func / :export_func / :extern_func (host_module_values.lua:66-90)

These call `api._module_func/_module_export_func/_module_extern_func` which call `make_func` with the module as the first argument. The builder captures the module_value for context, but the builder API uses `api.expr_ref` and `api.as_moonlift_expr` which are **session-global**, not module-scoped.

### CallableFunc:__call — The "lazy compile" path (host.lua:101-111)

```lua
function CallableFunc:__call(...)
    if not self._compiled then
        local api = self._api
        local m = api.module(self.name .. "_auto")
        m:add_func(self)
        local compiled = m:compile()
        self._compiled = compiled
        self._fn = compiled:get(self.name)
    end
    return self._fn(...)
end
```

This is the `moon.func[[]](args)` path. It:
1. Creates a brand new module named `"<name>_auto"`
2. Adds `self` (the func value) to that module via `m:add_func(self)`
3. Calls `m:compile()` (full ModuleValue:compile path)
4. Gets the compiled function pointer via `compiled:get(self.name)`
5. Caches and calls

The key point: the function is the **only item** in the auto-generated module. Cross-references to other host-defined functions are **not available** in this module.

### mlua_run FuncValue:compile — Standalone compile path (mlua_run.lua:316-389)

```lua
function FuncValue:compile()
    local Pipeline = require("moonlift.frontend_pipeline").Define(T)
    local Tr = T.MoonTree
    -- Collect ALL sibling func items from runtime
    local items = {}
    if runtime and runtime.func_values then
        for name, fv in pairs(runtime.func_values) do
            items[#items + 1] = fv.item or fv:as_item()
        end
    end
    -- Also collect type_decls and extern_funcs from ALL deps
    local merged = empty_deps()
    if runtime and runtime.func_values then
        for _, fv in pairs(runtime.func_values) do
            merged = merge_deps(merged, deps_of(fv))
        end
    end
    for _, td in ipairs(merged.type_decls) do items[#items + 1] = Tr.ItemType(td.decl) end
    for _, ex in ipairs(merged.extern_funcs) do items[#items + 1] = ex.item or ... end

    local lowered = Pipeline.lower_module(Tr.Module(Tr.ModuleSurface, items), ...)
    -- Extract self from checked module
    -- Get artifact, get function pointer, return CompiledFunction
end
```

Contrast with CallableFunc: this collects **all sibling functions** from the runtime, plus their type/extern dependencies, into a single module before lowering. Cross-references among runtime-defined functions resolve.

### mlua_run FuncValue:__call (mlua_run.lua:29-37)

```lua
function FuncValue:__call(...)
    if not self._compiled then
        local runtime = self.runtime
        if runtime and runtime._func_artifacts and runtime._func_artifacts[self.name] then
            self._compiled = runtime._func_artifacts[self.name]
        end
    end
    if not self._compiled then self._compiled = self:compile() end
    return self._compiled(...)
end
```

Checks runtime cache first (sibling JIT artifact reuse), otherwise calls self:compile().

### Pipeline.lower_module (frontend_pipeline.lua:16-47)

```
expanded = OpenExpand.module(module, opts.expand_env)
open report = OpenValidate.validate(OpenFacts.facts_of_module(expanded))
closed = ClosureConvert.module(expanded)
checked = Typecheck.check_module(closed)
resolved = Layout.module(checked.module, opts.layout_env)
program = Lower.module(resolved)
back_report = Validate.validate(program)
```

Returns a table with all intermediate stages for debugging.

---

## Relationships — How the pieces connect

### Two independent compile paths

```
PATH A: ModuleValue:compile (host_module_values.lua:203)
  ModuleValue:to_asdl() → single Tr.Module with all items
  → ModuleValue:_lower_program() → Pipeline.lower_module(module)
  → back_jit.jit():compile(program)
  → CompiledModule with artifact

PATH B: mlua_run FuncValue:compile (mlua_run.lua:316)
  Collects all sibling func values + deps from runtime
  → Builds single Tr.Module with all items
  → Pipeline.lower_module(module)
  → back_jit.jit():compile(program)
  → CompiledFunction with artifact
```

### Cross-function name resolution differences

| Aspect | ModuleValue:compile | CallableFunc:__call (host.lua) | mlua_run FuncValue:compile |
|--------|--------------------|-------------------------------|---------------------------|
| What's in the module | Everything added via module:func/export/extern/struct/union | Just the one function | ALL siblings from runtime.func_values + type/extern deps |
| Cross-ref resolution | Yes — all items in one ASDL module | **No** — only the single function | **Yes** — all siblings plus deps |
| Type decls present | Yes — all types added to module | **No** — no type declarations | Yes — collected from deps |
| Extern funcs present | Yes — all externs added | **No** | Yes — from merged deps |
| Region frags | Yes — region_frags injected into expand_env | **No** — no region_frags | Yes — via runtime.region_frags |

### The CallableFunc gap (host.lua:101-111)

`moon.func[[]](args)` creates a `CallableFunc` which, on first call:
1. Makes a fresh module `"name_auto"`
2. Adds **only itself** via `m:add_func(self)`
3. Compiles that module

The `self` FuncValue carries the parsed function ASDL, but has **no module context** — no type declarations, no region fragments, no extern imports. If the function references a type `Foo` that was defined in a prior `moon.struct[[]]` call, the compile will fail because that type is not in the auto-generated module's item list.

### The mlua_run FuncValue escapes this (mlua_run.lua:316)

The mlua_run Runtime maintains:
- `runtime.func_values` — all func islands ever evaluated (keyed by name)
- `deps_of_value` — weak-map tracking each value's type_decls, extern_funcs, region_frags, expr_frags
- `runtime.region_frags` / `runtime.expr_frags` — all fragment values

When any function compiles, it collects **all** of these into the module. So cross-references among functions defined in the same `.mlua` file work.

### The host_api module path

When using the explicit builder API (`moon.module()`):
```lua
local m = moon.module("mymod")
local f = m:func("add", {...}, ..., function(b) ... end)
local c = m:compile()
c:get("add")(3, 4)
```

This is the **only path** where `ModuleValue:compile()` is called directly. It includes everything added to that module. Exported functions are retrievable via `compiled:get(name)`.

### The mlua_run "callable shortcut" path

```lua
-- Inside a .mlua file:
func add(a: i32, b: i32) -> i32
    return a + b
end
-- The island eval creates a FuncValue with runtime context
-- Then: add(3, 4) triggers FuncValue:__call → self:compile() → works
```

The mlua_run FuncValue:compile collects siblings, so cross-refs among functions in the same file work. But FuncValue:compile does **not** include region_frags or expr_frags from the module-level expansion — those are handled differently (injected into the OpenExpand environment during island evaluation, not during the standalone compile).

### Object file emission (init.lua:114-134)

`moon.emit_object` uses `Pipeline.Define(T).parse_and_lower(src)` — a fresh parse that doesn't involve any host module. This is a one-shot source-to-object path for isolated snippets.

---

## Observations

1. **Three distinct compile paths exist with different cross-reference capabilities**: ModuleValue:compile (richest — module context with all items), mlua_run FuncValue:compile (medium — sibling funcs + deps from runtime), CallableFunc:__call (poorest — single function, no context).

2. **The CallableFunc lazy compile path (host.lua:101) has a cross-reference blind spot**: If `moon.func[[]]` references types or regions defined by other `moon.XXX[[]]` calls, the auto-generated module contains only the single function. The host API has no mechanism to provide module context to `CallableFunc`.

3. **The `_lower_program` on ModuleValue injects region_frags into expand_env**: In `ModuleValue:_lower_program` (host_module_values.lua:193-200), region_frags from `self.region_frags` are wrapped in an `O.ExpandEnv` for open expansion. But the `ModuleValue:func` builder path doesn't have a way to associate region fragments with functions during building — regions are added separately via `module:add_region()`.

4. **mlua_run FuncValue:compile rebuilds the module from scratch each time**: It doesn't cache the lowered program or share it between functions. Each function that triggers `self:compile()` re-runs the full pipeline. However, `_func_artifacts` at the runtime level does cache JIT artifacts by name after first compilation.

5. **FuncValue has no `compile()` method in host_func_values.lua**: The FuncValue type defined in the host API (installed by host_func_values.lua) has methods `:as_item()`, `:__tostring()`, and the FuncBuilder methods, but **no `.compile()` method**. The `compile` and `__call` exist only on:
   - `ModuleValue` (host_module_values.lua) — `.compile()`
   - `CallableFunc` (host.lua) — `.__call()` + lazy compile
   - `mlua_run`'s `FuncValue` (mlua_run.lua) — `.compile()` + `.__call()` (different FuncValue metatable, local to mlua_run)

6. **The pvm_surface_cache_values.lua is unrelated to function compilation**: It's a generative pattern for producing cached PVM phase infrastructure (lookup-cache-insert cycles for memoized phases), not involved in source → native compilation.

7. **CompiledModule:get produces FFI-callable wrappers** (host_module_values.lua:231-241): It casts the artifact function pointer to the C ABI signature derived from the function's type, producing a `CompiledFunction` (different from mlua_run's `CompiledFunction`). These are thin FFI wrappers with no caching or compilation logic.

8. **No mechanism for "host module → standalone function call"**: The `CompiledFunction` returned by `ModuleValue:compile():get(name)` is a plain FFI cdata wrapper, not a FuncValue. There is no interoperability path where a ModuleValue-compiled function is wrapped as a FuncValue for reuse in another module's compilation.
