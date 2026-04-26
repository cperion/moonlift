# Moonlift Host Exposure Performance Design

Status: design document. Current implementation policy: slow eager JSON object surfaces (`decode`, `decode_view`, generic `decode_host_arena`, one-shot projection records) have been removed; retained public JSON paths are validator/raw tape facts, reusable indexed documents, and indexed projection outputs.

Purpose: make Moonlift values cross into Lua with good ergonomics **and** good
performance, without pretending that lazy proxies and eager Lua tables are the
same output target.

The core design rule:

```text
Moonlift value exposure is a compiler/runtime target.
It must be represented explicitly, planned by phases, and executed by flat
host-facing commands or coarse native operations.
```

This document supersedes the informal performance discussion around JSON views,
proxy wrappers, and generic `Json.decode` slowness.

---

## 1. Problem split

There are three different operations currently being conflated:

```text
A. Parse/validate bytes
B. Expose a Moonlift-owned value lazily to Lua
C. Materialize an ordinary eager Lua table/object graph
```

They have different optimal representations.

### A. Parse/validate bytes

Best representation:

```text
native/tape/arena/source-specific flat facts
```

Current JSON tape parser is already fast.

### B. Lazy Lua exposure

Best representation:

```text
Lua proxy table
  + hidden FFI/native ref
  + owner/session pin
  + family/type access plan
  + optional indexes/caches
```

This is what `value_proxy.lua` starts.

### C. Eager Lua table materialization

Best representation:

```text
Lua tables created directly through lua_State* / Lua C API
```

This is not the same as lazy proxy exposure. It is a separate host backend.

---

## 2. Why we are still slow today

The current proxy layer fixes the **boundary shape**, but not all expensive
algorithms.

Current lazy JSON view field access still does:

```text
proxy __index
  -> Lua family dispatch
  -> scan object tape entries
  -> unescape each candidate key
  -> compare key
  -> wrap result
```

Current eager `Json.decode` still does:

```text
native parse -> tape arrays -> Lua recursive table rebuild
```

Current decode setup still does per-call allocation/copy:

```text
Lua string -> fresh FFI buffer
fresh stack/tape arrays
fresh meta arrays
```

Therefore, performance work must target the correct layer:

```text
proxy caches/indexes      improve lazy view access
session/reusable buffers  improve repeated decode overhead
native table builder      improve eager Lua table decode
```

---

## 3. Required architecture

Do not add random helper switches to JSON or Lua wrappers. The host boundary must
become explicit.

Add or evolve these layers:

```text
Moon2Host       host exposure plans, proxy kinds, access operations
Moon2LuaObj     eager Lua object builder target
value_proxy.lua Lua-side proxy runtime
native host     optional lua_State* backend for eager tables/coarse ops
```

Pipeline:

```text
Moonlift value/tape/arena/source result
  -> host_expose_plan
  -> HostExposeProxy | HostExposeEagerTable | HostExposeScalar | HostExposeOpaque
  -> proxy/index/materialize/native command plan
  -> final Lua-visible value
```

---

## 4. ASDL model

The ASDL names below are now partially implemented in `Moon2Host`: layout IDs,
field layouts, expose modes, access plans, view plans, producers, and host fact
streams are explicit ASDL values. Remaining work is to drive more codegen from
those facts directly.

### 4.1 Host exposure mode

```asdl
module Moon2Host {
  HostExposeMode
    = HostExposeProxy(HostProxyKind kind,
                      HostProxyCachePolicy cache,
                      HostMutability mutability,
                      HostBoundsPolicy bounds)
    | HostExposeEagerTable(HostMaterializePolicy policy)
    | HostExposeScalar(HostFieldRep rep)
    | HostExposeOpaque(string reason)
}
```

Meaning:

- `HostExposeProxy`: expose a Moonlift-owned value lazily.
- `HostExposeEagerTable`: produce real Lua table/string/number graph.
- `HostExposeScalar`: return primitive Lua scalar immediately.
- `HostExposeOpaque`: return handle/userdata/session object.

### 4.2 Proxy kinds

```asdl
HostProxyKind
  = HostProxyRecord
  | HostProxyArray
  | HostProxyMap
  | HostProxyVariant
  | HostProxyFunction
  | HostProxyModule
```

JSON object tape nodes are `HostProxyRecord`.
JSON array tape nodes are `HostProxyArray`.
Future ASDL nodes are likely `HostProxyVariant` or `HostProxyRecord` depending
on API shape.

### 4.3 Access operations

```asdl
HostAccessOp
  = HostAccessField(string name)
  | HostAccessIndex
  | HostAccessLen
  | HostAccessPairs
  | HostAccessIpairs
  | HostAccessMaterialize
  | HostAccessRawRef
```

Lua syntax maps to these operations:

```text
obj.foo       -> HostAccessField("foo")
obj[k]        -> HostAccessField(k) or HostAccessIndex(k)
#arr          -> HostAccessLen
obj:pairs()   -> HostAccessPairs
arr:ipairs()  -> HostAccessIpairs
obj:to_table() -> HostAccessMaterialize
```

### 4.4 Cache policy

```asdl
HostProxyCachePolicy
  = HostProxyCacheNone
  | HostProxyCacheKeys
  | HostProxyCacheFieldIndex
  | HostProxyCacheArrayIndex
  | HostProxyCacheFullIndex
  | HostProxyCacheMaterialized
```

Cache policy is meaningful and should not be hidden in arbitrary Lua tables.

For JSON tape:

```text
object: HostProxyCacheFieldIndex
array:  HostProxyCacheArrayIndex
keys:   HostProxyCacheKeys
```

### 4.5 Access plans

```asdl
HostAccessPlan
  = HostAccessLuaProxy
  | HostAccessLuaProxyCached
  | HostAccessNativeLookup
  | HostAccessNativeBatch
  | HostAccessMaterializeLua
  | HostAccessMaterializeNative
```

This distinguishes:

- simple Lua proxy lookup
- cached Lua proxy lookup
- native lookup over hidden refs
- coarse native batch extraction
- Lua materialization fallback
- native table builder materialization

---

## 5. Phase boundaries

### 5.1 `host_expose_plan`

Question:

```text
How should this Moonlift value cross into Lua?
```

Input:

```text
value family/type/tag + caller requested exposure mode
```

Output:

```text
HostExposeMode
```

Examples:

```text
JSON object tape node + view request
  -> HostExposeProxy(HostProxyRecord, HostProxyCacheFieldIndex)

JSON array tape node + view request
  -> HostExposeProxy(HostProxyArray, HostProxyCacheArrayIndex)

JSON object tape node + decode_table request
  -> HostExposeEagerTable(HostMaterializeNative if available else Lua fallback)
```

### 5.2 `host_access_plan`

Question:

```text
How is a Lua access operation implemented for this proxy kind/family?
```

Input:

```text
HostProxyKind + HostAccessOp + cache policy
```

Output:

```text
HostAccessPlan
```

Examples:

```text
JSON object + field + field-index cache
  -> HostAccessLuaProxyCached

JSON array + index + array-index cache
  -> HostAccessLuaProxyCached

ASDL node + field + native arena
  -> HostAccessNativeLookup or LuaProxyCached
```

### 5.3 `host_materialize_plan`

Question:

```text
How should a Moonlift-owned value become an ordinary Lua value graph?
```

Input:

```text
value family/type/tag + target host runtime capabilities
```

Output:

```text
HostAccessMaterializeLua | HostAccessMaterializeNative
```

Examples:

```text
JSON tape + no native Lua state backend
  -> Lua tape materializer fallback

JSON parser + native Lua state backend
  -> native Lua object builder
```

### 5.4 `host_session_plan`

Question:

```text
What reusable buffers/indexes/native sessions should this repeated host operation own?
```

Input:

```text
operation kind + input size policy + exposure mode
```

Output:

```text
HostSessionPlan
```

Examples:

```text
JSON projection repeated
  -> reusable byte buffer + compiled projection + reused typed record

explicit low-level struct producer
  -> Moonlift code writes explicit struct layout + proxy owner session
```

---

## 6. Lua proxy runtime design

The public proxy shape is already started in `value_proxy.lua`:

```text
Lua table shell
  [REF]   = FFI MoonliftValueRef[1]
  [OWNER] = tape/session/artifact/native owner
  [CACHE] = optional access indexes
```

This remains the correct public shape.

### 6.1 Hidden ref

```c
typedef struct MoonliftValueRef {
    uint64_t session_id;
    uint32_t family_id;
    uint32_t type_id;
    uint32_t tag;
    uint32_t flags;
    uint64_t value_id;
    uint32_t index;
    uint32_t reserved;
} MoonliftValueRef;
```

### 6.2 Family descriptor

Each family implements:

```lua
family.index(proxy, key, ref, owner)
family.len(proxy, ref, owner)
family.pairs(proxy, ref, owner)
family.ipairs(proxy, ref, owner)
family.to_table(proxy, ref, owner)
family.tostring(proxy, ref, owner)
```

### 6.3 Family performance contract

A family must document:

```text
lookup complexity before cache
lookup complexity after cache
cache memory shape
mutation policy
materialization behavior
native acceleration availability
```

JSON family current target:

```text
object field lookup before cache: O(fields)
object field lookup after cache:  O(1)
array index before cache:         O(index)
array index after incremental:    amortized O(1) for sequential, O(delta) for forward random
```

---

## 7. JSON proxy cache design

### 7.1 Object field cache

For a JSON object proxy, hidden cache should contain:

```lua
cache.object_pos = proxy_pos
cache.field_pos = {
  id = value_pos,
  age = value_pos,
  active = value_pos,
}
cache.key_by_pos = {
  [key_pos] = unescaped_key,
}
cache.complete = true
```

Build policy:

```text
first string field access builds full field index for that object
```

Why full object index instead of one-key cache?

- objects are usually small/medium
- avoids repeated scans for multiple fields
- supports pairs() reusing key strings
- simpler correctness

Duplicate keys:

JSON allows duplicate object names. Lua table decode usually last-wins.

Policy must be explicit:

```text
field cache stores last occurrence by default
pairs() preserves tape order
```

That matches common decode behavior while retaining ordered iteration.

### 7.2 Array index cache

For a JSON array proxy:

```lua
cache.array_pos = { [1] = pos1, [2] = pos2 }
cache.scanned_len = 2
cache.next_pos = pos_after_2
cache.complete = false
cache.len = nil until complete
```

Access policy:

```text
arr[i]: scan forward from cached frontier until i or end
#arr: scan to end once, cache len and positions if cheap
ipairs(): scan sequentially and fill positions
```

This makes sequential iteration efficient and avoids rescanning from start.

### 7.3 Scalar materialization cache

Optional:

```lua
cache.scalar_by_pos[pos] = value
```

Useful for strings/numbers repeatedly accessed from the same proxy owner.

Default:

```text
enable for strings with escapes and numbers
```

Because repeated `tonumber(slice)` and `unescape_string` is costly.

### 7.4 Cache ownership

Caches live on the proxy, not in the tape owner, initially.

Reason:

- easiest lifetime behavior
- no global weak tables yet
- avoids cross-proxy invalidation

Later optimization:

```text
owner-level weak index keyed by tape pos
```

for sharing indexes between multiple wrappers of the same object position.

---

## 8. Decode session design

Current implementation policy removed slow eager whole-document JSON object APIs. The
retained JSON runtime uses one indexed-tape path:

```text
validator/raw tape facts for validation and diagnostics
reusable JsonDocDecoder sessions for generic indexed documents
indexed projection outputs for user-facing extraction
reused buffer-backed views for pointer-backed Lua table shape
```

Repeated decode sessions are attached to `JsonDocDecoder` and reused by projectors/views.
The implemented hot APIs are:

```lua
local doc_decoder = Json.doc_decoder(compiled)
local doc = assert(doc_decoder:decode(src))

local projector = JsonCodegen.project(spec)
local view_decoder = projector:view_decoder()
local view = assert(view_decoder:decode(src))
```

The document decoder owns/reuses tape/index FFI buffers, while projection views
own/reuse an explicit FFI struct buffer through `buffer_view.lua`. Eager Lua
object rebuilds and borrowed whole-document JSON object views are
intentionally not public fast paths.

---

## 9. Native/coarse proxy operations

Per-field native FFI calls are not the answer. They create too many Lua -> native
boundaries.

Instead, use coarse operations over proxy refs:

```lua
Json.project_from_view(view, spec, out)
Json.native_batch_get(view, {"id", "age", "active"}, out)
Vector.sum(view)
ASDL.batch_fields(nodes, field_ids, out)
```

This is where hidden FFI refs pay off:

```text
Lua proxy -> raw_ref pointer -> native batch op -> one boundary -> many lookups
```

ASDL target:

```asdl
HostBatchAccess
  = HostBatchGetFields(HostAccessPath* paths)
  | HostBatchProject(HostProjectionSpec spec)
  | HostBatchMaterialize(HostMaterializeSpec spec)
```

Execution:

```text
for-loop over flat access commands in native/runtime code
```

---

## 10. Eager table backend design

For real `cjson`-style eager decode, proxy caches are not enough.

Need:

```text
LuaObj builder backend with lua_State* access
```

This is a separate target from proxy exposure.

### 10.1 Lua object commands

```asdl
Moon2LuaObj.LuaObjOp
  = LuaObjBeginObject
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
```

### 10.2 Runtime builder

```text
LuaObjBuilder
  lua_State* L
  container stack
  pending key
  null sentinel ref
  error status
```

### 10.3 Table decode path

```text
JSON bytes
  -> Moonlift parser/control
  -> LuaObj operations while parsing
  -> native Lua API creates real tables directly
  -> Lua table result
```

This is the correct path for:

```lua
Json.decode_table(src)
```

and is the only path expected to approach/beat `lua-cjson` for full eager table
output.

---

## 11. API design

Expose only fast JSON surfaces:

```lua
local Json = require("moonlift.json_codegen")

local projector = Json.project(spec)

-- Fastest raw extraction.
local out = assert(projector:decode_i32(src, out))

-- Fast pointer-backed buffer view.
local decoder = projector:view_decoder()
local view = assert(decoder:decode(src))

-- Convenience result that still only materializes projected fields.
local table = assert(projector:decode_table(src))
```

The generic JSON helper remains validator/raw-tape only:

```lua
local Generic = require("moonlift.json_library")
local compiled = assert(Generic.compile())
local tape = assert(Generic.decode_tape(compiled, src))
```

No public `Json.decode`, generic whole-document `Json.decode_view`, generic
`decode_host_arena`, or one-shot projection record allocation API should be
reintroduced unless it is measured as a fast path.

---

## 12. Diagnostics and correctness

### 12.1 Proxy invalidation

Borrowed session proxies must detect stale generation:

```text
HostRejectStaleProxy
```

Lua error:

```text
stale Moonlift proxy: session was reused after this value was borrowed
```

### 12.2 Unsupported table compatibility

Proxy values are table-like but not raw tables.

Supported:

```lua
obj.id
obj["id"]
arr[1]
#arr
obj:pairs()
arr:ipairs()
obj:to_table()
```

Not promised:

```lua
next(obj)
rawget(obj, "id")
table.insert(arr, x)
```

Diagnostic/doc message:

```text
use :to_table() when a raw Lua table is required
```

### 12.3 Duplicate JSON keys

Explicit policy:

```text
field access returns last occurrence
pairs() yields source order
:to_table() uses last occurrence
```

Document and test this.

---

## 13. Implementation sequence

### Phase 1: Keep fast typed proxies

- [x] Keep `value_proxy.lua` as the small Lua shell around hidden refs/pointers.
- [x] Use buffer-backed table-shaped proxies for projection outputs.
- [x] Remove slow public JSON view/table/generic HostArena decode paths.

### Phase 2: Reusable specialized sessions

- [x] Use `projector:view_decoder()` for repeated JSON projection.
- [x] Reuse explicit view buffer memory instead of allocating one-shot record proxies in hot paths.
- [ ] Generalize this pattern through explicit Moonlift structs and ASDL host facts.

### Phase 3: Coarse batch operations over explicit refs

- [ ] Add APIs only where they operate over explicit typed refs/layout facts.
- [ ] Keep operations coarse, not per-field FFI.
- [ ] Do not reintroduce a Rust dynamic object/JSON arena.

### Phase 4: Optional native eager table backend

- [ ] If cjson-compatible eager table decode is needed, add it as a separate Lua table-builder target.
- [ ] Keep it separate from Moonlift-owned typed records and proxy pointer access.

### Phase 5: ASDL host exposure modules

- [x] Extend `Moon2Host` with host layout/view/access/expose facts.
- [x] Add `host_layout_facts.lua` to emit fact streams and access/view plans from buffer-view layouts.
- [ ] Drive LuaJIT cdefs/accessors directly from `Moon2Host` facts.
- [ ] Add host materialize plan phases for explicit eager-table targets.

---

## 14. Expected benchmark movement

### After typed-record projection sessions

Expected improvement:

```text
projection reused-record access stays close to raw output buffers
allocation/proxy construction overhead is avoided in hot loops
```

No improvement is expected for removed slow generic JSON object paths because they
are no longer public surfaces.

### After optional native table backend

Expected improvement:

```text
generic eager Lua table decode approaches cjson
large documents may beat cjson if parser remains faster
small documents depend on fixed overhead
```

---

## 15. Key decision

The proper design is not one trick. It is three explicit exposure targets:

```text
1. Proxy exposure for Moonlift-owned lazy values
2. Session/batch operations for repeated/coarse host access
3. Native Lua object builder for ordinary eager Lua tables
```

The proxy layer is the right foundation, but performance comes from adding the
missing plans:

```text
HostProxyCachePolicy
HostSessionPlan
HostBatchAccess
Moon2LuaObj eager materialization backend
```

That keeps Moonlift values ergonomic in Lua without losing the performance model
or hiding semantic distinctions in helper code.
