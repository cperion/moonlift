# LuaBridge Design

LuaBridge is the standard protocol boundary between Moonlift and LuaJIT.

It is not a convenience wrapper over the Lua C API.  It is the place where
LuaJIT stack effects, registry references, borrowed memory, protected calls,
and Lua errors become explicit Moonlift facts.

The core rule:

```text
Raw Lua C API calls are allowed.
Raw Lua C API calls are not the design.
LuaBridge regions are the design.
```

## Doctrine

LuaJIT is a dynamic host runtime with stack-based APIs, registry references,
garbage-collected objects, and exception-style error transfer.  Moonlift is a
typed, jump-first compiled language where resource obligations and control
outcomes are explicit.

LuaBridge reconciles those worlds.

```text
LuaJIT owns Lua object memory.
Moonlift owns registry-reference obligations.
Moonlift owns semantic handles and typed stores.
LuaBridge owns the conversion protocol.
```

Raw stack slots are not durable values.  Raw registry integers are not resource
types.  Raw `lua_State*` pointers are not a capability model.  Raw `lua_pcall`
status codes are not an error model.

LuaBridge gives each of those facts a name, a type, and a protocol.

## Bridge Store

LuaBridge requires an explicit bridge store.  Handles are not wrappers around
raw Lua values; they resolve through this store.

Conceptually:

```moonlift
struct LuaBridgeStore
    states: LuaStateRecord*
    refs: LuaRefRecord*
    errors: LuaErrorRecord*
    generation: u64
end
```

The exact storage representation is an implementation choice.  The semantic
requirements are not:

```text
state handles resolve with generation checks
ref handles resolve with generation checks
error handles resolve with generation checks
ref records name their owning LuaStateRef
error records name their owning LuaStateRef
owned release protocols retire store slots
stale handles are typed outcomes
```

`core: ptr(Core)` appears in the protocols below as the owner of that store.
If the runtime splits stores more finely, `Core` may contain or point to the
LuaBridge store.  The protocol law remains the same.

## Layering

The boundary has three layers:

```text
moonlift.lua_raw
    raw extern declarations only
    unsafe, small, internal
    no ownership meaning

moonlift.lua_bridge_model
    handles, records, structs, enums, and protocol signatures
    no raw Lua C API calls
    reusable by every subsystem that mentions Lua values

moonlift.lua_bridge
    region implementations
    the only normal module allowed to use lua_raw
    owns stack discipline, registry references, protected calls, and errors
```

Higher layers use `lua_bridge`.  They do not import `lua_raw`.

```text
moonlift core/runtime code
    uses lua_bridge
    does not call lua_raw

public Lua-facing APIs
    expose ergonomic Lua objects
    do not expose raw stack or registry discipline
```

The unsafe escape hatch is explicit:

```lua
local raw = require("moonlift.lua_raw")
```

That import means the module is implementing or auditing the bridge boundary.
It is not normal application or compiler code.

## Ownership Law

LuaBridge has four ownership classes.

```text
Lua stack value
    borrowed, positional, temporary
    valid only while the stack discipline preserves it

Lua registry reference
    durable Lua value identity
    owned by Moonlift as a release obligation

Lua object memory
    owned by LuaJIT and its garbage collector
    never freed by Moonlift

Moonlift semantic value
    owned by Moonlift stores and resource protocols
    may be represented in Lua only through bridge-controlled proxies
```

The central type is:

```moonlift
owned LuaRef
```

`owned LuaRef` means: this control path must discharge one Lua registry
reference exactly once.  Discharge normally means `luaL_unref` through
`lua_release_ref`; transfer means moving the owned value into another typed
protocol that accepts `owned LuaRef`.

`LuaRef` without `owned` is durable identity, not cleanup authority.

Plain `LuaRef` values may be copied.  `owned LuaRef` values may not be copied,
silently dropped, converted to plain `LuaRef`, stored into ordinary aggregates,
or hidden behind raw integers.

## State Identity

`lua_State*` is opaque.  Moonlift does not model its layout.

```moonlift
struct LuaStateRecord
    raw: ptr(u8)
    generation: u64
    owns_state: bool
end

handle LuaStateRef : u32 invalid 0
    target LuaStateRecord
end
```

`LuaStateRef` names a state record known to the bridge store.  The raw pointer
is used only at the boundary.  The generation prevents stale handles from
silently resolving to a recycled state slot.

The state record distinguishes two cases:

```text
owns_state = true
    LuaBridge is responsible for closing the state through a typed protocol.

owns_state = false
    LuaBridge has adopted a state owned by an outer host.
    LuaBridge may create registry refs in it, but may not close it.
```

State protocols:

```moonlift
region lua_state_adopt(core: ptr(Core), L: ptr(u8);
    adopted(state: LuaStateRef)
  | null_state
  | already_registered(state: LuaStateRef)
  | memory_exhausted(needed: index))
end

region lua_state_validate(core: ptr(Core), state: LuaStateRef;
    valid(record: lease ptr(LuaStateRecord))
  | stale(state: LuaStateRef)
  | missing(state: LuaStateRef))
end

region lua_state_raw(core: ptr(Core), state: LuaStateRef;
    raw(L: ptr(u8))
  | stale(state: LuaStateRef)
  | missing(state: LuaStateRef))
end
```

A `LuaRef` belongs to exactly one `LuaStateRef`.  Pushing or releasing a ref
against the wrong state is a typed outcome.

## Reference Records

Lua registry references are stored in a bridge-owned store.

```moonlift
struct LuaRefRecord
    state: LuaStateRef
    registry_ref: i32
    kind_hint: u8
    generation: u64
end

handle LuaRef : u32 invalid 0
    target LuaRefRecord
end
```

`kind_hint` is diagnostic and optimization metadata.  It may record the observed
Lua kind at retain time, but correctness must still be checked at use sites
where Lua semantics require it.

The store law:

```text
LuaRef handle identity is Moonlift-owned.
registry_ref is an implementation field.
Only lua_bridge may create, push, or unref registry_ref.
```

Reference lifecycle protocols:

```moonlift
region lua_retain_value(core: ptr(Core), state: LuaStateRef, idx: i32;
    retained(ref: owned LuaRef)
  | invalid_index(idx: i32)
  | unsupported_type(actual: i32)
  | stale_state(state: LuaStateRef)
  | missing_state(state: LuaStateRef)
  | lua_error(code: i32)
  | memory_exhausted(needed: index))
end

region lua_push_ref(core: ptr(Core), state: LuaStateRef, ref: LuaRef;
    pushed(stack_index: i32)
  | stale(ref: LuaRef)
  | missing(ref: LuaRef)
  | wrong_state(ref: LuaRef, state: LuaStateRef)
  | stale_state(state: LuaStateRef)
  | missing_state(state: LuaStateRef)
  | lua_error(code: i32))
end

region lua_release_ref(core: ptr(Core), state: LuaStateRef, ref: owned LuaRef;
    released
  | stale(ref: owned LuaRef)
  | missing(ref: owned LuaRef)
  | wrong_state(ref: owned LuaRef, state: LuaStateRef)
  | stale_state(ref: owned LuaRef, state: LuaStateRef)
  | missing_state(ref: owned LuaRef, state: LuaStateRef)
  | lua_error(ref: owned LuaRef, code: i32))
end
```

`lua_release_ref` consumes ownership on every outcome where the registry
reference has been definitively discharged.  If the operation cannot prove
discharge, the continuation must return the `owned LuaRef` so the caller still
has the obligation.  Implementations must not erase an ownership obligation by
reporting an error.

The same rule applies to every region that accepts an owned bridge resource:

```text
If the resource was discharged, the continuation does not carry it.
If the resource was not discharged, the continuation carries it as owned.
```

## Stack Discipline

The Lua stack is ambient mutable state in the raw C API.  LuaBridge turns stack
effects into explicit protocols.

```moonlift
struct LuaStackMark
    top: i32
end

struct LuaStackRange
    first: i32
    count: i32
end
```

Stack protocols:

```moonlift
region lua_stack_mark(core: ptr(Core), state: LuaStateRef;
    mark(mark: LuaStackMark)
  | stale_state(state: LuaStateRef)
  | missing_state(state: LuaStateRef))
end

region lua_stack_restore(core: ptr(Core), state: LuaStateRef, mark: LuaStackMark;
    restored
  | stack_underflow(expected: i32, got: i32)
  | stack_overflow(expected: i32, got: i32)
  | stale_state(state: LuaStateRef)
  | missing_state(state: LuaStateRef))
end

region lua_stack_check(core: ptr(Core), state: LuaStateRef, mark: LuaStackMark;
    balanced
  | changed(expected: i32, got: i32)
  | stale_state(state: LuaStateRef)
  | missing_state(state: LuaStateRef))
end
```

Every bridge region that touches the stack obeys this pattern:

```text
mark stack
perform raw Lua C API work
return through a typed continuation
restore the stack or expose the exact resulting LuaStackRange
```

No bridge region leaves an undocumented stack effect.

Stack indices returned by bridge regions are valid only under the stack
discipline that produced them.  They are not durable identities and must never
be stored as long-lived Moonlift values.

## Lua Kinds

LuaBridge names Lua runtime kinds without turning Lua into a second static type
system.

```moonlift
union LuaValueKind
    nil_value
  | boolean
  | number
  | string
  | table
  | function
  | userdata
  | thread
  | lightuserdata
  | unknown(code: i32)
end
```

Reading the kind is a stack operation:

```moonlift
region lua_read_type(core: ptr(Core), state: LuaStateRef, idx: i32;
    kind(kind: LuaValueKind)
  | invalid_index(idx: i32)
  | stale_state(state: LuaStateRef)
  | missing_state(state: LuaStateRef))
end
```

LuaBridge may use raw integer Lua type codes internally, but typed code should
traffic in `LuaValueKind`.

## Borrowed Strings

`lua_tolstring` returns memory owned by LuaJIT.  It is borrowed memory, not a
Moonlift allocation.

```moonlift
struct LuaStringBorrow
    data: ptr(u8)
    len: index
    stack_index: i32
    mark: LuaStackMark
end
```

The borrow is valid only while the stack discipline preserves the referenced
Lua value and LuaJIT has not invalidated the pointer.

```moonlift
region lua_borrow_string(core: ptr(Core), state: LuaStateRef, idx: i32;
    string(s: LuaStringBorrow)
  | wrong_type(actual: LuaValueKind)
  | invalid_index(idx: i32)
  | null_string
  | stale_state(state: LuaStateRef)
  | missing_state(state: LuaStateRef))
end
```

Durable string data must be copied into Moonlift-owned memory:

```moonlift
region lua_copy_string(core: ptr(Core), state: LuaStateRef, idx: i32;
    bytes(bytes: owned OwnedBytesRef)
  | wrong_type(actual: LuaValueKind)
  | invalid_index(idx: i32)
  | null_string
  | stale_state(state: LuaStateRef)
  | missing_state(state: LuaStateRef)
  | memory_exhausted(needed: index))
end
```

Borrowing and copying are separate protocols because they have different
ownership meanings.

## Scalar Reads

Scalar reads convert stack values into Moonlift values without retaining Lua
objects.

```moonlift
region lua_read_bool(core: ptr(Core), state: LuaStateRef, idx: i32;
    value(value: bool)
  | wrong_type(actual: LuaValueKind)
  | invalid_index(idx: i32)
  | stale_state(state: LuaStateRef)
  | missing_state(state: LuaStateRef))
end

region lua_read_number(core: ptr(Core), state: LuaStateRef, idx: i32;
    value(value: f64)
  | wrong_type(actual: LuaValueKind)
  | invalid_index(idx: i32)
  | stale_state(state: LuaStateRef)
  | missing_state(state: LuaStateRef))
end
```

Expected-type conversion belongs in named conversion protocols, not in ad hoc
call sites.

```moonlift
region lua_value_to_core_value(core: ptr(Core), state: LuaStateRef, idx: i32, expected: TypeRef;
    value(value: ValueRef)
  | wrong_type(expected: TypeRef, actual: LuaValueKind)
  | unsupported_conversion(actual: LuaValueKind)
  | foreign_userdata
  | invalid_index(idx: i32)
  | stale_state(state: LuaStateRef)
  | missing_state(state: LuaStateRef)
  | lua_error(code: i32)
  | memory_exhausted(needed: index))
end
```

## Push Protocols

Pushing values into Lua must return the exact resulting stack index.

```moonlift
region lua_push_nil(core: ptr(Core), state: LuaStateRef;
    pushed(stack_index: i32)
  | stale_state(state: LuaStateRef)
  | missing_state(state: LuaStateRef)
  | lua_error(code: i32))
end

region lua_push_bool(core: ptr(Core), state: LuaStateRef, value: bool;
    pushed(stack_index: i32)
  | stale_state(state: LuaStateRef)
  | missing_state(state: LuaStateRef)
  | lua_error(code: i32))
end

region lua_push_number(core: ptr(Core), state: LuaStateRef, value: f64;
    pushed(stack_index: i32)
  | stale_state(state: LuaStateRef)
  | missing_state(state: LuaStateRef)
  | lua_error(code: i32))
end

region lua_push_string(core: ptr(Core), state: LuaStateRef, bytes: readonly view(u8);
    pushed(stack_index: i32)
  | stale_state(state: LuaStateRef)
  | missing_state(state: LuaStateRef)
  | lua_error(code: i32)
  | memory_exhausted(needed: index))
end
```

Reverse semantic conversion:

```moonlift
region core_value_to_lua(core: ptr(Core), state: LuaStateRef, value: ValueRef;
    pushed(stack_index: i32)
  | unsupported_value(kind: u8)
  | invalid_ref
  | stale_state(state: LuaStateRef)
  | missing_state(state: LuaStateRef)
  | lua_error(code: i32)
  | memory_exhausted(needed: index))
end
```

LuaBridge should not standardize Lua as a second object model.  It standardizes
the boundary between dynamic host values and Moonlift semantic values.

## Protected Calls

All Lua calls from Moonlift are protected calls.

Raw `lua_call` is not part of the bridge design.  Raw `lua_pcall` is an
implementation pin used by LuaBridge.

```moonlift
struct LuaCallFrame
    mark: LuaStackMark
    fn_index: i32
    first_arg: i32
    nargs: i32
    nresults: i32
end
```

Call frame protocols:

```moonlift
region lua_begin_call(core: ptr(Core), state: LuaStateRef, fn: LuaRef;
    frame(frame: LuaCallFrame)
  | stale(ref: LuaRef)
  | missing(ref: LuaRef)
  | wrong_state(ref: LuaRef, state: LuaStateRef)
  | invalid_function(ref: LuaRef)
  | stale_state(state: LuaStateRef)
  | missing_state(state: LuaStateRef)
  | lua_error(code: i32))
end

region lua_push_call_arg(core: ptr(Core), state: LuaStateRef, frame: LuaCallFrame, value: ValueRef;
    pushed(frame: LuaCallFrame)
  | unsupported_value(kind: u8)
  | stale_state(state: LuaStateRef)
  | missing_state(state: LuaStateRef)
  | lua_error(code: i32)
  | memory_exhausted(needed: index))
end

region lua_finish_call(core: ptr(Core), state: LuaStateRef, frame: LuaCallFrame;
    returned(results: LuaStackRange)
  | lua_error(message: owned LuaErrorRef)
  | stack_unbalanced(expected: i32, got: i32)
  | stale_state(state: LuaStateRef)
  | missing_state(state: LuaStateRef)
  | memory_exhausted(needed: index))
end
```

Single-region protected call:

```moonlift
region lua_call_protected(core: ptr(Core), state: LuaStateRef, fn: LuaRef, args: LuaStackRange, nresults: i32;
    returned(results: LuaStackRange)
  | lua_error(message: owned LuaErrorRef)
  | invalid_function(ref: LuaRef)
  | stack_unbalanced(expected: i32, got: i32)
  | stale_state(state: LuaStateRef)
  | missing_state(state: LuaStateRef)
  | memory_exhausted(needed: index))
end
```

The call frame form is the canonical internal protocol when arguments are
constructed incrementally.  The single-region form is the canonical protocol
when arguments already occupy a checked stack range.

## Lua Errors

Lua errors are values captured by protocols.  They are not unstructured host
exceptions inside Moonlift.

```moonlift
struct LuaErrorRecord
    state: LuaStateRef
    message: LuaRef
    traceback: LuaRef
    code: i32
    generation: u64
end

handle LuaErrorRef : u32 invalid 0
    target LuaErrorRecord
end
```

`owned LuaErrorRef` is a resource obligation.  Releasing it must release any
contained owned registry references or transfer them through a typed protocol.

```moonlift
region capture_lua_error(core: ptr(Core), state: LuaStateRef, err_index: i32;
    error(err: owned LuaErrorRef)
  | invalid_error_object
  | stale_state(state: LuaStateRef)
  | missing_state(state: LuaStateRef)
  | memory_exhausted(needed: index))
end

region lua_error_to_diagnostic(core: ptr(Core), err: LuaErrorRef;
    diagnostic(diag: DiagnosticRef)
  | stale(err: LuaErrorRef)
  | missing(err: LuaErrorRef))
end

region lua_release_error(core: ptr(Core), err: owned LuaErrorRef;
    released
  | stale(err: owned LuaErrorRef)
  | missing(err: owned LuaErrorRef))
end
```

At an outer hosted API boundary, a diagnostic or captured Lua error may be
presented as a Lua exception.  Inside Moonlift, it remains a typed continuation.

## Tables

Lua table traversal is not a free-for-all.  Tables enter Moonlift through named
import protocols that state the semantic role of the table.

Examples:

```moonlift
region lua_import_args_table(core: ptr(Core), state: LuaStateRef, idx: i32;
    args(args: ArgsRef)
  | wrong_type(actual: LuaValueKind)
  | unsupported_key_type(actual: LuaValueKind)
  | unsupported_value_type(actual: LuaValueKind)
  | too_many_args(n: index)
  | invalid_index(idx: i32)
  | stale_state(state: LuaStateRef)
  | missing_state(state: LuaStateRef)
  | lua_error(code: i32)
  | memory_exhausted(needed: index))
end

region lua_import_field_overrides(core: ptr(Core), state: LuaStateRef, idx: i32, subject: ValueRef;
    overrides(overrides: FieldOverrideSetRef)
  | wrong_type(actual: LuaValueKind)
  | no_such_field(name: SymbolRef)
  | field_type_mismatch(field: FieldRef, expected: TypeRef, got: TypeRef)
  | invalid_index(idx: i32)
  | stale_state(state: LuaStateRef)
  | missing_state(state: LuaStateRef)
  | lua_error(code: i32)
  | memory_exhausted(needed: index))
end
```

The rule is:

```text
Lua table shape is interpreted by named bridge regions.
No subsystem should manually iterate Lua tables through raw APIs.
```

This prevents table conventions from spreading as hidden architecture.

## Userdata And Proxies

Lua proxies are Lua-facing representations of Moonlift handles.  They are not
owners of the semantic object unless their protocol explicitly carries an owned
handle.

A proxy must encode:

```text
proxy kind
owning bridge/core generation
semantic handle
metatable identity controlled by LuaBridge
```

Proxy decode is a bridge protocol:

```moonlift
region lua_decode_proxy(core: ptr(Core), state: LuaStateRef, idx: i32, expected_kind: u8;
    proxy(value: ValueRef)
  | wrong_type(actual: LuaValueKind)
  | wrong_proxy_kind(expected: u8, actual: u8)
  | foreign_userdata
  | stale_proxy
  | invalid_index(idx: i32)
  | stale_state(state: LuaStateRef)
  | missing_state(state: LuaStateRef)
  | lua_error(code: i32))
end
```

Specific semantic proxy protocols may be layered on top:

```moonlift
region lua_push_core_proxy(core: ptr(Core), state: LuaStateRef, value: ValueRef;
    pushed(stack_index: i32)
  | unsupported_value(kind: u8)
  | invalid_ref
  | stale_state(state: LuaStateRef)
  | missing_state(state: LuaStateRef)
  | lua_error(code: i32)
  | memory_exhausted(needed: index))
end
```

LuaBridge owns proxy safety and identity.  The semantic subsystem owns the
meaning of the handle behind the proxy.

## Conversion Matrix

LuaBridge has an explicit conversion matrix.

```text
Lua nil
    may become a nil value, absent optional value, or empty semantic value
    only under a named expected role

Lua boolean
    may become bool

Lua number
    may become f64 directly
    may become integer only through expected-type conversion

Lua string
    may become borrowed LuaStringBorrow
    may become owned bytes by copying
    may become SymbolRef through symbol-intern protocol

Lua table
    may become args, overrides, builders, or semantic records
    only through named import protocols

Lua function
    may become owned LuaRef
    callability is checked by call protocols

Lua userdata
    may become a decoded proxy
    foreign userdata is a typed rejection

Lua thread/lightuserdata
    rejected unless a named protocol explicitly accepts it
```

No conversion should be hidden in helper callbacks or stringly metadata.

## Raw Extern Layer

`moonlift.lua_raw` centralizes raw pins.  It declares only the functions required
to implement LuaBridge.

Representative externs:

```moonlift
extern lua_gettop(L: ptr(u8)): i32 as "moonlift_lua_raw_gettop" end
extern lua_settop(L: ptr(u8), idx: i32) as "moonlift_lua_raw_settop" end
extern lua_type(L: ptr(u8), idx: i32): i32 as "moonlift_lua_raw_type" end
extern lua_tolstring(L: ptr(u8), idx: i32, len: ptr(index)): ptr(u8) as "moonlift_lua_raw_tolstring" end
extern lua_toboolean(L: ptr(u8), idx: i32): i32 as "moonlift_lua_raw_toboolean" end
extern lua_tonumber(L: ptr(u8), idx: i32): f64 as "moonlift_lua_raw_tonumber" end
extern lua_pushvalue(L: ptr(u8), idx: i32) as "moonlift_lua_raw_pushvalue" end
extern lua_pushnil(L: ptr(u8)) as "moonlift_lua_raw_pushnil" end
extern lua_pushboolean(L: ptr(u8), b: i32) as "moonlift_lua_raw_pushboolean" end
extern lua_pushnumber(L: ptr(u8), n: f64) as "moonlift_lua_raw_pushnumber" end
extern lua_pushlstring(L: ptr(u8), s: ptr(u8), len: index) as "moonlift_lua_raw_pushlstring" end
extern lua_rawgeti(L: ptr(u8), idx: i32, n: i32) as "moonlift_lua_raw_rawgeti" end
extern lua_rawseti(L: ptr(u8), idx: i32, n: i32) as "moonlift_lua_raw_rawseti" end
extern luaL_ref(L: ptr(u8), t: i32): i32 as "moonlift_lua_raw_lref" end
extern luaL_unref(L: ptr(u8), t: i32, ref: i32) as "moonlift_lua_raw_lunref" end
extern lua_pcall(L: ptr(u8), nargs: i32, nresults: i32, errfunc: i32): i32 as "moonlift_lua_raw_pcall" end
```

These externs are pins, not architecture.  They should not be re-exported by
normal Moonlift modules.

## Diagnostics

Bridge diagnostics should report:

```text
operation name
LuaStateRef
LuaRef or LuaErrorRef when applicable
expected LuaValueKind or semantic type
actual LuaValueKind or raw Lua status code
stack mark and observed top for stack failures
unsafe raw boundary when raw APIs are involved
```

Diagnostics should not expose raw registry integers except in debug-only
inspection paths.  A registry integer is not the user's resource handle.

## Implementation Rules

LuaBridge implementation files must obey these rules:

```text
Every raw stack mutation is inside a region with declared stack behavior.
Every retained registry reference becomes owned LuaRef.
Every owned LuaRef is discharged or transferred exactly once.
Every borrowed Lua pointer is named as a borrow.
Every Lua call is protected.
Every Lua error is captured or converted at a typed boundary.
Every cross-state use is checked.
Every table import has a named semantic role.
Every proxy decode checks kind, generation, and foreign userdata.
```

Forbidden patterns:

```text
storing raw stack indices in durable records
passing registry_ref integers outside lua_bridge
calling lua_pcall outside lua_bridge
calling lua_call from Moonlift code
using Lua errors as internal control flow
returning borrowed string pointers as durable memory
manual table iteration in semantic subsystems
silent stack cleanup without a declared protocol
```

## Relationship To Higher Layers

LuaBridge is below compiler phases, semantic stores, and public Lua APIs.

It does not define the compiler's phase model.  It does not define PVM.  It does
not decide what a semantic node, stream, phase, or builder means.

It defines the only lawful way those layers may cross into LuaJIT:

```text
retain Lua value
push Lua value
read Lua value
copy Lua data
call Lua function
capture Lua error
import Lua table by semantic role
encode/decode Lua proxy
restore or expose stack effects
```

Higher layers may build beautiful Lua-facing APIs on top of this.  They may not
inherit LuaJIT's raw stack and registry discipline as invisible architecture.

## Final Doctrine Card

```text
Raw lua_* externs are pins, not architecture.
lua_raw is unsafe and internal.
lua_bridge_model names the boundary facts.
lua_bridge is the only normal user of lua_raw.

LuaJIT owns Lua object memory.
Moonlift owns registry-reference obligations.
LuaRef is durable identity.
owned LuaRef is exactly-one release authority.

LuaStateRef gives state identity and generation checks.
Cross-state LuaRef use is a typed outcome.

Lua stack values are borrowed, positional, and temporary.
Lua stack effects must be marked, restored, checked, or exposed as ranges.
Lua string pointers are borrowed, not durable.

Lua calls are protected.
Lua errors are captured values and typed continuations.
Lua tables are imported by named semantic regions.
Lua userdata is decoded as controlled proxies or rejected as foreign.

No raw stack convention, registry integer, table shape, or handler error path
may become hidden architecture.
```
