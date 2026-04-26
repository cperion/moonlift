# Moonlift Host Arena ABI Design

Status: design document.

Purpose: define the low-level representation for exposing Moonlift-owned values
to Lua with high performance, without leaking library domains such as JSON into
Moonlift's Rust/runtime core.

The key requirement:

```text
Lua should mostly wrap/cast pointers and run type-local accessors.
Rust/runtime should own only stable memory sessions for explicit typed records.
Layout descriptors and producers belong in Moonlift/ASDL/library code, not in a
Rust-defined dynamic object arena. Library domains such as JSON must stay outside
the Rust core.
```

---

## 1. Non-negotiable boundary

Do **not** put JSON into Moonlift Rust.

The Rust/native host layer must not contain:

- JSON object semantics
- JSON key rules
- JSON number grammar
- JSON string escape policy
- JSON-specific structs
- JSON-specific parser code

Rust may contain only domain-neutral typed-record memory concepts:

```text
HostSession
HostRecord allocation
stable HostRef / HostPtr
record field initialization by explicit layout offsets
```

JSON, regex, binary protocols, etc. are libraries/generators that emit low-level
Moonlift code and explicit structs. They must not target a Rust-defined dynamic
object/array/string graph as a shortcut.

---

## 2. Design target

Current bad path for host-exposed values:

```text
Moonlift/native result
  -> Lua reconstructs structure
  -> many Lua tables/strings allocated
  -> slow and not Moonlift-owned
```

Desired path:

```text
Moonlift/native result
  -> explicit typed record/struct allocation
  -> HostRef returned for that record
  -> Lua proxy holds session + pointer/ref
  -> Lua accessors cast/read stable memory
```

For typed values:

```text
obj.id
  -> Lua type-local accessor
  -> ffi.cast to typed record pointer
  -> read field at known offset
```

For generic/dynamic values:

```text
obj.name
  -> Lua proxy/access plan
  -> native or cached generic map lookup
  -> HostRef wrapped/scalar materialized
```

---

## 3. Output modes

The host runtime supports several output modes. They are separate targets, not
one blurred API.

### 3.1 Typed arena records

Best for:

- ASDL nodes
- Moonlift compiler values
- generated projection schemas
- known structs/records
- metaprogramming values

Access path:

```text
Lua FFI cast + offset load
```

### 3.2 Generic arena values

Best for:

- dynamic objects/maps
- arrays with heterogeneous values
- library values whose shape is only known at runtime
- generic JSON-like data without JSON in Rust

Access path:

```text
proxy + generic map/array accessors + optional caches/batch ops
```

### 3.3 Eager Lua tables

Best for:

- compatibility with ordinary Lua libraries
- exact cjson-like API

Access path:

```text
native Lua table builder with lua_State*
```

This is a separate backend from arena proxies.

---

## 4. Host session and arena

A `HostSession` owns stable allocations for explicit typed records. Layout tables
are produced by Moonlift/ASDL/library code and consumed by Lua/Rust APIs; Rust
itself does not define a dynamic object graph.

Conceptual Rust shape:

```rust
pub struct HostSession {
    session_id: u64,
    generation: u32,
    records: Vec<RecordBlock>,
}

pub struct RecordBlock {
    ptr: NonNull<u8>,
    layout: Layout,
    kind: u32,
    type_id: u32,
    tag: u32,
}
```

Lua-visible references always pin the session owner.

```text
proxy._owner = session
proxy._ref   = HostRef / pointer cdata
```

If the session resets, generation changes and stale refs are rejected.

---

## 5. Stable ABI handles

Use both offset refs and optional direct pointers.

### 5.1 Offset reference

Good for persistence across arena page movement and validation.

```c
typedef struct MoonHostRef {
    uint64_t session_id;
    uint32_t generation;
    uint32_t kind;
    uint32_t type_id;
    uint32_t tag;
    uint64_t offset;
} MoonHostRef;
```

### 5.2 Direct pointer view

Good for fast typed Lua access.

```c
typedef struct MoonHostPtr {
    void* ptr;
    uint64_t session_id;
    uint32_t generation;
    uint32_t kind;
    uint32_t type_id;
    uint32_t tag;
} MoonHostPtr;
```

Recommended public proxy stores both when possible:

```lua
proxy[REF] = MoonHostRef[1]
proxy[PTR] = MoonHostPtr[1] or typed cdata pointer
proxy[OWNER] = session
```

Typed accessors use `PTR`.
Native batch operations use `REF`.

---

## 6. Scalar and reference ABI

Do not use a generic dynamic `MoonValue` tree as the default representation.
Explicit layouts should choose their own scalar fields and reference fields.

Examples:

```c
typedef struct ProjectedUser {
    int32_t id;
    int32_t active;
} ProjectedUser;

typedef struct NodeEdge {
    uint64_t target_ref;
    uint32_t kind;
    uint32_t flags;
} NodeEdge;
```

Booleans should use explicit integer encodings chosen by the layout facts.
References are stable `HostRef`/offset fields only when the producer explicitly
needs them.

---

## 7. Typed record ABI

Typed records are the fast path.

Generated layout example:

```c
typedef struct UserRecord {
    uint32_t type_id;
    uint32_t tag;
    int32_t  id;
    int32_t  age;
    uint8_t  active;
    uint8_t  _pad[3];
    MoonStringRef name;
} UserRecord;
```

Lua-generated accessor:

```lua
ffi.cdef[[
typedef struct UserRecord {
    uint32_t type_id;
    uint32_t tag;
    int32_t  id;
    int32_t  age;
    uint8_t  active;
    uint8_t  _pad[3];
    MoonStringRef name;
} UserRecord;
]]

function UserMethods:id()
    return tonumber(ffi.cast("const UserRecord*", self:ptr()).id)
end
```

Or for property syntax:

```lua
local UserIndex = {
    id = function(self) return tonumber(self._ptr.id) end,
    age = function(self) return tonumber(self._ptr.age) end,
    active = function(self) return self._ptr.active ~= 0 end,
}
```

Then:

```lua
user.id
```

is:

```text
Lua __index -> type-local closure -> FFI struct field read
```

No domain semantics in Rust. Rust only allocated a record with a known layout.
The layout came from ASDL/schema/codegen.

---

## 8. Arrays and strings

Arrays and strings should be explicit Moonlift structs/regions when a library
needs them. They are not a Rust HostArena dynamic fallback.

A library may define a typed homogeneous array layout such as:

```c
typedef struct MoonI32ArrayView {
    uint32_t len;
    const int32_t* data;
} MoonI32ArrayView;
```

Lua access stays pointer-backed:

```lua
local p = ffi.cast("const int32_t*", arr_header.data)
return tonumber(p[i - 1])
```

A library may define an explicit byte string/slice layout such as:

```c
typedef struct MoonByteSlice {
    const uint8_t* ptr;
    uint32_t len;
    uint32_t flags;
} MoonByteSlice;
```

Lua materializes only on demand:

```lua
ffi.string(s.ptr, s.len)
```

---

## 9. Explicit maps/records, not dynamic fallback objects

Dynamic object graphs are not a Rust HostArena fallback. If a library needs a map,
object, row, packet, slice, or table-shaped view, it should define an explicit
layout and generate low-level Moonlift code that writes that layout.

Examples:

```c
typedef struct ProjectedUser {
    int32_t id;
    int32_t active;
} ProjectedUser;

typedef struct PacketHeader {
    uint16_t kind;
    uint16_t flags;
    uint32_t len;
} PacketHeader;
```

Lua field access over these layouts is direct pointer access through
`buffer_view.lua` or a host typed-record proxy. Generated typed records avoid
string lookup and avoid a generic `MoonValue` tree entirely.

---

## 10. Low-level producers

Rust runtime does not expose a JSON/object builder. Producers are Moonlift code
or library codegen that writes explicit buffers/structs.

Allowed producer shape:

```text
parse/control in Moonlift
  -> write known fields into explicit struct/buffer
  -> return pointer/view/ref
  -> Lua wraps with generated accessors
```

ASDL target direction:

```asdl
Moon2Host.HostLayoutFact
Moon2Host.HostAccessPlan
Moon2Back flat memory/store/call commands
```

A JSON projection library, a binary protocol library, and an ASDL exporter can all
use the same explicit layout/view machinery without any Rust dynamic object arena.

---

## 11. Lua API shape

Public value proxy remains a Lua table shell, but the hot payload is a pointer.

```lua
local v = session:wrap(ptr_or_ref)

v.id          -- type-local accessor or generic map lookup
v.items[1]    -- direct typed array access or generic value array
#v.items
v:pairs()
v:to_table()
v:raw_ref()
v:ptr()
```

Type-local methods are installed directly on type tables, preserving the desired
Lua API style:

```lua
function User:age_plus_one()
    return self.age + 1
end

user:age_plus_one()
```

No visible phase calls in user code.

---

## 12. Access tiers

### Tier 1: Direct typed pointer access

Fastest ergonomic path.

```text
known type + known field offset -> FFI struct read
```

Used for:

- ASDL values
- typed Moonlift records
- generated projection records
- compiler/metaprogramming values

### Tier 2: Cached generic proxy access

For dynamic maps/arrays.

```text
first access: symbol/field lookup
later access: cached slot/pointer read
```

Used for:

- generic dynamic objects
- library-defined maps

### Tier 3: Coarse native batch operations

For hot loops/traversals.

```text
one Lua->native call, many fields/elements processed
```

Examples:

```lua
Native.project(root, spec, out)
Native.batch_get(root, paths, refs_out)
Vector.sum(array)
```

### Tier 4: Eager Lua table materialization

Compatibility path.

```text
native Lua table builder if available, Lua fallback otherwise
```

---

## 13. How JSON uses this without leaking

JSON library remains ordinary Moonlift/library code.

Allowed:

```text
json.moon2 / json_codegen.lua generates low-level Moonlift parsers
json projection generator emits explicit typed record layouts/accessors
json validator remains a Moonlift function
```

Forbidden:

```text
Rust HostArena has JsonObject
Rust HostArena has JsonNumber
Rust runtime parses JSON
Rust runtime knows JSON duplicate-key policy
```

For JSON-shaped output, do not invent a Rust JSON/dynamic arena. Write the
low-level Moonlift code and explicit structs needed for that output shape.

For specialized projection, the library may produce:

```text
generated typed record, e.g. ProjectedUser { id: i32, active: bool }
```

That typed record is the retained HostArena output path.

---

## 14. ASDL/PVM phase boundaries

### `host_layout_plan`

Question:

```text
What stable ABI layout represents this host-exposed type?
```

Input:

```text
Moonlift/ASDL type, record schema, projection schema, or explicit struct type
```

Output:

```text
HostTypeLayout facts: size, alignment, fields, offsets, scalar encodings
```

### `host_arena_emit_plan`

Question:

```text
What low-level Moonlift/backend commands construct this typed value shape?
```

Input:

```text
source/parser/backend facts
```

Output:

```text
flat backend command stream or typed-record allocation calls
```

### `host_lua_access_plan`

Question:

```text
How does Lua access this host value?
```

Input:

```text
HostTypeLayout + HostAccessOp
```

Output:

```text
Lua accessor plan: direct offset read, type-local method, native batch over explicit refs, materialize only when requested
```

### `host_session_lifetime_plan`

Question:

```text
What owns this memory and when do refs become stale?
```

Output:

```text
owned session, borrowed generation, frozen arena, or copied value
```

---

## 15. Implementation sequence

### Phase 1: Lua-side ABI prototype without Rust JSON

- [x] Extend `value_proxy.lua` with optional `PTR` slot and `:ptr()` method.
- [x] Add a tiny fake/FFI-allocated typed record test in Lua.
- [x] Generate/register type-local accessors over struct offsets.
- [x] Prove `obj.field` reads cdata pointer fields without table materialization.

### Phase 2: Rust typed-record allocation slice

- [x] Implement first `HostSession` / typed-record allocation slice in the domain-neutral Rust runtime.
- [x] Remove the generic Rust values, arrays, maps, strings, and HostArena builder surface.
- [x] Expose C ABI for sessions, aligned record allocation, scalar field initialization by layout offsets, batch record allocation, stable refs, pointer lookup, reset, and generation checks.
- [x] No JSON code and no Rust-defined dynamic JSON/object arena.

### Phase 3: ASDL layout facts

- [x] Add `Moon2Host` ASDL facts for type layouts, buffer views, expose modes, access plans, producers, and fact streams.
- [x] `host_layout_facts.lua` emits `Moon2Host` facts from `buffer_view.lua` layouts, including cdefs and direct field access plans.
- [x] Validate size/alignment/offset facts in `test_host_layout_facts.lua`.
- [ ] Generate LuaJIT `ffi.cdef` fragments and type-local accessors directly from `Moon2Host` facts rather than Lua layout specs.

### Phase 4: Generated/library producers

- [ ] Make library codegen produce low-level Moonlift code and explicit structs.
- [x] JSON projection now produces generic buffer-backed views through `buffer_view.lua`; the compiled projection writes directly into an explicit FFI struct buffer via `view_decoder`.
- [x] Slow generic JSON HostArena decode experiments were removed from the public path and from the Rust/Lua HostArena surface; JSON projection no longer depends on `host_arena_native`.
- [x] Rust still remains domain-neutral and contains no JSON/dynamic-object arena.

### Phase 5: Native table compatibility backend

- [ ] Add optional Lua table materializer for explicit buffer views / HostArena refs.
- [ ] Keep this separate from proxy pointer access.

---

## 16. Key decision

The best low-level approach is:

```text
explicit buffer/struct views plus optional domain-neutral Rust typed-record sessions
  + stable ABI refs/pointers where needed
  + generated HostTypeLayout facts from Moonlift/ASDL/library code
  + Lua proxy tables with hidden refs/pointers
  + type-local pointer-cast accessors
  + low-level Moonlift code and explicit structs for domain producers
```

Not:

```text
JSON parser in Rust
```

and not:

```text
Lua rebuilds everything as ordinary tables
```

This gives the desired user experience:

```lua
obj.field
obj.items[1]
obj:method()
```

while Lua mostly performs:

```text
cast pointer -> read field -> wrap ref/scalar
```

and Moonlift/library layout facts retain ownership, layout, lifetime, and performance.
