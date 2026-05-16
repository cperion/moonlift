# MOM Precompiled Binary Reorganization Plan

Audience: an AI coding agent arriving fresh in this repository.

Goal: replace the current mixed hosted/native MOM arrangement with a clean product architecture:

- `moonlift` is the hosted/staging compiler used to build native MOM.
- `mom` links LuaJIT, Rust/Cranelift backend symbols, and a precompiled native MOM object.
- `mom` does **not** embed or run hosted Moonlift compiler Lua modules at startup.
- The LuaJIT linked into `mom` is only the user/metaprogramming runtime and small CLI host.
- Source bytes are read by Rust/LuaJIT and passed as `ptr(u8)+len` directly into precompiled MOM.
- Precompiled MOM provides the `moonlift` API visible to that LuaJIT.
- No compatibility shims are kept. Rename and delete freely when that improves the native compiler dependency graph.

This plan intentionally removes the current ambiguous paths instead of preserving them.

---

## 0. Current State Summary

Read these files before editing:

- `AGENTS.md`
- `lua/moonlift/mom/AGENTS.md`
- `lua/moonlift/mom/PORTING_GUIDE.md`, section 14
- `Makefile`
- `build.rs`
- `src/main.rs`
- `src/mom_main.rs`
- `src/lua_api.rs`
- `src/ffi.rs`
- `lua/moonlift/host_mom.lua`
- `lua/moonlift/mom/init.lua`
- `lua/moonlift/mom/driver/native_entry.mlua`
- `lua/moonlift/mom/schema/init.lua`
- `scripts/emit_mom_precompiled.lua`
- `lua/moonlift/mom_cli.lua`

Important current problems:

1. `src/mom_main.rs` is effectively another hosted Lua compiler runner.
2. `build.rs` embeds all `.lua` files and all MOM `.mlua` sources into `mom`.
3. `lua/moonlift/host_mom.lua` routes MOM CLI compilation through the hosted Lua semantic pipeline.
4. `target/libmom_precompiled.o` is optional; the `mom` binary works without using it.
5. `lua/moonlift/mom/init.lua` loads many `.mlua` files, flattens them by `pairs`, and compiles a unified object, but the linked `mom` binary does not call that object.
6. MOM source module shapes are inconsistent:
   - some return `moon.module(...)`,
   - some return `function(M) ... end`,
   - schema files return plain tables,
   - `back/back_tags.lua` derives constants by running schema `.mlua` files through hosted `mlua_run`.

---

## 1. Final Architecture Contract

### 1.1 Binaries

```text
moonlift binary
  purpose: hosted compiler / staging tool
  may embed hosted Lua compiler sources
  builds libmom_precompiled.o

mom binary
  purpose: product native compiler / runner
  links:
    - static LuaJIT
    - Rust backend symbols
    - target/libmom_precompiled.o
  runtime behavior:
    - no hosted compiler Lua is embedded
    - no hosted compiler Lua is required
    - reads user files to bytes
    - calls native MOM C ABI symbols
    - registers a native-backed `moonlift` Lua module into linked LuaJIT
```

### 1.2 Native MOM ABI

The precompiled object must export a small stable C ABI. Use these symbols as the product boundary:

```c
typedef struct MomBytes {
    uint8_t *data;
    size_t len;
    size_t cap;
} MomBytes;

typedef struct MomDiag {
    int32_t code;
    int32_t phase;
    int32_t offset;
    int32_t line;
    int32_t col;
    int32_t message_start;
    int32_t message_len;
} MomDiag;

typedef struct MomCompileResult {
    int32_t status;       /* 0 ok, nonzero error */
    int32_t diag_count;
    size_t bytes_written;
} MomCompileResult;

/* source -> MLBT v3 wire bytes */
MomCompileResult mom_compile_source_to_wire(
    uint8_t *src,
    size_t src_len,
    uint8_t *wire_out,
    size_t wire_cap,
    MomDiag *diags,
    size_t diag_cap
);

/* source -> object bytes through Rust backend */
MomCompileResult mom_compile_source_to_object(
    uint8_t *src,
    size_t src_len,
    uint8_t *object_out,
    size_t object_cap,
    uint8_t *module_name,
    size_t module_name_len,
    MomDiag *diags,
    size_t diag_cap
);

/* source -> JIT artifact handle through Rust backend */
uint8_t *mom_compile_source_to_artifact(
    uint8_t *src,
    size_t src_len,
    MomDiag *diags,
    size_t diag_cap
);

uint8_t *mom_artifact_getpointer(uint8_t *artifact, uint8_t *name, size_t name_len);
void mom_artifact_free(uint8_t *artifact);

/* Lua package installation into the linked LuaJIT state. */
int32_t mom_luaopen_moonlift(void *lua_state);
```

Notes:

- The native compiler phases produce MLBT v3 as their backend boundary.
- Rust object/JIT emission stays in `src/ffi.rs` and `src/lib.rs`.
- MOM calls Rust backend exports through `extern` declarations in `.mlua`.
- Strings crossing the native boundary are byte slices, never Lua tables.

---

## 2. Final Directory Layout

Reorganize `lua/moonlift/mom/` to this shape:

```text
lua/moonlift/mom/
  AGENTS.md
  PRECOMPILED_MOM_REORG_PLAN.md
  README.md
  PORTING_GUIDE.md

  build/
    manifest.lua          -- ordered source list for precompiled MOM
    assemble.lua          -- hosted-only object assembly helpers
    tags_gen.lua          -- hosted-only schema constants generator

  schema/
    init.lua              -- hosted-only schema loader for checks/generation
    MoonCore.mlua
    MoonBack.mlua
    MoonSource.mlua
    MoonParse.mlua
    MoonType.mlua
    MoonBind.mlua
    MoonTree.mlua
    MoonSem.mlua
    MoonLink.mlua
    MoonVec.mlua

  tags/
    mom_tags.lua          -- generated Lua constants used at staging time

  runtime/
    arena.mlua
    bytes.mlua
    builders.mlua
    diag.mlua
    sets.mlua
    strings.mlua

  parser/
    document_scan.mlua
    lexer.mlua
    cursor.mlua
    parse_type.mlua
    parse_expr.mlua
    parse_stmt.mlua
    parse_item.mlua
    parse_module.mlua
    tree_materialize.mlua

  open/
    facts.mlua
    validate.mlua
    expand.mlua

  typecheck/
    env.mlua
    scalar.mlua
    expr.mlua
    place.mlua
    stmt.mlua
    control.mlua
    func.mlua
    module.mlua

  layout/
    env.mlua
    type.mlua
    field.mlua
    resolve.mlua

  back/
    ids.mlua
    env.mlua
    ops.mlua
    abi.mlua
    cmd.mlua
    memory.mlua
    address.mlua
    expr.mlua
    stmt.mlua
    control.mlua
    func.mlua
    module.mlua
    validate.mlua

  vec/
    facts.mlua
    decide.mlua
    plan.mlua
    lower.mlua
    validate.mlua

  driver/
    compile_source.mlua   -- source bytes -> checked BackProgram tape
    wire.mlua             -- BackProgram tape -> MLBT v3
    backend_ffi.mlua      -- Rust backend ABI externs
    object_driver.mlua
    jit_driver.mlua
    lua_api.mlua          -- mom_luaopen_moonlift and Lua-facing API
    native_entry.mlua     -- exported product ABI symbols

  verify/
    parser_native_ast.lua -- hosted verification harnesses only
```

Delete or rename the current files into this layout. Suggested direct renames:

```text
parser/native_lexer.mlua        -> parser/lexer.mlua
parser/native_core.mlua         -> parser/parse_module.mlua initially, then split
parser/native_tree.mlua         -> parser/tree_materialize.mlua
back/back_abi.mlua              -> back/abi.mlua
back/expr_lower.mlua            -> back/expr.mlua
back/stmt_lower.mlua            -> back/stmt.mlua
typecheck/type_env.mlua         -> typecheck/env.mlua
typecheck/type_scalar.mlua      -> typecheck/scalar.mlua
typecheck/type_expr.mlua        -> typecheck/expr.mlua
typecheck/type_place.mlua       -> typecheck/place.mlua
typecheck/type_stmt.mlua        -> typecheck/stmt.mlua
typecheck/type_control.mlua     -> typecheck/control.mlua
typecheck/type_module.mlua      -> typecheck/module.mlua
parser/native_ast.lua           -> verify/parser_native_ast.lua
```

Remove `lua/moonlift/mom/back/back_tags.lua` after generated `tags/mom_tags.lua` is in use.

---

## 3. Standard MOM Module Shape

### 3.1 Schema modules

Schema modules remain simple plain tables:

```lua
-- lua/moonlift/mom/schema/MoonCore.mlua
local S = {}

S.Name = struct Name
    text: ptr(u8)
    len: index
end

S.Scalar = union Scalar
  | ScalarVoid
  | ScalarBool
  | ScalarI8
  | ScalarI16
  | ScalarI32
  | ScalarI64
  | ScalarU8
  | ScalarU16
  | ScalarU32
  | ScalarU64
  | ScalarF32
  | ScalarF64
  | ScalarRawPtr
  | ScalarIndex
end

return S
```

Rules:

- No phase logic in `schema/*.mlua`.
- No backend calls in `schema/*.mlua`.
- No `moon.module(...)` in `schema/*.mlua`.
- Schema files may reference prior schema modules only through explicit staged Lua imports in the builder/generator path.

### 3.2 Compiler modules

All non-schema `.mlua` compiler modules must use this shape:

```lua
-- lua/moonlift/mom/back/ops.mlua
local T = require("moonlift.mom.tags.mom_tags")

return function(M)

local mb_is_float_scalar = func(s: i32) -> bool
    return s == @{T.BackF32} or s == @{T.BackF64}
end

local mb_lower_compare_op = func(op: i32, scalar: i32) -> i32
    let is_float: bool = mb_is_float_scalar(scalar)
    switch op do
    case @{T.CmpEq} then return select(is_float, @{T.BackFCmpEq}, @{T.BackIcmpEq})
    case @{T.CmpNe} then return select(is_float, @{T.BackFCmpNe}, @{T.BackIcmpNe})
    default then return 0
    end
end

M:local_func("mb_is_float_scalar", mb_is_float_scalar)
M:local_func("mb_lower_compare_op", mb_lower_compare_op)

return M
end
```

Rules:

- No `moon.module(...)` in compiler modules.
- Each module receives the unified assembly object `M`.
- Use `M:type`, `M:local_func`, `M:export_func`, and `M:extern_func` only.
- Private Lua locals are allowed for staged constants and helper names.
- Module-level functions that other modules call must be registered with `M:local_func`.
- Product ABI symbols must be registered with `M:export_func`.
- Every file returns `M` at the end of the installer function.

---

## 4. Implement Unified MOM Assembler

Create `lua/moonlift/mom/build/manifest.lua`:

```lua
local M = {}

M.schema_sources = {
    "lua/moonlift/mom/schema/MoonCore.mlua",
    "lua/moonlift/mom/schema/MoonBack.mlua",
    "lua/moonlift/mom/schema/MoonSource.mlua",
    "lua/moonlift/mom/schema/MoonParse.mlua",
    "lua/moonlift/mom/schema/MoonType.mlua",
    "lua/moonlift/mom/schema/MoonBind.mlua",
    "lua/moonlift/mom/schema/MoonTree.mlua",
    "lua/moonlift/mom/schema/MoonSem.mlua",
    "lua/moonlift/mom/schema/MoonLink.mlua",
    "lua/moonlift/mom/schema/MoonVec.mlua",
}

M.compiler_sources = {
    "lua/moonlift/mom/runtime/arena.mlua",
    "lua/moonlift/mom/runtime/bytes.mlua",
    "lua/moonlift/mom/runtime/builders.mlua",
    "lua/moonlift/mom/runtime/diag.mlua",
    "lua/moonlift/mom/runtime/sets.mlua",
    "lua/moonlift/mom/runtime/strings.mlua",

    "lua/moonlift/mom/back/ids.mlua",
    "lua/moonlift/mom/back/ops.mlua",
    "lua/moonlift/mom/back/env.mlua",
    "lua/moonlift/mom/back/cmd.mlua",
    "lua/moonlift/mom/back/abi.mlua",
    "lua/moonlift/mom/back/memory.mlua",
    "lua/moonlift/mom/back/address.mlua",
    "lua/moonlift/mom/back/expr.mlua",
    "lua/moonlift/mom/back/stmt.mlua",
    "lua/moonlift/mom/back/control.mlua",
    "lua/moonlift/mom/back/func.mlua",
    "lua/moonlift/mom/back/module.mlua",
    "lua/moonlift/mom/back/validate.mlua",

    "lua/moonlift/mom/parser/document_scan.mlua",
    "lua/moonlift/mom/parser/lexer.mlua",
    "lua/moonlift/mom/parser/cursor.mlua",
    "lua/moonlift/mom/parser/parse_type.mlua",
    "lua/moonlift/mom/parser/parse_expr.mlua",
    "lua/moonlift/mom/parser/parse_stmt.mlua",
    "lua/moonlift/mom/parser/parse_item.mlua",
    "lua/moonlift/mom/parser/parse_module.mlua",
    "lua/moonlift/mom/parser/tree_materialize.mlua",

    "lua/moonlift/mom/open/facts.mlua",
    "lua/moonlift/mom/open/validate.mlua",
    "lua/moonlift/mom/open/expand.mlua",

    "lua/moonlift/mom/typecheck/scalar.mlua",
    "lua/moonlift/mom/typecheck/env.mlua",
    "lua/moonlift/mom/typecheck/expr.mlua",
    "lua/moonlift/mom/typecheck/place.mlua",
    "lua/moonlift/mom/typecheck/stmt.mlua",
    "lua/moonlift/mom/typecheck/control.mlua",
    "lua/moonlift/mom/typecheck/func.mlua",
    "lua/moonlift/mom/typecheck/module.mlua",

    "lua/moonlift/mom/layout/env.mlua",
    "lua/moonlift/mom/layout/type.mlua",
    "lua/moonlift/mom/layout/field.mlua",
    "lua/moonlift/mom/layout/resolve.mlua",

    "lua/moonlift/mom/vec/facts.mlua",
    "lua/moonlift/mom/vec/decide.mlua",
    "lua/moonlift/mom/vec/plan.mlua",
    "lua/moonlift/mom/vec/lower.mlua",
    "lua/moonlift/mom/vec/validate.mlua",

    "lua/moonlift/mom/driver/wire.mlua",
    "lua/moonlift/mom/driver/backend_ffi.mlua",
    "lua/moonlift/mom/driver/compile_source.mlua",
    "lua/moonlift/mom/driver/object_driver.mlua",
    "lua/moonlift/mom/driver/jit_driver.mlua",
    "lua/moonlift/mom/driver/lua_api.mlua",
    "lua/moonlift/mom/driver/native_entry.mlua",
}

return M
```

Create `lua/moonlift/mom/build/assemble.lua`:

```lua
local Host = require("moonlift.mlua_run")
local Manifest = require("moonlift.mom.build.manifest")

local A = {}
local MomAssembly = {}
MomAssembly.__index = MomAssembly

local function is_type_value(v)
    return type(v) == "table" and (
        v.kind == "struct" or v.kind == "union" or v.kind == "struct_draft"
    )
end

function A.new(opts)
    opts = opts or {}
    local carrier, rt = Host.loadfile(Manifest.compiler_sources[1])
    local api = rt.session:api()
    local module = api.module(opts.name or "mom")
    local self = setmetatable({
        rt = rt,
        api = api,
        module = module,
        names = {},
        types = {},
        funcs = {},
        exports = {},
        externs = {},
    }, MomAssembly)
    return self, carrier
end

function MomAssembly:reserve(name, kind)
    assert(type(name) == "string" and name ~= "", "MOM item needs a name")
    local prior = self.names[name]
    assert(prior == nil, "duplicate MOM item " .. name .. " as " .. kind .. ", previous " .. tostring(prior))
    self.names[name] = kind
end

function MomAssembly:type(name, value)
    self:reserve(name, "type")
    self.types[#self.types + 1] = value
    self.module:add_type(value)
    self[name] = value
    return value
end

function MomAssembly:local_func(name, value)
    self:reserve(name, "local_func")
    self.funcs[#self.funcs + 1] = value
    self.module:add_func(value)
    self[name] = value
    return value
end

function MomAssembly:export_func(name, value)
    self:reserve(name, "export_func")
    self.exports[name] = true
    self.funcs[#self.funcs + 1] = value
    self.module:add_func(value)
    self[name] = value
    return value
end

function MomAssembly:extern_func(name, value)
    self:reserve(name, "extern_func")
    self.externs[#self.externs + 1] = value
    self.module:add_func(value)
    self[name] = value
    return value
end

function A.load(opts)
    opts = opts or {}
    local assembly, first_carrier = A.new(opts)

    for i, path in ipairs(Manifest.compiler_sources) do
        local carrier
        if i == 1 then
            carrier = first_carrier
        else
            carrier = assert(Host.loadfile(path, { runtime = assembly.rt }))
        end
        local installer = carrier()
        assert(type(installer) == "function", path .. " must return function(M) ... return M end")
        local returned = installer(assembly)
        assert(returned == assembly, path .. " did not return the assembly object")
    end

    return assembly
end

function A.emit_object(opts)
    opts = opts or {}
    local assembly = A.load({ name = opts.name or "mom" })
    return assembly.module:emit_object({ module_name = opts.module_name or "libmom_precompiled" })
end

return A
```

After this exists, delete the old flat `lua/moonlift/mom/init.lua` or replace it with a clear error:

```lua
error("moonlift.mom.init was removed; use moonlift.mom.build.assemble from the hosted build path", 2)
```

---

## 5. Generate Tags Once, Use Them Everywhere

The current `back/back_tags.lua` loads schema `.mlua` files at require time. Replace it with generated constants.

Create `lua/moonlift/mom/build/tags_gen.lua`:

```lua
local Host = require("moonlift.mlua_run")
local Manifest = require("moonlift.mom.build.manifest")

local G = {}

local function derive(union)
    local out = {}
    local variants = assert(union.protocol_variants, "expected union with protocol_variants")
    for i, v in ipairs(variants) do
        local tag = i - 1
        if tag > 0 then out[v.name] = tag end
    end
    return out
end

local function put_all(dst, src)
    for k, v in pairs(src) do
        assert(dst[k] == nil, "duplicate generated tag " .. k)
        dst[k] = v
    end
end

function G.collect()
    local S = {}
    for _, path in ipairs(Manifest.schema_sources) do
        local mod = assert(Host.dofile(path))
        for k, v in pairs(mod) do S[k] = v end
    end

    local T = {}
    put_all(T, derive(assert(S.Cmd)))
    put_all(T, derive(assert(S.BackScalar)))
    put_all(T, derive(assert(S.BackIntOp)))
    put_all(T, derive(assert(S.BackBitOp)))
    put_all(T, derive(assert(S.BackShiftOp)))
    put_all(T, derive(assert(S.BackRotateOp)))
    put_all(T, derive(assert(S.BackFloatOp)))
    put_all(T, derive(assert(S.BackUnaryOp)))
    put_all(T, derive(assert(S.BackCompareOp)))
    put_all(T, derive(assert(S.BackCastOp)))
    put_all(T, derive(assert(S.BackShape)))
    put_all(T, derive(assert(S.BackIntrinsicOp)))
    put_all(T, derive(assert(S.BackVecBinaryOp)))
    put_all(T, derive(assert(S.BackVecCompareOp)))
    put_all(T, derive(assert(S.BackVecMaskOp)))
    put_all(T, derive(assert(S.BackValidationIssue)))
    put_all(T, derive(assert(S.Scalar)))
    put_all(T, derive(assert(S.BinaryOp)))
    put_all(T, derive(assert(S.CmpOp)))
    put_all(T, derive(assert(S.UnaryOp)))
    put_all(T, derive(assert(S.AtomicOrdering)))
    put_all(T, derive(assert(S.AtomicRmwOp)))

    -- Explicit non-schema tags. Keep these documented beside their native use.
    T.MC_IDENTITY = 1
    T.MC_BITCAST = 2
    T.MC_IREDUCE = 3
    T.MC_SEXTEND = 4
    T.MC_UEXTEND = 5
    T.MC_FPROMOTE = 6
    T.MC_FDEMOTE = 7
    T.MC_STOF = 8
    T.MC_UTOF = 9
    T.MC_FTOS = 10
    T.MC_FTOU = 11

    T.MB_BIN_INVALID = 0
    T.MB_BIN_INT = 1
    T.MB_BIN_FLOAT = 2
    T.MB_BIN_BIT = 3
    T.MB_BIN_SHIFT = 4

    T.SC_SURFACE_CAST = 1
    T.SC_TRUNC = 2
    T.SC_ZEXT = 3
    T.SC_SEXT = 4
    T.SC_BITCAST = 5
    T.SC_SAT_CAST = 6

    return T
end

function G.write(path)
    local T = G.collect()
    local keys = {}
    for k in pairs(T) do keys[#keys + 1] = k end
    table.sort(keys)

    local f = assert(io.open(path, "wb"))
    f:write("-- Generated by lua/moonlift/mom/build/tags_gen.lua\n")
    f:write("local T = {}\n")
    for _, k in ipairs(keys) do
        f:write(string.format("T.%s = %d\n", k, T[k]))
    end
    f:write("return T\n")
    f:close()
end

return G
```

Create `scripts/generate_mom_tags.lua`:

```lua
package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path
require("moonlift.mom.build.tags_gen").write("lua/moonlift/mom/tags/mom_tags.lua")
```

Update every MOM compiler module:

```lua
local T = require("moonlift.mom.tags.mom_tags")
```

Remove:

```lua
require("moonlift.mom.back.back_tags")
```

---

## 6. Convert Existing Modules

Use mechanical conversions first, then split large files.

### 6.1 `runtime/builders.mlua`

Current shape:

```lua
local M = moon.module("mom_runtime_builders")
...
M:add_func(...)
return M
```

New shape:

```lua
return function(M)

local i32p = moon.ptr(moon.i32)

local MomI32Builder = M:type("MomI32Builder", struct MomI32Builder
    data: ptr(i32)
    len: index
    cap: index
end)

local mr_i32_builder_push = func(b: ptr(@{MomI32Builder}), value: i32) -> index
    let i: index = b.len
    if i < b.cap then b.data[i] = value end
    b.len = i + as(index, 1)
    return i
end

M:local_func("mr_i32_builder_push", mr_i32_builder_push)
return M
end
```

Do this for each type and function in the file.

### 6.2 `back/ops.mlua`

Current shape:

```lua
local T = require("moonlift.mom.back.back_tags")
local M = moon.module("mom_back_ops")
...
M:add_func(...)
return M
```

New shape:

```lua
local T = require("moonlift.mom.tags.mom_tags")

return function(M)
...
M:local_func("mb_is_float_scalar", mb_is_float_scalar)
...
return M
end
```

### 6.3 Modules already returning `function(M)`

Files like `driver/compile_module.mlua` already use an installer shape. Keep the shape, but enforce:

```lua
return function(M)
...
M:local_func("name", name)
return M
end
```

Do not assign exported functions as `M.name = func` without registering them.

### 6.4 Export product ABI only in `driver/native_entry.mlua`

`driver/native_entry.mlua` should contain all product C ABI exports and only thin orchestration. Example:

```lua
local T = require("moonlift.mom.tags.mom_tags")

return function(M)

local MomCompileResult = M:type("MomCompileResult", struct MomCompileResult
    status: i32
    diag_count: i32
    bytes_written: index
end)

local mom_compile_source_to_wire = func(
    src: ptr(u8), src_len: index,
    wire_out: ptr(u8), wire_cap: index,
    diags: ptr(@{M.MomDiag}), diag_cap: index
) -> @{MomCompileResult}
    return mom_driver_compile_source_to_wire(src, src_len, wire_out, wire_cap, diags, diag_cap)
end

M:export_func("mom_compile_source_to_wire", mom_compile_source_to_wire)
return M
end
```

If Moonlift does not allow returning a struct by value in this ABI reliably, change the API to fill an out pointer:

```moonlift
func mom_compile_source_to_wire(..., result: ptr(MomCompileResult)) -> i32
```

Use the out-pointer form if tests reveal return-by-value ABI issues.

---

## 7. Native Compile Pipeline Implementation

The product path must be:

```text
source ptr+len
  -> document scan / island handling
  -> lexer
  -> parser
  -> typed AST materialization
  -> open facts/expand/validate
  -> typecheck
  -> layout
  -> back lowering
  -> back validation
  -> MLBT v3 wire
  -> Rust backend JIT/object
```

Implement `lua/moonlift/mom/driver/compile_source.mlua` as the only native source-to-wire orchestrator:

```lua
return function(M)

local mom_driver_compile_source_to_wire = func(
    src: ptr(u8), src_len: index,
    wire_out: ptr(u8), wire_cap: index,
    diags: ptr(@{M.MomDiag}), diag_cap: index
) -> @{M.MomCompileResult}
    -- 1. initialize issue builder
    -- 2. scan document
    -- 3. lex Moonlift islands or full file
    -- 4. parse module
    -- 5. materialize AST/tapes
    -- 6. typecheck
    -- 7. lower to BackProgram tape
    -- 8. validate BackProgram tape
    -- 9. write MLBT v3 into wire_out
    -- 10. return status/diag_count/bytes_written
end

M:local_func("mom_driver_compile_source_to_wire", mom_driver_compile_source_to_wire)
return M
end
```

Required design decisions:

- Native phases pass typed structs, builders, and SoA views.
- Diagnostics use `MomDiag` and typed issue tags.
- No phase calls Lua.
- No phase returns strings except source slices represented by `ptr(u8)+len` or interned ids.
- No parser tape bypasses typecheck/layout/back validation in product entrypoints.

---

## 8. Rust Backend FFI Additions

`src/ffi.rs` already exports:

- `moonlift_jit_new`
- `moonlift_jit_free`
- `moonlift_jit_compile_binary`
- `moonlift_artifact_getpointer`
- `moonlift_artifact_free`
- `moonlift_object_compile_binary`

Add a C API helper for object bytes with caller-owned buffer if native MOM needs direct object output without allocation transfer:

```rust
#[unsafe(no_mangle)]
pub extern "C" fn moonlift_object_compile_binary_into(
    data: *const u8,
    len: usize,
    module_name: *const c_char,
    out_data: *mut u8,
    out_cap: usize,
    out_len: *mut usize,
) -> c_int {
    let result: Result<(), MoonliftError> = (|| {
        if data.is_null() || out_data.is_null() || out_len.is_null() {
            return Err(MoonliftError("null pointer passed to moonlift_object_compile_binary_into".to_string()));
        }
        let buf = unsafe { std::slice::from_raw_parts(data, len) };
        let module_name = if module_name.is_null() {
            "mom_object".to_string()
        } else {
            read_cstr(module_name, "object module name")?
        };
        let cmds = parse_back_command_binary(buf)?;
        let artifact = compile_object(&BackProgram::new(cmds), &module_name)?;
        let bytes = artifact.into_bytes();
        unsafe { *out_len = bytes.len(); }
        if bytes.len() > out_cap {
            return Err(MoonliftError("object output buffer too small".to_string()));
        }
        unsafe {
            std::ptr::copy_nonoverlapping(bytes.as_ptr(), out_data, bytes.len());
        }
        Ok(())
    })();
    match result {
        Ok(()) => ok_int(),
        Err(err) => fail_int(err.0),
    }
}
```

Then register this symbol in `src/lua_api.rs` if native MOM JIT tests need it through hosted compilation:

```rust
sym!("moonlift_object_compile_binary_into", crate::ffi::moonlift_object_compile_binary_into);
```

---

## 9. Rewrite `mom_main.rs`

Replace the current hosted `src/mom_main.rs` with a minimal native product binary.

### 9.1 Declare native symbols

```rust
use std::ffi::{c_int, c_void};

#[repr(C)]
struct MomDiag {
    code: i32,
    phase: i32,
    offset: i32,
    line: i32,
    col: i32,
    message_start: i32,
    message_len: i32,
}

#[repr(C)]
struct MomCompileResult {
    status: i32,
    diag_count: i32,
    bytes_written: usize,
}

unsafe extern "C" {
    fn mom_luaopen_moonlift(lua_state: *mut c_void) -> c_int;
    fn mom_compile_source_to_wire(
        src: *mut u8,
        src_len: usize,
        wire_out: *mut u8,
        wire_cap: usize,
        diags: *mut MomDiag,
        diag_cap: usize,
    ) -> MomCompileResult;
    fn mom_compile_source_to_artifact(
        src: *mut u8,
        src_len: usize,
        diags: *mut MomDiag,
        diag_cap: usize,
    ) -> *mut u8;
    fn mom_artifact_getpointer(artifact: *mut u8, name: *mut u8, name_len: usize) -> *mut c_void;
    fn mom_artifact_free(artifact: *mut u8);
}
```

### 9.2 CLI parsing in Rust

Move product CLI parsing from `lua/moonlift/mom_cli.lua` into Rust. Delete `lua/moonlift/mom_cli.lua` after the Rust CLI is working.

Supported commands:

```text
mom status
mom run [--call NAME] [--ret i32|void] [--arg-i32 N ...] FILE
mom --emit-object -o OUT.o [--module-name NAME] FILE
```

`status` should report native precompiled MOM availability by calling `mom_compile_source_to_wire` on a tiny program:

```moonlift
func main() -> i32
    return 0
end
```

### 9.3 LuaJIT initialization

Use LuaJIT only when executing `.mlua` metaprogramming files. Register native `moonlift` package by calling `mom_luaopen_moonlift`.

Skeleton:

```rust
fn init_luajit() -> mlua::Result<mlua::Lua> {
    let lua = unsafe { mlua::Lua::unsafe_new() };
    let mut state = std::ptr::null_mut();
    unsafe {
        lua.exec_raw::<()>((), |s| state = s)?;
        let rc = mom_luaopen_moonlift(state.cast::<c_void>());
        if rc != 0 {
            return Err(mlua::Error::RuntimeError("mom_luaopen_moonlift failed".to_string()));
        }
    }
    Ok(lua)
}
```

Do not import `mod embedded_lua;` in `mom_main.rs`.
Do not call `require("moonlift.mlua_run")` in `mom_main.rs`.
Do not install `_host_compile` in `mom_main.rs`.

---

## 10. Split `embedded_lua` Generation by Binary

`build.rs` currently generates one `src/embedded_lua.rs` used by both binaries. Change this.

### 10.1 Generate hosted-only embedded Lua

Rename generated file:

```text
src/embedded_hosted_lua.rs
```

Use it only in `src/main.rs`.

`src/main.rs` changes:

```rust
mod embedded_hosted_lua;
```

and replace calls:

```rust
embedded_hosted_lua::embedded_modules()
embedded_hosted_lua::embedded_mlua_sources()
```

### 10.2 Do not generate embedded Lua for `mom`

Remove all embedded Lua usage from `src/mom_main.rs`.

### 10.3 Build script behavior

`build.rs` should:

- always build/link LuaJIT for both binaries,
- generate `embedded_hosted_lua.rs` for `moonlift`,
- require `target/libmom_precompiled.o` when compiling bin `mom`,
- not embed MOM `.mlua` sources into `mom`.

Use an env var from `Makefile`:

```rust
fn link_mom_precompiled() {
    let path = std::env::var("MOM_OBJ_PATH")
        .unwrap_or_else(|_| "target/libmom_precompiled.o".to_string());
    let obj = PathBuf::from(path);
    if !obj.exists() {
        panic!("MOM_OBJ_PATH object missing: {}", obj.display());
    }
    let abs = std::fs::canonicalize(&obj).unwrap();
    println!("cargo:rustc-link-arg-bin=mom={}", abs.display());
    println!("cargo:rerun-if-changed={}", abs.display());
}
```

---

## 11. Rewrite Build Scripts

### 11.1 `Makefile`

Replace the top-level build graph with:

```make
MOONLIFT  = target/release/moonlift
MOM       = target/release/mom
LUAJIT    = .vendor/LuaJIT/src
MOM_OBJ   = target/libmom_precompiled.o

.PHONY: all clean mom-obj mom-tags test-mom

all: $(MOONLIFT) $(MOM)

$(LUAJIT)/libluajit.a:
	$(MAKE) -C $(LUAJIT) CFLAGS="-fPIC"
	ln -sf libluajit.a $(LUAJIT)/libluajit-5.1.a

$(MOONLIFT): $(LUAJIT)/libluajit.a
	LUAJIT_LIB=$(CURDIR)/$(LUAJIT)/libluajit-5.1.a \
	LUAJIT_INCLUDE=$(CURDIR)/$(LUAJIT) \
	cargo build --release --bin moonlift

mom-tags: $(MOONLIFT)
	$(MOONLIFT) scripts/generate_mom_tags.lua

$(MOM_OBJ): $(MOONLIFT) mom-tags
	@mkdir -p target
	MOM_OBJ_PATH=$(MOM_OBJ) $(MOONLIFT) scripts/emit_mom_precompiled.lua

mom-obj: $(MOM_OBJ)

$(MOM): $(LUAJIT)/libluajit.a $(MOM_OBJ)
	LUAJIT_LIB=$(CURDIR)/$(LUAJIT)/libluajit-5.1.a \
	LUAJIT_INCLUDE=$(CURDIR)/$(LUAJIT) \
	MOM_OBJ_PATH=$(CURDIR)/$(MOM_OBJ) \
	cargo build --release --bin mom

clean:
	$(MAKE) -C $(LUAJIT) clean
	cargo clean
	rm -f $(LUAJIT)/libluajit-5.1.a src/embedded_hosted_lua.rs $(MOM_OBJ)

test-mom: $(MOM)
	luajit tests/test_mom_cli.lua
```

### 11.2 `scripts/emit_mom_precompiled.lua`

Replace with:

```lua
package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local output_path = os.getenv("MOM_OBJ_PATH") or "target/libmom_precompiled.o"
local output_dir = output_path:gsub("/[^/]+$", "")
if output_dir ~= "" then os.execute("mkdir -p " .. output_dir) end

local Assemble = require("moonlift.mom.build.assemble")
local artifact = Assemble.emit_object({
    name = "mom",
    module_name = "libmom_precompiled",
})
artifact:write(output_path)
print(output_path)
```

Delete `scripts/emit_mom_precompiled.mlua`.

---

## 12. Lua API Provided by Precompiled MOM

Implement `lua/moonlift/mom/driver/lua_api.mlua` with the native Lua-facing API.

Minimum product behavior:

```lua
local moon = require("moonlift")
local chunk = moon.loadfile("program.mlua")
local compiled = chunk()
local fn = compiled:get("main")
```

Because the LuaJIT in `mom` should execute user/metaprogramming Lua, the native `moonlift` package must expose:

```lua
moon.loadstring(src, name, opts)
moon.loadfile(path, opts)
moon.dofile(path, opts, ...)
moon.emit_object(src, path, name)
moon.native_loadstring(src, name)
moon.native_loadfile(path)
moon.native_dofile(path, opts)
```

These functions should call native MOM ABI symbols, not hosted compiler modules.

Implementation strategy:

1. `mom_luaopen_moonlift(void *L)` creates a Lua table.
2. It pushes C-callable wrappers generated by Moonlift native functions.
3. Wrappers read Lua strings through Lua C API:
   - `lua_tolstring`
   - `lua_pushlstring`
   - `lua_pushinteger`
   - `lua_pushboolean`
   - `lua_error`
4. Wrappers call `mom_compile_source_to_artifact` or `mom_compile_source_to_object`.
5. Artifact userdata/table exposes:
   - `getpointer(name)`
   - `cfunction(name)` where possible
   - `free()`

If direct Lua C API wrappers in Moonlift become too large, implement `mom_luaopen_moonlift` in Rust and have it call the native MOM C ABI. The rule remains: Rust wrapper is thin and does not call hosted compiler Lua.

---

## 13. Tests to Rewrite/Add

### 13.1 Delete tests that assert hosted MOM CLI behavior

Rewrite `tests/test_mom_cli.lua`. It must fail if `mom status` mentions `tree_to_back` or hosted Lua pipeline.

New assertions:

```lua
local ok, _, out = capture("./target/release/mom status")
assert(ok, out)
assert(out:match("precompiled native MOM"), out)
assert(not out:match("tree_to_back"), out)
assert(not out:match("hosted Lua"), out)
```

### 13.2 Add linked-symbol test

Create `tests/test_mom_precompiled_symbols.lua`:

```lua
local function capture(cmd)
    local p = assert(io.popen(cmd .. " 2>&1", "r"))
    local out = p:read("*a")
    local ok, _, code = p:close()
    return ok, code, out
end

local ok, _, out = capture("nm -g target/release/mom | grep mom_compile_source_to_wire")
assert(ok, out)
print("mom precompiled symbols ok")
```

### 13.3 Add no-embedded-hosted-compiler test

Create `tests/test_mom_no_hosted_embed.lua`:

```lua
local function capture(cmd)
    local p = assert(io.popen(cmd .. " 2>&1", "r"))
    local out = p:read("*a")
    local ok, _, code = p:close()
    return ok, code, out
end

local ok, _, out = capture("strings target/release/mom | grep 'moonlift.tree_typecheck' || true")
assert(not out:match("moonlift.tree_typecheck"), out)

ok, _, out = capture("strings target/release/mom | grep 'moonlift.mlua_run' || true")
assert(not out:match("moonlift.mlua_run"), out)

print("mom no hosted embed ok")
```

### 13.4 Keep focused native module tests

Update paths/names in tests after renames:

```text
tests/test_mom_groundwork.lua
tests/test_mom_document_scan.lua
tests/test_mom_native_lexer.mlua
tests/test_mom_native_core.lua
tests/test_mom_native_tree.lua
tests/test_mom_typecheck.lua
tests/test_mom_vec.lua
tests/test_mom_wire.lua
```

Any test that compiles a single module must use a helper that creates a `MomAssembly` and installs dependencies required by that module. Do not reintroduce `moon.module(...)` as a product pattern.

---

## 14. Deletions

Delete these after replacements are complete:

- `lua/moonlift/host_mom.lua`
- `lua/moonlift/mom_cli.lua`
- `lua/moonlift/mom/back/back_tags.lua`
- `scripts/emit_mom_precompiled.mlua`
- `src/embedded_lua.rs` generated path
- `_MOONLIFT_EMBEDDED_MLUA` setup in Rust
- hosted MOM status messages mentioning Lua semantic pipeline

Update `lua/moonlift/init.lua` so it does not export `host_mom` from the product `mom` path. The hosted `moonlift` binary may expose hosted APIs under explicit hosted names if needed, but product `mom` must not depend on them.

---

## 15. Progress Checklist

### Preparation

- [ ] Read `AGENTS.md`.
- [ ] Read `lua/moonlift/mom/AGENTS.md`.
- [ ] Read `lua/moonlift/mom/PORTING_GUIDE.md` section 14.
- [ ] Run `make clean` once to remove generated stale files.
- [ ] Record current failing/passing baseline with `cargo build --release --bin moonlift`.

### Module Layout

- [ ] Create `lua/moonlift/mom/build/manifest.lua`.
- [ ] Create `lua/moonlift/mom/build/assemble.lua`.
- [ ] Create `lua/moonlift/mom/build/tags_gen.lua`.
- [ ] Create `lua/moonlift/mom/tags/`.
- [ ] Rename parser files to final names.
- [ ] Rename typecheck files to final names.
- [ ] Rename backend files to final names.
- [ ] Move verification-only Lua files to `lua/moonlift/mom/verify/`.
- [ ] Update all test paths after renames.

### Module Shape Conversion

- [ ] Convert `runtime/*.mlua` to `return function(M)`.
- [ ] Convert `back/*.mlua` to `return function(M)`.
- [ ] Convert `parser/*.mlua` to `return function(M)`.
- [ ] Convert `typecheck/*.mlua` to `return function(M)`.
- [ ] Convert `layout/*.mlua` to `return function(M)`.
- [ ] Convert `vec/*.mlua` to `return function(M)`.
- [ ] Convert `driver/*.mlua` to `return function(M)`.
- [ ] Replace all `M:add_func` with `M:local_func`, `M:export_func`, or `M:extern_func`.
- [ ] Remove all `moon.module(...)` from non-schema MOM compiler modules.
- [ ] Remove all imports of `moonlift.mom.back.back_tags`.
- [ ] Generate `lua/moonlift/mom/tags/mom_tags.lua`.

### Native Driver

- [ ] Implement `runtime/diag.mlua` with `MomDiag` and diagnostic builder types.
- [ ] Implement `runtime/bytes.mlua` for byte slices/builders.
- [ ] Implement or rename `driver/wire.mlua` as the single MLBT writer.
- [ ] Implement `driver/backend_ffi.mlua` against Rust `src/ffi.rs` exports.
- [ ] Implement `driver/compile_source.mlua` as source-to-wire orchestrator.
- [ ] Implement `driver/object_driver.mlua`.
- [ ] Implement `driver/jit_driver.mlua`.
- [ ] Implement `driver/lua_api.mlua` or a thin Rust Lua API that calls native MOM C ABI.
- [ ] Implement `driver/native_entry.mlua` exported product symbols.

### Rust/Build

- [ ] Rename generated Rust file to `src/embedded_hosted_lua.rs`.
- [ ] Update `src/main.rs` to use `embedded_hosted_lua`.
- [ ] Remove embedded Lua module usage from `src/mom_main.rs`.
- [ ] Rewrite `src/mom_main.rs` around native MOM extern symbols.
- [ ] Update `src/ffi.rs` with any missing backend helper exports.
- [ ] Update `src/lua_api.rs` symbol registration for hosted tests.
- [ ] Make `build.rs` require `MOM_OBJ_PATH`/`target/libmom_precompiled.o` for bin `mom`.
- [ ] Update `Makefile` to build `moonlift -> tags -> MOM object -> mom`.
- [ ] Rewrite `scripts/emit_mom_precompiled.lua` to use `build.assemble`.
- [ ] Delete `scripts/emit_mom_precompiled.mlua`.

### Product Cleanup

- [ ] Delete `lua/moonlift/host_mom.lua` or move it under a verification-only name outside product graph.
- [ ] Delete `lua/moonlift/mom_cli.lua` after Rust CLI is complete.
- [ ] Delete `lua/moonlift/mom/back/back_tags.lua`.
- [ ] Remove `_MOONLIFT_EMBEDDED_MLUA` from Rust code.
- [ ] Ensure `mom` binary does not require `moonlift.mlua_run`.
- [ ] Ensure `mom` binary does not require `moonlift.tree_typecheck`.
- [ ] Ensure `mom status` reports precompiled native MOM.

### Tests

- [ ] Update single-module MOM tests to new file names.
- [ ] Add `tests/test_mom_precompiled_symbols.lua`.
- [ ] Add `tests/test_mom_no_hosted_embed.lua`.
- [ ] Rewrite `tests/test_mom_cli.lua` expectations.
- [ ] Run `make`.
- [ ] Run `luajit tests/test_mom_precompiled_symbols.lua`.
- [ ] Run `luajit tests/test_mom_no_hosted_embed.lua`.
- [ ] Run `luajit tests/test_mom_cli.lua`.
- [ ] Run focused MOM tests listed in `lua/moonlift/mom/AGENTS.md`.

---

## 16. Acceptance Criteria

The cleanup is complete only when all are true:

- [ ] `make` builds `target/release/moonlift`, `target/libmom_precompiled.o`, and `target/release/mom`.
- [ ] `target/release/mom` links `mom_compile_source_to_wire` and related native symbols.
- [ ] `target/release/mom` does not contain embedded hosted compiler module names such as `moonlift.tree_typecheck` or `moonlift.mlua_run`.
- [ ] `mom status` reports the precompiled native MOM path.
- [ ] `mom run --call main file.mlua` compiles through native MOM and executes via Rust backend artifact.
- [ ] `mom --emit-object -o out.o file.mlua` emits object bytes through native MOM -> MLBT -> Rust backend.
- [ ] No product path imports `lua/moonlift/host_mom.lua`.
- [ ] No product path imports `lua/moonlift/mom_cli.lua`.
- [ ] No non-schema MOM compiler module uses `moon.module(...)`.
- [ ] No native compiler module calls hosted Lua compiler modules.
- [ ] Schema files remain plain returned tables.
- [ ] Compiler modules use `return function(M) ... return M end`.
- [ ] Exported product ABI exists only in `driver/native_entry.mlua` and Lua package API code.

---

## 17. Grep Checks

Run these before declaring completion:

```sh
rg 'moon\.module\(' lua/moonlift/mom --glob '*.mlua'
# Expected: no matches outside schema if schema ever needs none as well.

rg 'moonlift\.mom\.back\.back_tags' lua tests scripts
# Expected: no matches.

rg 'host_mom|mom_cli|mlua_run|tree_typecheck' src/mom_main.rs lua/moonlift/mom scripts tests/test_mom_cli.lua
# Expected: no product-path usage.

nm -g target/release/mom | rg 'mom_compile_source_to_wire|mom_luaopen_moonlift'
# Expected: exported/linked symbols present.

strings target/release/mom | rg 'moonlift\.tree_typecheck|moonlift\.mlua_run'
# Expected: no output.
```

---

## 18. Discipline Rules While Executing

- Keep hosted verification harnesses outside the native compiler dependency graph.
- Do not introduce Lua materialization into product MOM.
- Do not use stringly dispatch for native compiler decisions.
- Do not hide state in side tables.
- Do not make `libmom_precompiled.o` optional for the `mom` binary.
- Do not preserve old module names merely to avoid test edits.
- Keep builder capacity behavior explicit: append always advances `len`, store only when `len < cap`.
- Every new native module must have a focused test or an updated existing test.
- When a design choice is required, document the chosen typed interface in the module header.
