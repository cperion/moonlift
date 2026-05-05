# Moonlift C Interop — Target Architecture

**Status:** target design. This document is normative for the C interop work.

**Goal:** let Moonlift code call C libraries and exchange C data with exact C ABI
semantics, while preserving Moonlift's doctrine: Lua performs staging and fact
production; Moonlift receives explicit monomorphic ASDL facts; the backend
consumes explicit facts and never guesses from strings.

---

## 1. Scope and non-goals

### In scope

- Curated C declarations embedded in Moonlift source with `import c`.
- C scalar, pointer, enum, array, struct, union, typedef, and function pointer
  types accepted by LuaJIT FFI `ffi.cdef`.
- Complete and incomplete/opaque C types.
- Compile-time C layout queries: `csizeof`, `coffsetof`, and `calignof`.
- C functions imported from the process symbol namespace or an explicitly loaded
  shared library.
- C callbacks: passing the address of a Moonlift `export func` to C as a C
  function pointer.
- C aggregate by-value calls **only on targets with an implemented C ABI plan**.
  The compiler must reject aggregate by-value calls on targets whose ABI planner
  is not implemented.
- JIT and object/shared-object emission for the same C ABI as the running LuaJIT
  host process.

### Explicitly out of scope

- Header crawling and preprocessing. Users or Lua code must provide already
  preprocessed/curated declarations. `#include`, macros, and conditional
  compilation are not parsed by Moonlift.
- C++. No templates, classes, overload sets, references, exceptions, namespaces,
  or name mangling.
- C varargs. Vararg function declarations are rejected at `cimport` time.
- C `volatile` semantics and C11 memory-order-specific atomics. Cranelift 0.131
  has sequentially-consistent atomic instructions, but no volatile load/store
  flag and no acquire/release/relaxed ordering parameter. Moonlift must not
  pretend otherwise in this C interop design.
- Ownership, lifetime, and GC interop. C pointers are raw.
- Longjmp/exception interop.
- Cross-compiling C interop to a different C ABI than the running LuaJIT host.
  LuaJIT FFI reports the host C layout. If Moonlift later supports C interop
  cross-compilation, it must add a separate target C layout provider and must
  not reuse host FFI layout facts.

---

## 2. Core principles

1. **LuaJIT FFI is the authority for C syntax acceptance and data layout.**
   `ffi.cdef`, `ffi.typeof`, `ffi.sizeof`, `ffi.alignof`, and `ffi.offsetof`
   validate declarations and provide target-correct sizes, alignments, field
   offsets, and bitfield metadata.

2. **Moonlift still has one semantic type system.** A C type is represented as a
   Moonlift type node that points to an explicit `CTypeId` fact. It is not a
   backend-only string.

3. **The backend never receives an aggregate as `BackScalar`.** Cranelift scalar
   IR has no C struct scalar type. C aggregates are represented as memory plus
   explicit layout and explicit C ABI call plans.

4. **LuaJIT FFI is not an introspection API for declarations.** It does not
   enumerate struct fields or function prototypes portably. Therefore the
   `cimport` phase has two inputs: the FFI parser for validation/layout, and a
   Moonlift-owned Lua declaration parser (`lib/c_decl_parse.lua`) for producing
   ASDL facts. The parser never computes layout; it only records names, field
   declarations, and signatures to query through FFI.

5. **Every ABI decision is a fact.** By-value aggregate calls are lowered from a
   `CAbiPlan` fact. The Rust/Cranelift backend must not reclassify C types from
   names or layouts on its own.

---

## 3. Source syntax

### 3.1 C imports

```text
import_c_decl ::= "import" "c" [ "from" string_lit ] cdef_string
cdef_string   ::= string_lit | long_string_lit
```

Both short and long Lua-style strings are accepted; long strings are preferred.
The string content is LuaJIT FFI cdef syntax, restricted to declarations that
`c_decl_parse.lua` can also parse. Unsupported top-level C declarations are a
`c_import_unsupported_declaration` diagnostic; they are never ignored silently.

```moonlift
import c [[
    void* malloc(size_t n);
    void free(void* p);
]]

import c from "m" [[
    double cos(double x);
    double sqrt(double x);
]]
```

`from` names a library for JIT symbol resolution and for object-link facts.

### 3.2 Imported names, scoping, and duplicates

- C types and functions imported by `import c` are module-scoped facts.
- Unqualified C function names are inserted into the importing module's value
  namespace. A collision with an existing function, extern, const, static, or
  previous C import is a diagnostic unless the declaration is byte-for-byte the
  same symbol and signature from the same library.
- C types are addressed by canonical `CTypeId { module_name, spelling }` facts.
  In source, `c("T")` resolves only in the current module's C import registry.
  To expose a C type across modules, define a normal Moonlift type alias such as
  `type Sqlite3 = c("sqlite3")`; consumers then import and refer to that alias
  through the ordinary Moonlift module/type namespace.
- Two different C spellings that `ffi.typeof` reports as the same typedef/type
  within the same module are aliases to one `CTypeId`; incompatible
  redefinitions are diagnostics.
- A C function symbol imported from two different libraries is a diagnostic;
  this design does not silently choose one.

### 3.3 C types in Moonlift type position

```text
c_type ::= "c" "(" string_lit ")"
```

The string is an exact C type spelling accepted by `ffi.typeof`. Built-in C
scalar names known to LuaJIT FFI (`int`, `double`, `size_t`, `void*`, etc.) are
pre-registered in every module. User-defined typedef/tag names must come from an
`import c` block. Typedef names are recommended. Tag names must include their C
keyword:

```moonlift
let p: ptr(c("sqlite3"))        -- typedef name
let q: ptr(c("struct sqlite3")) -- struct tag spelling
```

Rules:

- `c("T")` must resolve to a built-in C type or a C type imported by the current
  module. Cross-module use goes through ordinary Moonlift named type aliases,
  not through the `c(...)` string namespace.
- Complete object types may be used by value.
- Incomplete object types may only be used behind `ptr(...)`.
- `void` is valid only as a C function result. `void*` maps to Moonlift
  `ptr(u8)`; Moonlift still has no `ptr(void)`.
- C qualifiers (`const`, `restrict`) are metadata/contract facts, not separate
  Moonlift runtime types. `volatile`-qualified objects are rejected by this
  design because the backend cannot implement C volatile semantics correctly.

### 3.4 Layout constants

```text
csizeof_expr   ::= "csizeof"  "(" string_lit ")"
coffsetof_expr ::= "coffsetof" "(" string_lit "," string_lit ")"
calignof_expr  ::= "calignof" "(" string_lit ")"
```

All three return a compile-time constant of type `index`.

```moonlift
const POINT_SIZE: index  = csizeof("point_t")
const POINT_Y: index     = coffsetof("point_t", "y")
const POINT_ALIGN: index = calignof("point_t")
```

Rules:

- `csizeof(T)` and `calignof(T)` require a complete C object type or a pointer
  type. They reject incomplete object types.
- `coffsetof(T, field)` requires a complete struct or union.
- For pointer layout use a pointer spelling, e.g. `csizeof("sqlite3 *")`.
- Results are folded during typecheck/cimport and lower to ordinary `CmdConst`
  integer constants. There is no backend `sizeof` command.

### 3.5 Function pointers and callbacks

C function pointer typedefs imported from C are used with `c("typedef_name")`.
Moonlift also provides an explicit C function pointer constructor for hand-written
signatures:

```text
cfunc_type ::= "cfunc" "(" [ type { "," type } ] ")" "->" type
addr_func  ::= "&" ident
```

`cfunc` is a C ABI function pointer type. It is distinct from any Moonlift-native
closure/function ABI.

```moonlift
import c [[
    typedef int (*cmp_t)(const void*, const void*);
    void qsort(void* base, size_t n, size_t size, cmp_t cmp);
]]

export func my_cmp(a: ptr(u8), b: ptr(u8)) -> i32
    let av: i32 = *(as(ptr(i32), a))
    let bv: i32 = *(as(ptr(i32), b))
    if av < bv then return -1 end
    if av > bv then return 1 end
    return 0
end

qsort(data, n, csizeof("int"), &my_cmp)
```

`&name` is valid only for a Moonlift `export func` with a C-callable signature.
The function address remains valid only while the compiled artifact is loaded.
No closures or captured Lua values are supported.

A Moonlift `export func` used as a C callback is compiled at its public symbol
boundary with the same C ABI planner used for imported C calls. Scalar/pointer
callbacks are Phase 3. Aggregate-by-value callback parameters or results require
Phase 5 aggregate ABI support for the target; otherwise `&name` fails with
`c_abi_unsupported`.

---

## 4. C import phase

The hosted pipeline becomes:

```text
parse → cimport → check → lower → back-validate → emit
```

`cimport` performs these steps for every `ImportC` node, in source order:

1. Verify that the Moonlift backend target uses the same C ABI as the running
   LuaJIT host. Otherwise emit `c_cross_target_unsupported`.
2. Call `ffi.cdef(cdef_string)`. Failure produces `cdef_parse_error`.
3. Parse the same string with `lib/c_decl_parse.lua`. The parser records
   declarations; it does not compute layout or ABI classification.
4. Canonicalize every C type spelling through `ffi.typeof`.
5. For complete object types, query `ffi.sizeof`, `ffi.alignof`, and field
   offsets. For bitfields, record byte offset, bit offset, and bit width when
   `ffi.offsetof` provides them.
6. For incomplete object types, produce an opaque type fact.
7. For each function prototype, reject varargs; map parameter and result types;
   produce a `CExternFunc` fact.
8. For each C function pointer typedef, produce a `CFuncPointerType` fact.
9. If `from "lib"` is present:
   - In JIT mode, call `ffi.load(lib)`, resolve all referenced function symbols,
     register them with the JIT symbol table, and keep the library handle alive.
   - In object/shared-object mode, produce link facts (`-l` name or explicit
     path) and leave extern symbols undefined for the final linker.

No declaration is made available to typecheck until all diagnostics for its
import block have been produced.

### 4.1 LuaJIT FFI global namespace discipline

LuaJIT `ffi.cdef` mutates one Lua-state-global C namespace; Moonlift module
scoping is stricter than FFI scoping. Therefore cimport maintains a process-wide
`CdefRegistry` keyed by canonical declaration fingerprint. The fingerprint is
`{declaration_kind, C name, canonical parsed type tree, relevant qualifiers}`;
whitespace, comments, and parameter names do not affect it.

- The same declaration text/fingerprint may be imported multiple times and is
  passed to `ffi.cdef` only once.
- A second declaration that defines the same C name with the same canonical type
  is accepted as an alias in Moonlift facts but is not re-submitted to FFI.
- A second declaration that defines the same C name incompatibly is rejected
  before calling `ffi.cdef`, producing `c_type_redefinition` or
  `c_function_redefinition`.
- Module-local visibility is enforced by Moonlift's C import registry, not by
  relying on LuaJIT FFI visibility.

---

## 5. Required facts and ASDL additions

Names below are normative target names; exact builder helper names may differ,
but the facts and fields must exist explicitly.

### 5.1 Type-level facts

```lua
A.product "CTypeId" {
    A.field "module_name" "string",
    A.field "spelling" "string", -- canonical ffi.typeof spelling
    A.unique,
}

A.sum "CTypeKind" {
    A.variant "CVoid",
    A.variant "CScalar" { A.field "scalar" "MoonBack.BackScalar" },
    A.variant "CPointer" { A.field "pointee" "MoonC.CTypeId" },
    A.variant "CEnum" { A.field "scalar" "MoonBack.BackScalar" },
    A.variant "CArray" { A.field "elem" "MoonC.CTypeId", A.field "count" "number" },
    A.variant "CStruct",
    A.variant "CUnion",
    A.variant "COpaque",
    A.variant "CFuncPointer" { A.field "sig" "MoonC.CFuncSigId" },
}

A.product "CTypeFact" {
    A.field "id" "MoonC.CTypeId",
    A.field "kind" "MoonC.CTypeKind",
    A.field "complete" "boolean",
    A.field "size" (A.optional "number"),
    A.field "align" (A.optional "number"),
    A.unique,
}
```

Moonlift type schema adds:

```lua
A.variant "TCType" {
    A.field "id" "MoonC.CTypeId",
    A.variant_unique,
}

A.variant "TCFuncPtr" {
    A.field "sig" "MoonC.CFuncSigId",
    A.variant_unique,
}
```

### 5.2 Layout facts

```lua
A.product "CFieldLayout" {
    A.field "owner" "MoonC.CTypeId",
    A.field "name" "string",
    A.field "type" "MoonC.CTypeId",
    A.field "offset" "number",
    A.field "size" "number",
    A.field "align" "number",
    A.field "bit_offset" (A.optional "number"),
    A.field "bit_width" (A.optional "number"),
    A.unique,
}

A.product "CLayoutFact" {
    A.field "type" "MoonC.CTypeId",
    A.field "size" "number",
    A.field "align" "number",
    A.field "fields" (A.many "MoonC.CFieldLayout"),
    A.unique,
}
```

For Moonlift-host-facing APIs these facts may be mirrored into existing
`HostTypeLayout` / `HostFieldLayout`, but C layout facts remain the source for C
imports.

### 5.3 Function and library facts

```lua
A.product "CFuncSigId" { A.field "text" "string", A.unique }

A.product "CFuncSig" {
    A.field "id" "MoonC.CFuncSigId",
    A.field "params" (A.many "MoonC.CTypeId"),
    A.field "result" "MoonC.CTypeId", -- CVoid for no result
    A.unique,
}

A.product "CExternFunc" {
    A.field "moon_name" "string",
    A.field "symbol" "string",
    A.field "sig" "MoonC.CFuncSigId",
    A.field "library" (A.optional "string"),
    A.unique,
}

A.product "CLibrary" {
    A.field "name" "string",
    A.field "link_name" (A.optional "string"),
    A.field "path" (A.optional "string"),
    A.field "symbols" (A.many "string"),
    A.unique,
}
```

### 5.4 C ABI call-plan facts

C ABI planning is separate from C layout. It consumes C type facts and the target
model and produces the exact Cranelift-level signature and call marshalling plan.

```lua
A.sum "CAbiValueClass" {
    A.variant "CAbiDirect" {
        A.field "scalar" "MoonBack.BackScalar",
        A.field "offset" "number",
        A.field "extension" (A.optional "string"), -- "sext" or "uext"
    },

    A.variant "CAbiByValAddress" {
        A.field "size" "number",
        A.field "align" "number",
    },

    A.variant "CAbiSRet" {
        A.field "size" "number",
        A.field "align" "number",
    },
}

A.product "CAbiPlan" {
    A.field "sig" "MoonC.CFuncSigId",
    A.field "target" "MoonBack.BackTargetModel",
    A.field "cranelift_params" (A.many "MoonC.CAbiValueClass"),
    A.field "cranelift_results" (A.many "MoonC.CAbiValueClass"),
    A.field "uses_sret" "boolean",
    A.field "notes" (A.many "string"),
    A.unique,
}

A.product "CAbiProvider" {
    A.field "target_name" "string",
    A.field "triple" "string",
    A.field "supports_aggregate_by_value" "boolean",
    A.field "supports_sret" "boolean",
    A.unique,
}
```

The ABI planner must implement platform ABI rules from the relevant psABI/MSVC
ABI documents. No provider means scalar/pointer C calls only; any by-value
aggregate signature emits `c_abi_unsupported`. A provider may use Cranelift
`ArgumentPurpose::StructReturn` and `ArgumentPurpose::StructArgument(size)` only
where Cranelift 0.131 actually supports the needed target behavior. If no valid
plan exists, cimport emits `c_abi_unsupported` before lowering.

---

## 6. Semantic representation in Moonlift

### 6.1 Scalars and pointers

C scalar, enum, and pointer values lower to existing `BackScalar` values:

| C kind | Moonlift / Back representation |
|---|---|
| `_Bool` | `bool` / `BackBool` |
| signed integer | matching signed `BackScalar` by width |
| unsigned integer | matching unsigned `BackScalar` by width |
| `float`, `double` | `BackF32`, `BackF64` |
| enum | integer scalar with FFI-reported size; signedness derived from enumerator range, or signed if the range fits |
| `T*`, function pointer | `ptr` / `BackPtr` |
| `void*`, `const void*` | `ptr(u8)` / `BackPtr` |
| `size_t` | `index` if width equals pointer width; otherwise exact unsigned scalar |
| `intptr_t`, `uintptr_t` | `index` if width equals pointer width; otherwise exact scalar |

`char` signedness is target-dependent and is recorded by cimport. Users who need
stable signedness should use `signed char`, `unsigned char`, or fixed-width
stdint typedefs.

### 6.2 Aggregates

A C struct, union, or array value is an aggregate object with a layout. It is not
a `BackScalar`.

- Locals of C aggregate type are materialized as stack slots with the exact C
  size and alignment.
- Assignment and parameter preparation copy bytes with `CmdMemcpy`.
- Field access lowers to pointer offset plus load/store using the field's
  recorded type and layout.
- Bitfield access lowers to an integer load of the containing storage unit plus
  mask/shift/sign-extension. Bitfield assignment lowers to read/modify/write.
- Aggregate literals require a complete parsed field list. All non-padding,
  non-bitfield fields must be initialized by name; omitted fields are zeroed
  only in explicitly zero-initialized forms.

### 6.3 Opaque types

Forward declarations such as `typedef struct sqlite3 sqlite3;` create `COpaque`.

Rules:

- `ptr(c("sqlite3"))` is valid.
- `c("sqlite3")` by value is rejected.
- `csizeof("sqlite3")`, `calignof("sqlite3")`, and `coffsetof("sqlite3", ...)`
  are rejected because the object type is incomplete.
- Pointer layout queries use pointer spellings: `csizeof("sqlite3 *")`.

---

## 7. Backend architecture

### 7.1 What must not be added

Do **not** add `BackScalar::CStruct`. Cranelift `Type` is scalar/vector only.
Using a fake scalar for C structs would make signatures, locals, constants, and
calls ambiguous and incorrect.

Do **not** use `MemFlags::readonly()` for volatile. In Cranelift, `readonly`
means the loaded memory does not change for the duration of the function; it is
an optimization promise, the opposite of volatile.

Do **not** add memory-order parameters to Cranelift atomic lowering unless the
Cranelift version in use exposes those parameters. Cranelift 0.131 atomic
instructions are sequentially consistent.

### 7.2 New backend concepts

The backend gains aggregate-aware C ABI commands instead of pretending C structs
are scalars:

```lua
A.product "BackCAbiSigId" { A.field "text" "string", A.unique }

A.sum "BackCArg" {
    A.variant "BackCArgScalar" { A.field "value" "MoonBack.BackValId" },
    A.variant "BackCArgAddress" { A.field "addr" "MoonBack.BackValId" },
}

A.sum "BackCResult" {
    A.variant "BackCResultVoid",
    A.variant "BackCResultScalar" {
        A.field "dst" "MoonBack.BackValId",
        A.field "scalar" "MoonBack.BackScalar",
    },
    A.variant "BackCResultAddress" {
        A.field "addr" "MoonBack.BackValId", -- caller-allocated result storage
    },
}

A.variant "CmdDeclareCExtern" {
    A.field "func" "MoonBack.BackExternId",
    A.field "symbol" "string",
    A.field "abi_sig" "MoonBack.BackCAbiSigId",
}

A.variant "CmdCallC" {
    A.field "result" "MoonBack.BackCResult",
    A.field "func" "MoonBack.BackExternId",
    A.field "abi_sig" "MoonBack.BackCAbiSigId",
    A.field "args" (A.many "MoonBack.BackCArg"),
}
```

Scalar-only C functions may be lowered to existing `CmdCreateSig`,
`CmdDeclareExtern`, and `CmdCall`; aggregate-involving functions must use
`CmdDeclareCExtern`/`CmdCallC` so the marshalling is explicit.

### 7.3 Cranelift lowering of C calls

For a `CmdCallC`, the Rust backend:

1. Looks up the already-computed `CAbiPlan` by `BackCAbiSigId`.
2. Builds a Cranelift `Signature` from the plan's scalar and special ABI params.
3. For scalar arguments, passes the existing Cranelift value.
4. For aggregate-by-value arguments, copies bytes from the aggregate address into
   the ABI-prescribed outgoing representation. If the plan uses
   `ArgumentPurpose::StructArgument(size)`, the Cranelift call operand is a
   pointer to the source bytes, matching Cranelift's documented semantics.
5. For sret results, allocates or receives caller-provided result storage, passes
   the hidden pointer, and exposes the aggregate result as that address.
6. For direct aggregate returns decomposed into scalar parts, stores returned
   parts into the caller-provided result storage at the offsets recorded in the
   plan.

Validation rejects:

- Missing `CAbiPlan`.
- Aggregate arguments passed as scalar values or scalar args passed as addresses.
- Incomplete aggregate types by value.
- Alignment lower than the C type's ABI alignment.
- Use of `StructArgument`/`StructReturn` on a target where Cranelift rejects or
  mis-models the required ABI case.

### 7.4 C ABI export/callback functions

When a Moonlift `export func` has a public C-callable signature, the same
`CAbiPlan` mechanism is used in reverse:

1. The Cranelift function signature is built from the C ABI plan.
2. Function prologue code materializes aggregate parameters into Moonlift stack
   storage from direct return/parameter parts, byval pointers, or ABI stack
   areas as specified by the plan.
3. The Moonlift function body operates on normal Moonlift scalar values and
   aggregate storage.
4. Return lowering writes aggregate results to sret storage or decomposes them
   into direct scalar return parts according to the plan.

If the source function is never exported and its address is never taken as a C
function pointer, it may use Moonlift's internal lowering. Once exported for C or
used as `&func`, the C ABI boundary is mandatory and validated.

---

## 8. Shared library loading and linking

### 8.1 JIT mode

For `import c from "name"`:

1. `ffi.load(name)` is called during cimport.
2. Every imported function symbol is resolved from the returned library
   namespace.
3. The symbol pointer is registered with the JIT using the exact C symbol name.
4. The library namespace object is retained by the compiled artifact/session so
   function pointers remain valid.

For `import c` without `from`, symbols are resolved from the existing process
namespace/JIT symbol table. Missing symbols are diagnostics at JIT compile time.

### 8.2 Object/shared-object mode

`ffi.load` is not used for final linking. Instead cimport records `CLibrary` and
link facts:

- `from "m"` becomes a link-library request such as `-lm` on ELF platforms.
- Absolute or relative paths become explicit link inputs.
- Imported functions remain undefined extern symbols in the object file and are
  resolved by the final linker/loader.

A source module that uses `from` must therefore carry both JIT symbol facts and
object link facts.

---

## 9. Diagnostics

Required diagnostics include:

| Diagnostic | Meaning |
|---|---|
| `c_cross_target_unsupported` | C interop requested for a target whose C ABI differs from the running LuaJIT host ABI. |
| `cdef_parse_error` | LuaJIT FFI rejected the cdef string. |
| `c_import_unsupported_declaration` | Moonlift declaration parser cannot produce facts for a top-level declaration. |
| `c_type_redefinition` | A C type name is redefined incompatibly with an existing FFI/global declaration. |
| `c_function_redefinition` | A C function name is redefined incompatibly with an existing FFI/global declaration. |
| `c_type_not_found` | `c("T")` or a layout query references neither a built-in C type nor an imported type. |
| `c_type_incomplete_by_value` | Incomplete C object type used by value. |
| `c_layout_requires_complete_type` | `csizeof`, `calignof`, or `coffsetof` used on an incomplete object. |
| `c_offsetof_non_aggregate` | `coffsetof` used on a non-struct/non-union. |
| `c_offsetof_unknown_field` | Field name is not present in parsed C layout facts. |
| `c_varargs_unsupported` | Function prototype uses `...`. |
| `c_volatile_unsupported` | Imported type/function requires C volatile semantics. |
| `c_abi_unsupported` | Target ABI planner cannot lower a requested C signature. |
| `c_symbol_not_found` | JIT mode could not resolve an imported function symbol. |
| `c_library_not_found` | JIT mode could not load the requested library. |
| `c_callback_signature_mismatch` | `&export_func` does not match expected C function pointer type. |

Diagnostics are ASDL values with spans pointing at the `import c`, `c("...")`,
or call site that caused the issue.

---

## 10. Examples

### 10.1 Opaque SQLite handle

```moonlift
import c from "sqlite3" [[
    typedef struct sqlite3 sqlite3;
    int sqlite3_open(const char* filename, sqlite3** ppDb);
    int sqlite3_close(sqlite3* db);
    const char* sqlite3_errmsg(sqlite3* db);
]]

const SQLITE_OK: i32 = 0

export func open_then_close(path: ptr(u8)) -> i32
    var db: ptr(c("sqlite3")) = as(ptr(c("sqlite3")), nil)
    let rc: i32 = sqlite3_open(path, &db)
    if rc ~= SQLITE_OK then return rc end
    return sqlite3_close(db)
end
```

### 10.2 Struct layout and by-value call

```moonlift
import c [[
    typedef struct { int x; int y; } point_t;
    point_t point_add(point_t a, point_t b);
]]

const POINT_SIZE: index = csizeof("point_t")
const POINT_Y: index = coffsetof("point_t", "y")

func add_points(a: c("point_t"), b: c("point_t")) -> c("point_t")
    return point_add(a, b)
end
```

This compiles only when the target has a valid `CAbiPlan` for `point_t
(point_t, point_t)`. Otherwise it fails with `c_abi_unsupported` rather than
emitting a wrong call.

### 10.3 Callback

```moonlift
import c [[
    typedef int (*cmp_t)(const void*, const void*);
    void qsort(void* base, size_t nmemb, size_t size, cmp_t compar);
]]

export func cmp_i32(a: ptr(u8), b: ptr(u8)) -> i32
    let av: i32 = *(as(ptr(i32), a))
    let bv: i32 = *(as(ptr(i32), b))
    if av < bv then return -1 end
    if av > bv then return 1 end
    return 0
end

export func sort_i32(data: ptr(i32), n: index)
    qsort(as(ptr(u8), data), n, csizeof("int"), &cmp_i32)
end
```

---

## 11. Implementation phases

### Phase 1 — curated cdefs, scalar/pointer functions, layout constants

- Parser: `import c`, `c("T")`, `csizeof`, `coffsetof`, `calignof`.
- Add C type/layout/function facts.
- Implement `lib/c_decl_parse.lua` for typedefs, structs/unions/enums, pointers,
  arrays, and non-vararg prototypes.
- Register cdefs through LuaJIT FFI and query layout.
- Lower scalar/pointer imported functions through existing extern commands.
- Tests: libc `malloc/free`, libm `cos/sqrt`, opaque handles, layout constants.

### Phase 2 — field access, aggregate storage, and bitfields

- Materialize C aggregates as stack/data storage.
- Field load/store through recorded offsets.
- Aggregate literals and copies.
- Bitfield read/modify/write lowering.
- Tests: structs, unions, arrays in structs, packed structs, bitfields.

### Phase 3 — function pointers and callbacks

- `cfunc` type syntax and `&export_func` expression.
- C function pointer typedef resolution.
- Direct and indirect C function pointer calls.
- Callback lifetime tests in JIT and object/shared mode.

### Phase 4 — shared library facts

- JIT `ffi.load` resolution with retained handles.
- Object/shared-object link facts.
- Diagnostics for missing libraries and symbols.

### Phase 5 — aggregate by-value C ABI

- Implement `CAbiPlan` for each supported target family.
- Add `CmdDeclareCExtern` and `CmdCallC`.
- Use Cranelift special ABI params only where supported and tested.
- ABI conformance suite generated against a C compiler for each target.

---

## 12. Test requirements

- Every cimport fact has golden ASDL tests.
- Every layout query is checked against LuaJIT FFI and, for conformance suites,
  against a tiny C program compiled by the system C compiler.
- Aggregate by-value tests must cover sizes 1, 2, 3, 4, 5-8, 9-16, 17-32,
  mixed int/float fields, nested structs, unions, arrays, packed structs, and
  sret returns.
- Callback tests must verify direct callback invocation from C and indirect calls
  through a stored C function pointer.
- JIT and object/shared-object modes must both be tested for imported libraries.
- Unsupported cases must have explicit diagnostics tests: varargs, volatile,
  unknown symbols, incomplete by-value types, and unsupported target ABI plans.

---

## 13. Backwards compatibility

- Existing Moonlift code remains valid.
- Existing scalar/pointer `extern func` declarations continue to lower exactly
  as before.
- `import c` is additive; it does not deprecate manual extern declarations.
- New reserved words: `c`, `from`, `csizeof`, `coffsetof`, `calignof`, and
  `cfunc`. `import` is already reserved in the current language reference.

---

## 14. Final decisions

- Auto-generate callable Moonlift extern bindings for every non-vararg function
  prototype in an `import c` block.
- Do not auto-import C enum constants in this design; users may define Moonlift
  `const` values or generate them from Lua.
- Do not support varargs.
- Do not support C volatile in this design.
- Do not expose memory-order-specific atomics in this C interop design.
- Do not add `BackScalar::CStruct`.
- Do not claim that LuaJIT FFI can enumerate declarations; Moonlift owns a
  declaration parser but delegates all layout computation to FFI.
