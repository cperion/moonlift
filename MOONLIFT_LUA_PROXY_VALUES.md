# Moonlift Lua Proxy Values

Status: design note for exposing Moonlift-owned values to Lua without eagerly
materializing them as ordinary Lua tables. Current JSON policy keeps the proxy
runtime for generic buffer-backed projection views and other fast paths; the
slow whole-document JSON tape-view public API was removed.

The short version:

```text
Do not make every Moonlift value become a Lua table.
Expose a small Lua proxy table whose hidden payload is an FFI/native Moonlift
reference, and give that proxy table table-like behavior through metatables.
```

This is the middle ground between:

```text
native value/tape/arena is fast but awkward to use
```

and:

```text
eager Lua table materialization is convenient but slow
```

---

## 1. Problem

For generic JSON and future Moonlift object values, eager Lua table rebuilding is
slow because it does this:

```text
Moonlift/native value
  -> Lua walks representation
  -> Lua allocates every table/string/scalar
  -> Lua copies everything into ordinary Lua shape
```

But exposing raw FFI arrays/cdata directly is too awkward for users.

We need values that:

- keep the real object in Moonlift/native storage
- cross into Lua cheaply
- support natural access syntax
- preserve lifetime/session ownership
- can materialize to a real Lua table only when requested

---

## 2. Important constraint: cdata is not a Lua table

LuaJIT FFI cdata with `ffi.metatype` is useful, but it is not a perfect Lua
object/table replacement.

Problems with pure cdata objects:

- metatype is per C type, not per schema/type instance
- dynamic field sets are awkward
- per-object metadata is awkward
- `pairs`/`ipairs` table behavior is limited/non-portable
- lifecycle/finalization needs care
- users often expect normal Lua table affordances

Therefore the public value should usually be a **Lua table proxy**, not naked
cdata.

The proxy table hides an FFI/native reference:

```lua
local REF = {}

local obj = setmetatable({ [REF] = ffi_ref }, MoonValueMT)
```

The table gives Lua ergonomics. The hidden FFI reference gives native identity
and speed.

---

## 3. Representation

### 3.1 Public Lua shape

```lua
local v = Moon.wrap(ref)

v.id          -- lazy field access
v.items[1]    -- lazy index access
#v.items      -- length when array-like
v:pairs()     -- explicit portable iterator
v:to_table()  -- eager materialization
v:raw_ref()   -- advanced/native interop escape hatch
```

### 3.2 Hidden FFI ref

A minimal FFI-visible reference:

```c
typedef struct MoonValueRef {
    uint64_t session_id;
    uint32_t family_id;
    uint32_t type_id;
    uint32_t tag;
    uint32_t flags;
    uint64_t value_id;
    uint32_t index;
    uint32_t reserved;
} MoonValueRef;
```

Meaning:

- `session_id`: owner arena/runtime session
- `family_id`: representation family, e.g. JSON tape, ASDL node, native vector
- `type_id`: semantic type/schema id
- `tag`: object/array/string/number/etc. or ASDL variant id
- `flags`: lazy/materialized/error bits
- `value_id`: arena/tape/node id
- `index`: local offset/position when needed

For Lua storage, use:

```lua
local ref = ffi.new("MoonValueRef[1]")
local proxy = setmetatable({ [REF] = ref, [OWNER] = owner }, mt)
```

The `OWNER` slot pins the session/tape/artifact so the native memory outlives the
proxy.

---

## 4. Why a table proxy instead of naked cdata?

### Table proxy advantages

- dynamic metatables per family/type
- hidden owner references for lifetime
- method tables using colon syntax
- easier debug/tostring behavior
- can memoize accessed fields if desired
- can interoperate with existing Lua code better

### Cdata advantages retained

- compact native handle
- passable back to FFI/native calls
- no full object materialization
- type-local fast access functions possible

The proxy is therefore:

```text
Lua table shell + hidden FFI ref + native/session owner
```

not:

```text
ordinary eager Lua object graph
```

---

## 5. Access protocol

Each proxy family has a descriptor:

```lua
MoonFamily = {
  name = "json_tape_object",
  index = function(proxy, key) ... end,
  newindex = function(proxy, key, value) ... end,
  len = function(proxy) ... end,
  pairs = function(proxy) ... end,
  ipairs = function(proxy) ... end,
  to_table = function(proxy) ... end,
}
```

Metatable skeleton:

```lua
local MoonValueMT = {}

function MoonValueMT:__index(key)
    local method = MoonMethods[key]
    if method then return method end
    local ref = rawget(self, REF)
    local family = family_for(ref[0].family_id)
    return family.index(self, key)
end

function MoonValueMT:__len()
    local ref = rawget(self, REF)
    return family_for(ref[0].family_id).len(self)
end

function MoonMethods:pairs()
    local ref = rawget(self, REF)
    return family_for(ref[0].family_id).pairs(self)
end

function MoonMethods:to_table()
    local ref = rawget(self, REF)
    return family_for(ref[0].family_id).to_table(self)
end
```

For Lua 5.1/LuaJIT portability, always provide explicit methods:

```lua
for k, v in obj:pairs() do ... end
for i, v in obj.items:ipairs() do ... end
```

Do not rely on global `pairs(obj)` behaving exactly like Lua 5.2 `__pairs`.

---

## 6. JSON view as first target

Current `json_library.lua` already has a local version of this idea:

```text
TapeObject
TapeArray
_tape owner
_pos index
__index lookup
:pairs()
```

Generalize it into Moon proxy values:

```text
JsonTapeObject -> MoonValue proxy family: json_object
JsonTapeArray  -> MoonValue proxy family: json_array
Json scalar    -> lazy scalar proxy or immediate scalar
```

Instead of each JSON view being a hand-shaped table with `_tape`/`_pos`, it
becomes:

```lua
Moon.wrap_json_tape(tape, pos)
```

with hidden:

```text
MoonValueRef { family = JSON_TAPE, tag = OBJECT, value_id = tape_id, index = pos }
```

This gives one reusable proxy system for:

- JSON tape views
- future ASDL node views
- native vector views
- compiled module/function values
- lazy record/object values

---

## 7. ASDL/PVM representation

If the compiler/runtime needs to distinguish host exposure behavior, make it
explicit.

Candidate ASDL module:

```text
Moon2Host
```

Important distinctions:

```asdl
HostExposeMode
  = HostExposeProxy
  | HostExposeEagerTable
  | HostExposeScalar
  | HostExposeOpaque

HostProxyKind
  = HostProxyRecord
  | HostProxyArray
  | HostProxyVariant
  | HostProxyMap
  | HostProxyFunction

HostAccessOp
  = HostAccessField(string name)
  | HostAccessIndex
  | HostAccessLen
  | HostAccessPairs
  | HostAccessMaterialize
```

For JSON specifically, avoid JSON-domain ASDL pollution in the compiler core.
Instead JSON library can declare/use host exposure facts:

```text
JSON tape object has HostProxyRecord facet
JSON tape array has HostProxyArray facet
JSON string slice materializes as Lua string on access
```

---

## 8. Phase boundaries

### `host_expose_plan`

Question:

```text
How should this Moonlift value be exposed to Lua?
```

Input:

```text
semantic value/type/family
```

Output:

```text
HostExposePlan
```

Examples:

```text
JSON object tape node -> HostExposeProxy(HostProxyRecord)
JSON array tape node  -> HostExposeProxy(HostProxyArray)
JSON number slice     -> HostExposeScalar(LuaNumber, lazy parse)
ASDL node             -> HostExposeProxy(HostProxyVariant)
```

### `host_access_plan`

Question:

```text
What operation implements this Lua access?
```

Input:

```text
HostProxyKind + HostAccessOp
```

Output:

```text
HostAccessPlan / flat host command
```

Examples:

```text
json_object.field -> scan object keys in tape and wrap value
json_array[i]     -> skip tape elements until i and wrap value
asdl_node.field   -> read field from ASDL arena and wrap value
```

---

## 9. Caching and materialization

Proxy objects can optionally memoize fields:

```lua
local CACHE = {}
```

On first access:

```text
native/tape lookup -> wrapped value -> store in hidden cache
```

But caching must be a representation decision, not hidden semantics.

Expose as plan flag:

```text
HostProxyCacheNone
HostProxyCacheFields
HostProxyCacheMaterialized
```

Default for JSON tape:

```text
no field cache initially
```

because field lookup cost is acceptable for sparse access and cache tables cost
memory.

For ASDL nodes:

```text
cache field wrappers may be useful
```

because identities are stable and fields are immutable.

---

## 10. Mutation policy

Default Moonlift proxy values are immutable.

`__newindex` should reject:

```lua
obj.id = 3 -- error unless this is an explicit mutable host object
```

If mutable host objects are needed later, define explicit ASDL/state events:

```text
HostSetField
HostSetIndex
ApplyHostMutation
```

Do not silently mutate Moonlift values from Lua.

---

## 11. Exact table compatibility

A proxy can behave table-like, but it should not lie about being a raw Lua table.

Supported:

```lua
obj.id
obj["id"]
arr[1]
#arr
obj:pairs()
arr:ipairs()
obj:to_table()
tostring(obj)
```

Not guaranteed:

```lua
next(obj)
rawget(obj, "id")
table.insert(proxy_array, x)
generic libraries that require a raw table
```

For those cases:

```lua
local t = obj:to_table()
```

This is honest and avoids impossible compatibility promises.

---

## 12. Relationship to native Lua table builder

The proxy-value design and Lua table-builder backend solve different problems.

### Proxy values

Best for:

```text
lazy object access
Moonlift values crossing to Lua
large structured values
views over native/tape/arena data
metaprogramming handles
```

### Native Lua table builder

Best for:

```text
users explicitly want ordinary eager Lua tables
cjson-compatible decode API
library compatibility
```

They should share exposure plans:

```text
HostExposeProxy    -> proxy wrapper
HostExposeEagerTable -> native table builder or to_table materializer
```

---

## 13. Implementation plan

### Phase 1: General Lua proxy runtime

- [ ] Add `moonlift/lua/moonlift/value_proxy.lua`
- [ ] Define hidden keys: `REF`, `OWNER`, `CACHE`
- [ ] Define `MoonValueRef` FFI struct
- [ ] Define family registry
- [ ] Implement `wrap(ref, owner)`
- [ ] Implement method dispatch:
  - [ ] `:raw_ref()`
  - [ ] `:tag()`
  - [ ] `:pairs()`
  - [ ] `:ipairs()`
  - [ ] `:to_table()`
  - [ ] `__index`
  - [ ] `__len`
  - [ ] `__tostring`
  - [ ] immutable `__newindex`

### Phase 2: Buffer-backed and typed-record proxies

- [x] Keep `value_proxy.lua` as the generic proxy shell/runtime.
- [x] Use it for `buffer_view.lua` explicit struct views and typed HostArena record proxies with direct pointer-backed field access.
- [x] Do not expose the slow whole-document JSON tape-view API as a public fast path.

### Phase 3: ASDL node proxies

- [ ] Register ASDL node family
- [ ] Expose fields through schema/type descriptors
- [ ] Support `node:variant()` / `node:is(...)` / field access
- [ ] Use for hosted code values if helpful

### Phase 4: Native interop

- [ ] Make proxy refs passable to native/Rust operations
- [ ] Add coarse batch/native operations that consume `MoonValueRef*`
- [ ] Keep per-field native calls out of hot loops unless batched

### Phase 5: Eager materialization backend

- [ ] Add native table builder for `:to_table()` fast path where appropriate
- [ ] Keep Lua fallback materializer for bootstrapping

---

## 14. Design rule

The public Lua object should be:

```text
small Lua proxy table
  -> hidden FFI/native MoonValueRef
  -> owner/session pin
  -> family/type access plan
```

not:

```text
fully eager Lua table by default
```

and not:

```text
naked cdata pretending to be a table
```

This gives Lua users natural syntax while preserving Moonlift ownership,
laziness, identity, and native interop.
