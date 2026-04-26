# Moonlift Lua Table Builder Backend Design

Status: design document for making **generic JSON -> eager Lua tables** fast.

This document answers why Moonlift is currently slower than `lua-cjson` for
standard eager Lua table decoding and defines the proper ASDL/PVM architecture
for fixing it.

The key point:

```text
Moonlift's native JSON parser is fast.
The slow part is rebuilding Lua tables from the tape in Lua.
```

To compete with `lua-cjson` on generic table output, Moonlift must stop doing:

```text
native parse -> tape arrays -> Lua recursive table rebuild
```

and instead support:

```text
native parse/control machine -> Lua C API table construction
```

This requires an explicit backend/object-builder layer, not ad hoc Lua helper
mutation.

---

## 1. Problem statement

Current generic decode path:

```text
JSON bytes
  -> Moonlift native parser
  -> compact tape arrays
  -> Lua tape walker
  -> Lua string slicing/unescape
  -> Lua table allocation/population
  -> Lua object graph
```

`lua-cjson` path:

```text
JSON bytes
  -> C parser
  -> Lua C API table/value creation while parsing
  -> Lua object graph
```

Benchmarks show:

```text
Moonlift tape decode: fast
Moonlift lazy view: competitive
Moonlift projection: fast
Moonlift eager table rebuild: slow
```

So the parser is not the bottleneck. The Lua object rebuild is.

---

## 2. Architectural goal

Add a new explicit backend/execution target:

```text
Lua table builder commands
```

The parser/control program should emit flat commands or call flat builder
operations that are executed with direct `lua_State*` access.

This must remain ASDL/PVM disciplined:

```text
source/hosted fragments
  -> explicit ASDL representation of Lua object construction intent
  -> phase lowering to flat Lua object commands
  -> final loop over commands / native runtime builder
```

No hidden meaning in:

- opaque Lua tables
- captured mutable state
- string tags
- parser-only magic
- Rust/C-side ad hoc IR

---

## 3. Non-goals

This is not intended to replace all JSON paths.

Keep the current paths:

```text
json_library.lua / json.moon2
  - validation
  - tape decode
  - lazy view
  - eager Lua rebuild convenience

json_codegen.lua
  - specialized projection decoders
```

The Lua table builder backend is specifically for:

```text
generic JSON -> eager Lua table/object graph
```

It should coexist with tape/view/projection.

---

## 4. Design options

### Option A: Native Lua module / state-aware backend

A native module loaded by LuaJIT has direct `lua_State*` access and exposes:

```lua
local json = require("moonlift_json_native")
local obj = json.decode(src)
```

Implementation can use Lua C API:

```c
lua_createtable
lua_pushlstring
lua_pushnumber / lua_pushinteger
lua_pushboolean
lua_rawseti
lua_setfield / lua_rawset
```

Pros:

- fastest route to cjson-like eager table construction
- no need to own the whole LuaJIT process
- natural Lua errors
- userdata/session support possible
- incremental path from current FFI design

Cons:

- requires C/Rust native module with Lua C API
- more lifetime/error-handling complexity than FFI-only APIs
- build integration needed

### Option B: Fully owned LuaJIT state

Moonlift owns `lua_State*`, parser, sessions, native modules, and hosted syntax.

Pros:

- maximum integration
- best lifetime/session/cache model
- parser hooks possible long term

Cons:

- large architectural jump
- unnecessary for initial Lua table builder

### Option C: Keep FFI only and rebuild in Lua

Pros:

- minimal native integration

Cons:

- unlikely to match cjson for eager tables
- keeps expensive Lua-side object rebuild

### Recommendation

Start with **Option A**:

```text
state-aware native Lua module / backend layer
```

Do not jump straight to full owned LuaJIT state. Most performance and ergonomics
wins for eager table decode come from direct Lua C API object construction, and a
native module is enough for that.

---

## 5. ASDL-first representation

We need explicit ASDL for Lua object construction commands.

Create a new low-level module, tentatively:

```text
Moon2LuaObj
```

or if kept inside existing schema temporarily:

```text
Moon2HostObj
```

Preferred name:

```text
Moon2LuaObj
```

because this target is specifically Lua runtime object construction.

### 5.1 Core IDs

```asdl
LuaObjId = (string text) unique
LuaObjKeyId = (string text) unique
LuaObjProgramId = (string text) unique
```

### 5.2 Value sources

A command stream needs to push values from parser state:

```asdl
LuaObjScalar = LuaObjI32 | LuaObjI64 | LuaObjF64 | LuaObjBool | LuaObjNull

LuaObjStringSource
  = LuaObjStringLiteral(string value)
  | LuaObjStringSlice(Moon2Back.BackValId base, Moon2Back.BackValId start, Moon2Back.BackValId len)
  | LuaObjStringEscapedSlice(Moon2Back.BackValId base, Moon2Back.BackValId start, Moon2Back.BackValId len)
```

But mixing `BackValId` directly into LuaObj may be awkward. A cleaner split is:

```text
Moonlift control/parser computes values
Lua object builder runtime receives concrete primitive arguments
```

So the flat command target may be **runtime operations**, not static commands
containing `BackValId`.

### 5.3 Builder commands

Conceptual command set:

```asdl
LuaObjCmd
  = LuaObjBeginObject(number expected_fields)
  | LuaObjBeginArray(number expected_items)
  | LuaObjEndObject
  | LuaObjEndArray
  | LuaObjSetKeyString(string key)
  | LuaObjSetKeySlice
  | LuaObjAppendArray
  | LuaObjSetObjectField
  | LuaObjPushNull
  | LuaObjPushBool(boolean value)
  | LuaObjPushI64
  | LuaObjPushF64
  | LuaObjPushStringSlice
  | LuaObjPushEscapedStringSlice
```

However, some commands need dynamic values from the parser. That suggests two
layers:

1. **Builder API operations** callable from generated native parser code.
2. **Optional flat command facts** for static validation/planning.

### 5.4 Better design: builder operations as backend externs

Represent Lua object building as typed host calls in the object language:

```moonlift
extern func lua_obj_begin_object(builder: ptr, expected: i32) -> i32
extern func lua_obj_begin_array(builder: ptr, expected: i32) -> i32
extern func lua_obj_end_object(builder: ptr) -> i32
extern func lua_obj_end_array(builder: ptr) -> i32
extern func lua_obj_key_slice(builder: ptr, p: ptr(u8), start: i32, len: i32) -> i32
extern func lua_obj_string_slice(builder: ptr, p: ptr(u8), start: i32, len: i32) -> i32
extern func lua_obj_i64(builder: ptr, value: i64) -> i32
extern func lua_obj_f64(builder: ptr, value: f64) -> i32
extern func lua_obj_bool(builder: ptr, value: i32) -> i32
extern func lua_obj_null(builder: ptr) -> i32
```

But this hides too much meaning in extern names if used directly.

Therefore add ASDL facts/commands that lower to extern declarations/calls:

```asdl
LuaObjOp
  = LuaObjBeginObject
  | LuaObjEndObject
  | LuaObjBeginArray
  | LuaObjEndArray
  | LuaObjKeySlice
  | LuaObjStringSlice
  | LuaObjI64
  | LuaObjF64
  | LuaObjBool
  | LuaObjNull
```

and a lowering phase:

```text
Moon2LuaObjOp -> Moon2Back.CmdCall(Extern)
```

This keeps semantic intent explicit while allowing implementation through native
externs.

---

## 6. Runtime builder model

A native runtime builder owns a Lua stack construction context.

Conceptual C/Rust-side structure:

```text
LuaObjBuilder
  lua_State* L
  stack of container frames
  current pending key
  error status
```

### 6.1 Stack discipline

Builder operations must be deterministic and stack-safe.

Pseudo behavior:

```text
begin_object:
  lua_createtable(L, 0, expected_fields)
  if parent exists: attach as pending value or array element
  push frame(object)

key_slice:
  push Lua string key or store pending key reference

value:
  push Lua value
  if parent object: set pending key
  if parent array: rawseti(next_index)
  if no parent: set root

end_object:
  pop object frame
  if no parent: root object complete
```

### 6.2 Null representation

Options:

1. use `cjson.null` compatible sentinel if available
2. use Moonlift `Json.null` userdata/table sentinel
3. use Lua `nil` and lose object fields / array positions (bad)

Use explicit sentinel:

```lua
Json.null
```

Native module should be given or create a registry reference for null sentinel.

### 6.3 Error handling

Builder operations return status codes:

```text
0 success
<0 builder error
```

Or raise Lua errors directly if native module owns `lua_State*`.

For generated parser code, returning status is easier:

```moonlift
if lua_obj_begin_object(builder, expected) != 0 then yield ERR_BUILDER end
```

The outer native Lua function converts final status to Lua return/error.

---

## 7. JSON parser integration shapes

### 7.1 Generic table decoder

Expose:

```lua
local Json = require("moonlift.json_native")
local value = Json.decode(src)
```

Internal pipeline:

```text
Lua string src
  -> native builder initialized with lua_State*
  -> compiled Moonlift JSON parser called with (p, n, builder_ptr, stack...)
  -> parser calls LuaObj operations while parsing
  -> native function returns root Lua value
```

### 7.2 Generated table projection

Expose:

```lua
local decoder = Json.project_table {
  id = "i32",
  active = "bool",
}
local value = decoder(src)
```

This can build only selected output table fields directly:

```text
{ id = 42, active = true }
```

This avoids both full generic table and out-buffer conversion.

### 7.3 Existing projection buffer path remains

Keep:

```lua
projector:decode_i32(src, out)
```

for maximum speed.

---

## 8. How hosted continuation fragments fit

Current JSON projection generator already shows the desired composition pattern:

```text
skip_ws
skip_string
parse_i32
parse_bool
skip_value
field dispatch
```

For generic table decode, add builder-emitting fragments:

```moonlift
region emit_object_begin(builder: ptr; ok: cont(), err: cont(code: i32))
region emit_object_end(builder: ptr; ok: cont(), err: cont(code: i32))
region emit_array_begin(builder: ptr; ok: cont(), err: cont(code: i32))
region emit_key_slice(builder: ptr, p: ptr(u8), start: i32, len: i32; ok: cont(), err: cont(code: i32))
region emit_string_slice(...)
region emit_i64(...)
region emit_bool(...)
region emit_null(...)
```

The JSON parser wires semantic parse exits into builder operations:

```moonlift
block got_key(start: i32, len: i32, next: i32)
    emit lua_key_slice(builder, p, start, len; ok = after_key, err = builder_error)
end

block got_string(start: i32, len: i32, next: i32)
    emit lua_string_slice(builder, p, start, len; ok = after_value, err = builder_error)
end
```

This preserves the continuation-language architecture.

---

## 9. Required ASDL/PVM work

### 9.1 New ASDL module

Add `Moon2LuaObj` with explicit operation/fact types.

Candidate:

```asdl
module Moon2LuaObj {
  LuaObjBuilderType = LuaObjBuilder
  LuaObjStatus = LuaObjOk | LuaObjErr(string reason) unique

  LuaObjOp = LuaObjBeginObject
           | LuaObjEndObject
           | LuaObjBeginArray
           | LuaObjEndArray
           | LuaObjKeySlice
           | LuaObjStringSlice
           | LuaObjEscapedStringSlice
           | LuaObjI64
           | LuaObjF64
           | LuaObjBool
           | LuaObjNull

  LuaObjCall = (Moon2LuaObj.LuaObjOp op, Moon2Type.Type* params, Moon2Type.Type result) unique
}
```

### 9.2 Lowering phase

Define phase:

```text
lua_obj_op_to_extern
```

Question:

```text
Which backend extern declaration/call corresponds to this Lua object operation?
```

Output:

```text
Moon2Back commands / extern refs
```

### 9.3 Validation phase

Validate generated builder usage:

- key emitted only inside object
- object/array begin/end balanced
- exactly one root produced
- no value after root complete
- no missing object key

Some of this may be dynamic for JSON, but static fragments can still produce
facts.

This should be explicit:

```asdl
LuaObjFact
LuaObjReject
LuaObjDecision
```

Do not rely only on runtime builder errors.

---

## 10. Native runtime implementation

### 10.1 Rust vs C

Current backend is Rust-heavy. Lua C API integration from Rust is possible but
requires careful bindings.

Options:

- C shim exposing builder operations and loading Lua module
- Rust `cdylib` with LuaJIT FFI/C API bindings
- hybrid: C Lua module calls Rust backend/parser and owns Lua stack builder

Recommended first implementation:

```text
C shim/native Lua module for Lua C API builder
  + calls existing compiled function pointer / runtime externs
```

But given current project structure, a Rust `cdylib` Lua module may be cleaner if
LuaJIT headers/bindings are available.

### 10.2 Minimal native API

```c
int luaopen_moonlift_json_native(lua_State* L);
```

Lua API:

```lua
local N = require("moonlift_json_native")
local decoder = N.new_decoder(compiled_artifact_or_source, opts)
local obj = decoder:decode(src)
decoder:free()
```

Or if compilation remains in Lua:

```lua
local parser_ptr = artifact:getpointer(...)
local decoder = N.new_decoder(parser_ptr, artifact, opts)
local obj = decoder:decode(src)
```

The decoder userdata retains:

- parser function pointer
- artifact/session reference
- Lua null sentinel ref
- stack buffers if reusable

### 10.3 Builder extern calls

Generated parser signature could be:

```c
int32_t json_decode_lua_table(
  const uint8_t* p,
  int32_t n,
  void* builder,
  int32_t* stack_next,
  int32_t* stack_kind,
  int32_t stack_cap
)
```

Builder externs called by generated code:

```c
int32_t ml_lua_obj_begin_object(void* builder, int32_t expected);
int32_t ml_lua_obj_end_object(void* builder);
int32_t ml_lua_obj_key_slice(void* builder, const uint8_t* p, int32_t start, int32_t len);
...
```

Need to ensure Cranelift/JIT can resolve these extern symbols.

---

## 11. Incremental implementation plan

### Phase 1 — Builder runtime prototype

- [ ] Implement native Lua module skeleton
- [ ] Create `LuaObjBuilder` userdata/internal object
- [ ] Implement manual builder API callable from Lua for tests:
  - [ ] begin_object
  - [ ] key
  - [ ] value_i32
  - [ ] value_bool
  - [ ] value_null
  - [ ] end_object
  - [ ] root
- [ ] Test building `{ id = 42, active = true, none = Json.null }`

### Phase 2 — Extern-call integration

- [ ] Register builder extern functions with Moonlift JIT/backend
- [ ] Compile tiny Moonlift function that calls builder ops
- [ ] Return built Lua object from native module
- [ ] Ensure artifact/session lifetime retention

### Phase 3 — ASDL operation layer

- [ ] Add `Moon2LuaObj` ASDL module
- [ ] Add explicit `LuaObjOp` variants
- [ ] Add lowering from LuaObj ops to extern declarations/calls
- [ ] Add facts/validation for simple builder programs

### Phase 4 — JSON table decoder generation

- [ ] Generate generic JSON parser that calls builder ops directly
- [ ] Support strings, numbers, bool, null
- [ ] Support arrays/objects
- [ ] Support escapes/unescape in native builder or parser
- [ ] Return eager Lua object graph

### Phase 5 — Benchmarks

- [ ] Add fair benchmark against `lua-cjson` table decode
- [ ] Measure small object, nested object, large arrays
- [ ] Compare:
  - cjson decode
  - Moonlift tape+Lua rebuild
  - Moonlift native table builder
  - Moonlift projection

### Phase 6 — Hosted metaprogramming API

- [ ] Expose `Json.decode_native(src)`
- [ ] Expose `Json.project_table(spec)` for specialized Lua-table output
- [ ] Keep `Json.project(spec):decode_i32` for direct buffer output

---

## 12. Expected performance

For generic eager Lua tables, a native builder should close most of the gap with
`lua-cjson` because both would build Lua objects from native code.

Expected rough ordering:

```text
specialized projection to buffer         fastest
specialized projection to Lua table      very fast
Moonlift native table builder            should approach cjson
cjson decode                             strong baseline
Moonlift tape + Lua table rebuild        slower
```

Small objects may still favor cjson due to low fixed overhead unless Moonlift
uses persistent decoder/session buffers.

Large documents should benefit more from Moonlift's fast parser and generated
control.

---

## 13. Key design decision

Do **not** optimize generic eager table decode by making the Lua tape walker more
complicated first.

The correct architectural fix is:

```text
explicit Lua object builder backend with lua_State* access
```

This aligns with the earlier hosted/state-aware LuaJIT direction and gives a
real reason to add native Lua integration.

---

## 14. Relationship to current work

Current working pieces:

- hosted continuation fragments
- expression fragments
- region-fragment fusion
- JSON validator/tape decoder
- lazy JSON views
- specialized JSON projection codegen

The new Lua table builder backend should reuse the hosted fragment style:

```text
parse fragments -> builder fragments -> fused parser/table-constructor
```

This keeps the architecture unified while adding a new output target.
