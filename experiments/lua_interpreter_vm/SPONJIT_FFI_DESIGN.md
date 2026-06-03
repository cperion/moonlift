# SpongeJIT First-Class FFI Design

## Purpose

Design a first-class Lua FFI for the Moonlift-native Lua VM and SpongeJIT path,
with LuaJIT-class ergonomics and performance, but expressed through explicit
programming: typed data, typed control protocols, no hidden interpreter dispatch,
and no stringly semantic runtime.

The FFI is not a side library. It is part of Lua runtime semantics and part of
JIT/stencil generation. `ffi.cdef`, `ffi.load`, `ffi.C`, `ffi.new`, `ffi.cast`,
`ffi.typeof`, field access, pointer arithmetic, calls, callbacks, finalizers,
and cdata identity all need explicit types and protocols.

---

## One-sentence architecture

FFI parses C declarations into typed FFI declaration data, resolves layouts and
symbols into typed runtime handles, represents cdata as typed values, lowers FFI
operations into LuaExec/MoonCFG semantic regions, and generates stencils whose
calls/loads/stores/relocs are derived from those typed FFI facts.

```text
Lua ffi API call / cdef source
  -> FFI declaration/type model
  -> FFI registry + symbol table
  -> cdata values and operations
  -> LuaExec / MoonCFG regions
  -> Moonlift / Cranelift calls, loads, stores
  -> stencil templates with symbol/offset/ABI patch holes
```

No FFI operation may be implemented as “call LuaJIT FFI” or “ask host
interpreter.” The Moonlift VM owns the FFI runtime.

---

# Design rule: types first

The FFI has two trees.

## Data tree

What exists:

- C type declarations;
- C layouts;
- C symbols and libraries;
- cdata values;
- ownership/finalizer state;
- callback thunks;
- ABI/calling-convention data;
- errors and diagnostics.

## Control tree

What can happen:

- parse declarations;
- intern/resolve types;
- compute layout;
- load libraries;
- resolve symbols;
- allocate cdata;
- cast cdata;
- read/write fields/elements;
- call C functions;
- invoke callbacks;
- attach/detach finalizers;
- report type/layout/symbol/call errors.

Every meaningful alternative is a `union` variant or a region continuation.
No status strings. No integer kind fields with comments. No hidden global magic.

---

# Data tree

## Handles

```moonlift
struct CTypeId        id: u64 end
struct CDeclId        id: u64 end
struct CLibId         id: u64 end
struct CSymbolId      id: u64 end
struct CCallbackId    id: u64 end
struct CMetatypeId    id: u64 end
```

Handles are typed. They are not interchangeable integers.

## C scalar kinds

```moonlift
union CScalarKind
    c_void()
  | c_bool()
  | c_char()
  | c_schar()
  | c_uchar()
  | c_short()
  | c_ushort()
  | c_int()
  | c_uint()
  | c_long()
  | c_ulong()
  | c_longlong()
  | c_ulonglong()
  | c_int8()
  | c_uint8()
  | c_int16()
  | c_uint16()
  | c_int32()
  | c_uint32()
  | c_int64()
  | c_uint64()
  | c_size_t()
  | c_ssize_t()
  | c_intptr_t()
  | c_uintptr_t()
  | c_float()
  | c_double()
  | c_longdouble()
end
```

## C type model

```moonlift
union CType
    scalar(kind: CScalarKind)
  | pointer(to: CTypeId, is_const: bool, is_volatile: bool)
  | array(of: CTypeId, count: u64)
  | incomplete_array(of: CTypeId)
  | function(params: CParamListId, result: CTypeId, abi: CAbi)
  | struct_type(layout: CRecordLayoutId)
  | union_type(layout: CRecordLayoutId)
  | enum_type(layout: CEnumLayoutId)
  | typedef_type(name: CNameId, target: CTypeId)
  | opaque_tag(name: CNameId)
end
```

`opaque_tag` represents incomplete `struct foo;` declarations. It is a real
variant, not a null layout.

## Names

Names are data, but internal distinctions are handles.

```moonlift
struct CNameId id: u64 end
struct CName
    id: CNameId
    bytes: view(u8)
end
```

The runtime can compare `CNameId`; diagnostics can print `bytes`.

## Parameters and functions

```moonlift
union CParamMode
    by_value()
  | pointer_in()
  | pointer_out()
  | pointer_inout()
end

struct CParam
    name: CNameId
    ctype: CTypeId
    mode: CParamMode
end

struct CParamList
    params: view(CParam)
    is_variadic: bool
end

union CAbi
    system_v_amd64()
  | win64()
  | aarch64_sysv()
  | cdecl()
  | stdcall()
end
```

ABI is explicit because call lowering and stencil relocation depend on it.

## Record layout

```moonlift
union CFieldKind
    normal()
  | bitfield(width_bits: u16, bit_offset: u16)
  | flexible_array_member()
end

struct CField
    name: CNameId
    ctype: CTypeId
    offset_bits: u64
    size_bits: u64
    align_bits: u32
    kind: CFieldKind
end

struct CRecordLayout
    name: CNameId
    fields: view(CField)
    size_bytes: u64
    align_bytes: u32
    is_packed: bool
    is_complete: bool
end
```

`offsetof`, `sizeof`, `alignof`, and field access derive from this layout.

## Enum layout

```moonlift
struct CEnumItem
    name: CNameId
    value: i64
end

struct CEnumLayout
    name: CNameId
    repr: CScalarKind
    items: view(CEnumItem)
end
```

## Libraries and symbols

```moonlift
union CLibKind
    default_process()
  | dynamic_library(path: CNameId)
end

struct CLib
    id: CLibId
    kind: CLibKind
    handle: ptr(u8)
end

union CSymbolKind
    function_symbol(ctype: CTypeId)
  | data_symbol(ctype: CTypeId)
end

struct CSymbol
    id: CSymbolId
    lib: CLibId
    name: CNameId
    kind: CSymbolKind
    address: ptr(u8)
end
```

Symbols are typed. A function symbol and a data symbol are distinct variants.

## C data values

```moonlift
union CStorageKind
    inline_bytes()
  | external_pointer()
  | owned_heap()
  | borrowed_lua_buffer()
  | static_symbol()
end

struct CStorage
    kind: CStorageKind
    ptr: ptr(u8)
    size_bytes: u64
    owner: u64
end

struct CData
    ctype: CTypeId
    storage: CStorage
    finalizer: CFinalizerId
    metatype: CMetatypeId
end
```

Cdata stores type and storage explicitly. Pointer cdata is not the same thing as
inline struct cdata.

## Finalizers and ownership

```moonlift
struct CFinalizerId id: u64 end

union CFinalizer
    none()
  | c_function(symbol: CSymbolId)
  | lua_closure(ref: u64)
end

union OwnershipState
    unmanaged()
  | owned()
  | finalizer_attached(finalizer: CFinalizerId)
  | finalizer_detached()
end
```

`ffi.gc(cdata, finalizer)` changes typed ownership state. It is not a side-table
convention.

## Callbacks

```moonlift
struct CCallback
    id: CCallbackId
    signature: CTypeId
    lua_callable_ref: u64
    thunk_address: ptr(u8)
    live: bool
end
```

Callbacks are explicit runtime objects with type, thunk, Lua callable reference,
and lifetime.

## FFI registry

```moonlift
struct FFIRegistry
    types: view(CType)
    records: view(CRecordLayout)
    enums: view(CEnumLayout)
    names: view(CName)
    libs: view(CLib)
    symbols: view(CSymbol)
    callbacks: view(CCallback)
end
```

The registry is an explicit state object passed to FFI regions.

---

# Control tree

## Declaration parsing and interning

```moonlift
region ffi_cdef(reg: ptr(FFIRegistry), src: view(u8);
    ok: cont(updated: ptr(FFIRegistry)),
    parse_error: cont(offset: index, code: u32),
    unsupported_decl: cont(offset: index, code: u32),
    layout_error: cont(type_name: CNameId, code: u32))
```

`ffi.cdef` is not stringly after parsing. Source text is input; typed
declarations are output.

```moonlift
region intern_ctype(reg: ptr(FFIRegistry), ctype: CType;
    interned: cont(id: CTypeId),
    recursive_incomplete: cont(name: CNameId),
    layout_error: cont(code: u32))
```

## Type queries

```moonlift
region ffi_typeof(reg: ptr(FFIRegistry), spec: view(u8);
    found: cont(type_id: CTypeId),
    parse_error: cont(offset: index, code: u32),
    unknown_type: cont(name: CNameId))

region ffi_sizeof(reg: ptr(FFIRegistry), type_id: CTypeId;
    known: cont(size: u64),
    incomplete: cont(type_id: CTypeId))

region ffi_alignof(reg: ptr(FFIRegistry), type_id: CTypeId;
    known: cont(align: u32),
    incomplete: cont(type_id: CTypeId))

region ffi_offsetof(reg: ptr(FFIRegistry), type_id: CTypeId, field: CNameId;
    known: cont(offset_bytes: u64),
    no_such_field: cont(field: CNameId),
    not_record: cont(type_id: CTypeId),
    bitfield: cont(field: CNameId))
```

## Library and symbol resolution

```moonlift
region ffi_load(reg: ptr(FFIRegistry), path: view(u8);
    loaded: cont(lib: CLibId),
    open_failed: cont(code: i32))

region ffi_resolve_symbol(reg: ptr(FFIRegistry), lib: CLibId, name: CNameId;
    found: cont(symbol: CSymbolId, address: ptr(u8)),
    not_found: cont(name: CNameId),
    wrong_kind: cont(symbol: CSymbolId))
```

## Allocation and casting

```moonlift
region ffi_new(reg: ptr(FFIRegistry), type_id: CTypeId, init: LuaValueSeq;
    created: cont(cdata: CData),
    incomplete_type: cont(type_id: CTypeId),
    init_error: cont(code: u32),
    alloc_failed: cont(size: u64))

region ffi_cast(reg: ptr(FFIRegistry), target: CTypeId, value: LuaValue;
    casted: cont(cdata: CData),
    invalid_cast: cont(from: LuaValueKind, to: CTypeId),
    overflow: cont())
```

## Field and element access

```moonlift
region ffi_get_field(reg: ptr(FFIRegistry), cdata: CData, field: CNameId;
    value: cont(result: LuaValue),
    no_such_field: cont(field: CNameId),
    not_record: cont(type_id: CTypeId),
    bitfield_read: cont(result: LuaValue))

region ffi_set_field(reg: ptr(FFIRegistry), cdata: CData, field: CNameId, value: LuaValue;
    stored: cont(),
    no_such_field: cont(field: CNameId),
    not_record: cont(type_id: CTypeId),
    conversion_error: cont(code: u32),
    readonly: cont())

region ffi_index(reg: ptr(FFIRegistry), cdata: CData, index: i64;
    value: cont(result: LuaValue),
    not_indexable: cont(type_id: CTypeId),
    out_of_bounds: cont(index: i64))
```

## C function calls

```moonlift
region ffi_call(
    reg: ptr(FFIRegistry),
    symbol: CSymbolId,
    args: LuaValueSeq;

    returned: cont(values: LuaValueSeq),
    conversion_error: cont(arg_index: index, code: u32),
    arity_error: cont(expected: index, got: index),
    unsupported_abi: cont(abi: CAbi),
    call_trap: cont(code: u32))
```

Call lowering must be operation-specific and signature-specific. It cannot call a
catch-all `execute_ffi_call(symbol, args)` from hot stencils if that helper hides
ABI conversion. The generic API region can exist as a source-level operation,
but JIT/stencil lowering must specialize to typed signature and ABI.

## Callbacks

```moonlift
region ffi_make_callback(reg: ptr(FFIRegistry), signature: CTypeId, callable: LuaValue;
    made: cont(callback: CCallback),
    not_function_type: cont(type_id: CTypeId),
    unsupported_abi: cont(abi: CAbi),
    alloc_failed: cont(size: u64))

region ffi_callback_enter(reg: ptr(FFIRegistry), callback: CCallback, raw_args: ptr(u8);
    returned: cont(raw_result: ptr(u8)),
    lua_error: cont(code: u32),
    conversion_error: cont(arg_index: index, code: u32))
```

Callbacks cross from C into Lua. Their continuations must represent Lua error
and conversion failure explicitly.

## Finalizers

```moonlift
region ffi_gc_attach(reg: ptr(FFIRegistry), cdata: CData, finalizer: CFinalizer;
    attached: cont(cdata: CData),
    invalid_finalizer: cont(),
    ownership_error: cont())

region ffi_run_finalizer(reg: ptr(FFIRegistry), cdata: CData;
    done: cont(),
    finalizer_error: cont(code: u32))
```

---

# Lua API surface

Target Lua API should match LuaJIT-class expectations:

```lua
local ffi = require("ffi")
ffi.cdef[[ ... ]]
local C = ffi.C
local lib = ffi.load("libc.so.6")
local T = ffi.typeof("struct foo")
local x = ffi.new("struct foo[?]", n)
local p = ffi.cast("uint8_t *", x)
ffi.sizeof(T)
ffi.alignof(T)
ffi.offsetof(T, "field")
ffi.istype(T, x)
ffi.gc(x, finalizer)
ffi.metatype(T, methods)
```

But internally this API must lower to typed FFI operations. The surface may use
strings because LuaJIT compatibility requires string declarations; after parse,
strings are gone from semantics.

---

# Stencil and fact integration

FFI facts become part of stencil selection when needed.

Examples:

```moonlift
union RuntimeFact
    ffi_type_eq(value_slot: u32, type_id: CTypeId)
  | ffi_symbol_resolved(symbol: CSymbolId, address: ptr(u8))
  | ffi_layout_eq(type_id: CTypeId, layout_hash: u64)
  | ffi_callback_live(callback: CCallbackId)
end
```

FFI patch holes may include:

```moonlift
union PatchKind
    ffi_symbol_addr64(symbol: CSymbolId)
  | ffi_field_offset32(type_id: CTypeId, field: CNameId)
  | ffi_sizeof_imm32(type_id: CTypeId)
  | ffi_alignof_imm32(type_id: CTypeId)
  | ffi_callback_thunk64(callback: CCallbackId)
end
```

A stencil for `libc.memcpy(dst, src, n)` must be keyed by the typed function
signature, ABI, symbol identity, and target ABI. It must not be keyed by the
string `"memcpy"` alone or by Lua opcode shape.

---

# LuaJIT-quality requirements

## Required features

- C declaration parser for the practical LuaJIT FFI subset.
- `ffi.cdef` declaration interning.
- `ffi.C` default namespace.
- `ffi.load` dynamic library namespaces.
- `ffi.typeof` with canonical type identity.
- `ffi.new` for scalars, structs, arrays, variable-length arrays where
  supported.
- `ffi.cast` for numeric/pointer/cdata conversions.
- `ffi.sizeof`, `ffi.alignof`, `ffi.offsetof`.
- Pointer arithmetic and indexing.
- Struct/union field read/write.
- Array element read/write.
- Function pointer calls.
- C function symbol calls.
- Callbacks from C to Lua.
- `ffi.gc` finalizers.
- `ffi.istype`.
- Metatype/method support for cdata where compatible with Lua semantics.
- Good diagnostics: parse offset, type name, field name, ABI/layout failure.

## Performance requirements

- Hot FFI calls specialize by signature and ABI.
- Field offsets and sizes are constants/patch holes, not dynamic string lookups.
- Symbol addresses are resolved once and become typed patch values/relocs.
- Cdata loads/stores lower to MoonCFG memory ops.
- No vararg boxing loop in hot path unless the C signature is genuinely variadic.
- Callbacks use precompiled typed thunks.

---

# Forbidden patterns

- Calling LuaJIT FFI as implementation.
- Opaque `ffi_do(op_string, args)` helpers.
- Runtime field lookup by string in hot stencil paths.
- Function calls through untyped `ptr(u8)` without signature identity.
- Cdata as a black-box Lua table.
- Callback dispatch through a generic interpreter frame without typed thunk.
- ABI decisions encoded as integer constants without a `CAbi` variant.
- Layout decisions hidden in C/Rust side tables.

---

# Relationship to Moonlift extern

Moonlift `extern` is the compiler/runtime implementation tool. Lua FFI is the
Lua-visible feature.

```text
Moonlift extern:
  typed import used by Moonlift code and runtime implementation.

Lua FFI:
  dynamic Lua API that parses C declarations and creates cdata/symbol/call
  semantics for Lua programs.
```

The FFI runtime may use Moonlift externs for platform functions (`dlopen`,
`dlsym`, `mmap`, libc helpers), but the Lua FFI semantic model is separate and
first-class.

---

# Testing policy

Main tests should be positive intended behavior:

- parse cdef and query type layout;
- allocate struct cdata and read/write fields;
- cast pointer and index memory;
- load libc and call a typed symbol;
- attach finalizer and observe finalizer execution;
- create callback and call through C/function pointer path;
- generate stencil for an FFI call and verify no generic FFI helper dispatch;
- verify field-offset stencil uses typed layout facts/patch holes.

Malformed cdefs and invalid casts can have validator/error tests, but they must
not be used to claim feature completion.

---

# Open design questions

- Exact C parser subset and how close to LuaJIT syntax compatibility to target
  first.
- Full treatment of C bitfields across ABIs.
- Variadic C calls and default argument promotions.
- Long double and complex number support.
- Callback lifetime and GC interaction.
- Metatype method semantics and interaction with Lua metamethod lookup.
- Cross-platform ABI coverage order.
- Whether FFI registry is per Lua state, shared immutable plus per-state dynamic,
  or bank-generated.

---

# Summary

First-class FFI adds a new explicit subsystem:

```text
C declarations -> typed FFI registry -> cdata/symbol/callback values
  -> LuaExec/MoonCFG FFI regions
  -> Moonlift/Cranelift/stencil fast paths
```

It should feel like LuaJIT FFI at the Lua surface, but internally every C type,
layout, symbol, cdata value, call ABI, callback, finalizer, and error path is a
Moonlift/ASDL-visible typed distinction.
