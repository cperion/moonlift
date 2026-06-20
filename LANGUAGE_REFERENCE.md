# Moonlift Complete Language Reference

Status: canonical language reference for the current Moonlift design.

This file is intentionally broad. It describes Moonlift as one integrated
hosted language:

```text
Lua staging / metaprogramming
  + hosted declarations
  + monomorphic Moonlift object code
  + typed regions / emits / jumps
  + explicit host exposure facts
```

Moonlift is not Lua with strings, and it is not a generic source language.
Lua is where genericity, templates, code generation, specialization, and
dispatch-table construction live. Moonlift object code is the
generated/authorable monomorphic language whose semantics are explicit in
ASDL.

---

## Table of Contents

1.  [Language layers](#1-language-layers)
2.  [Non-negotiable language rules](#2-non-negotiable-language-rules)
3.  [Files and execution surfaces](#3-files-and-execution-surfaces)
4.  [Lexical rules](#4-lexical-rules)
5.  [Type system](#5-type-system)
6.  [Modules and items](#6-modules-and-items)
7.  [Hosted declarations](#7-hosted-declarations)
8.  [Statements](#8-statements)
9.  [Expressions](#9-expressions)
10. [Control regions](#10-control-regions)
11. [Region fragments and continuation protocols](#11-region-fragments-and-continuation-protocols)
12. [Expression fragments](#12-expression-fragments)
13. [Contracts](#13-contracts)
14. [Lua splicing and antiquote](#14-lua-splicing-and-antiquote)
15. [Quoting and table builder API reference](#15-lua-builder-api-reference)
16. [Metaprogramming and composition guide](#16-metaprogramming-and-composition-guide)
17. [View and host ABI semantics](#17-view-and-host-abi-semantics)
18. [Vectorization and facts](#18-vectorization-and-facts)
19. [Error and diagnostic model](#19-error-and-diagnostic-model)
20. [Intrinsics](#20-intrinsics)
21. [Memory Management Convention](#21-memory-management-convention)
22. [Memory operations](#22-memory-operations)
23. [Complete examples](#23-complete-examples)
24. [Implementation/layer map](#24-implementationlayer-map)
25. [Summary doctrine](#25-summary-doctrine)

---

## 1. Language layers

Moonlift has three user-visible layers.

### 1.1 Lua host/staging layer

The outer layer of a `.mlua` file is ordinary LuaJIT Lua.

Use Lua for:

- imports and module assembly
- loops that generate code
- type-indexed specialization
- function/region/expression fragment templates
- constants that are spliced into object code
- choosing which Moonlift declarations are produced
- computing sizes, offsets, and layout constants
- constructing dispatch tables and jump maps
- declaring memory worlds, scopes, arenas, stores, resources, and borrow rituals
- emitting multiple monomorphic variants from a single parameterized factory

Lua genericity is real genericity. Moonlift source genericity does not exist.
When you want a function parameterized by type, you write a Lua function that
returns a Moonlift function specialized to that type.

### 1.2 Hosted declaration layer

Inside `.mlua`, Moonlift recognizes these hosted islands:

- `struct ... end`
- `union ... end`
- `handle ... end`
- `extern ... end`
- `func ... end`
- `region ... entry ... end ... end`
- `expr ...: T ... end`

These islands construct ASDL values and host facts. They are not source strings
at runtime — the parser builds typed ASDL nodes directly.

### 1.3 Moonlift object-code layer

Moonlift object code is the compiled low-level language:

```text
typed values          -- scalars, pointers, views
typed memory views    -- data + len + stride descriptors
functions             -- typed signatures, parameter bindings
regions               -- typed control fragments with continuation protocols
blocks                -- typed continuation / state points with named params
switches              -- explicit integer/boolean dispatch
emits                 -- typed region or expression fragment use
jumps                 -- typed state transitions with named arguments
yields                -- exit current control region with optional value
returns               -- exit enclosing function with optional value
```

The central control model:

```text
region  = typed control fragment, machine boundary
cont    = typed output protocol (continuation signature)
block   = typed continuation / state point with named parameters
jump    = typed state transition with named arguments
emit    = typed region or expression fragment splice
switch  = explicit integer dispatch with typed branch targets
```

This is the low-level PVM idea. No extra micro-framework is required. Every
transition is explicit and typed.

---

## 2. Non-negotiable language rules

### 2.1 No Moonlift source generics

Moonlift source has no type parameters and no source-level generic instantiation.

❌ Wrong language direction:

```text
id<T>(x: T)
foo<i32>(x)
```

✅ Correct pattern — Lua is the metaprogramming language:

```lua
local function make_id(name, T)
    return expr @{name}(x: @{T}): @{T}
        x
    end
end

local id_i32 = make_id("id_for_i32", moon.i32)
```

Moonlift receives only the monomorphic result with all types resolved.

### 2.2 No angle-bracket type argument syntax

Moonlift source does not use angle brackets for type arguments or casts.
This applies everywhere: declarations, calls, and conversions.

The normal source-level conversion form is:

```moonlift
as(T, value)
```

Examples:

```moonlift
let x: i32 = as(i32, byte_value)      -- unsigned byte → signed 32-bit
let y: f64 = as(f64, int_value)        -- integer → float
let z: u8 = as(u8, wide_value)         -- truncation
let p: f32 = as(f32, double_value)     -- f64 → f32 demotion
```

`as(T, value)` is a semantic conversion request. It is not a generic call and
not an explicit machine operation. The compiler chooses the concrete machine
operation (extend, truncate, float conversion, or identity) from the source and
target scalar types.

For representation-level code that must reinterpret bits without numeric
conversion, use explicit same-width `bitcast(T, value)`:

```moonlift
let n: f64 = bitcast(f64, bits)
let bits2: u64 = bitcast(u64, n)
```

All combinations of supported scalar `as` conversions are defined. Invalid
combinations (e.g. `as(ptr(u8), f64_value)`) are rejected at typecheck time.

### 2.3 Explicit ASDL meaning

If a distinction matters to compilation, it must be represented as ASDL or as a
Lua-hosted value that constructs ASDL. Meaning must not hide in:

- raw strings or string concatenation
- callback closures or function dispatch tables
- mutable side tables or global state
- ad hoc runtime tags or conditional branches
- backend-only IR transformations

Every semantic fact — types, layouts, contracts, control edges, vector shapes,
diagnostics — is an explicit ASDL value produced by a named PVM phase.

### 2.4 Monomorphic object code

Every Moonlift function, region, block, continuation, and value has concrete
types when it reaches typecheck/lowering. There is no runtime type dispatch, no
type-erased generics, and no polymorphic inline caches. Type information is
fully resolved before backend command generation.

---

## 3. Files and execution surfaces

### 3.1 `.mlua` files

A `.mlua` file is LuaJIT Lua with Moonlift value islands embedded as Lua
expressions. Each island produces a host value (function, region fragment,
expr fragment, struct type, or union type). The file is loaded through the
unified Moonlift module:

```lua
local moon = require("moonlift")
local chunk = moon.loadfile("file.mlua")
local result = chunk()

-- Or directly:
local result = moon.dofile("file.mlua")
```

From the command line:

```bash
moonlift file.mlua                        # hosted Lua pipeline (default)
moonlift run --call main file.mlua         # hosted, call specific function
```

Inside `.mlua` files, the `moon` table provides `moon.require` and `moon.emit_object`.

The `.mlua` file returns any Lua value — typically a function or a table of
functions.

Example:

```lua
-- file.mlua
local add = func(a: i32, b: i32): i32
    return a + b
end

return add
```

### 3.2 Parsing types from strings

Individual type expressions can be parsed from strings:

```lua
local Parse = require("moonlift.parse")
local T = pvm.context()
local P = Parse.Define(T)
local result = P.parse_type("ptr(i32)")
-- result.value is a MoonType.TPtr(elem = MoonType.TScalar(ScalarI32))
```

### 3.3 Unified module API

The primary entry point is `require("moonlift")`, which provides the full
compilation pipeline alongside the builder API:

**Hosted-Lua pipeline:**

```lua
local moon = require("moonlift")
local chunk = moon.loadstring(src, name, opts)    -- compile and return callable
local chunk = moon.loadfile(path, opts)            -- compile and return callable from file
local result = moon.dofile(path, opts, ...)        -- load and execute
local result = moon.eval(src, ...)                 -- loadstring + immediate call
```

**Object emission:**

```lua
local obj_bytes = moon.emit_object(src, path, name)   -- emit .o bytes
local so_bytes  = moon.emit_shared(src, path, name)   -- emit .so/.dylib bytes
```

**Inside `.mlua` files**, the `moon` table provides `moon.require` and `moon.emit_object`.

**Builder API** — the unified module also exposes the quoting and table builder surface:

```lua
local M = moon.bundle("Demo")
M:export_func("add", { ... }, moon.i32, function(fn) ... end)
```

Backward-compatible alias: `require("moonlift.mlua_run")` still works, but the
unified `require("moonlift")` module is preferred.

### 3.4 Low-level ASDL construction

Two additional APIs produce the same ASDL values consumed by the same
PVM phases. Neither is a separate compiler IR.

**Low-level node constructor API:**

```lua
local ast = require("moonlift.ast")
```

`moonlift.ast` returns plain `MoonCore` / `MoonType` / `MoonTree` ASDL values and
carries LuaLS documentation for each exposed node constructor and table field.
This is the field-by-field hosted form of the language reference.

**High-level hosted value API:**

```lua
local moon = require("moonlift.host")
```

The `moonlift.host` API provides ergonomic builders with automatic name
generation, session management, and JIT compilation. The unified module
re-exports this surface, so `require("moonlift")` provides the same builder
methods.

Both APIs construct identical ASDL values. Choose based on preference and task.

### 3.5 Command-line tools

| Command | Purpose |
|---|---|
| `moonlift file.mlua` | Hosted-Lua pipeline (default) |
| `moonlift run --call main file.mlua` | Hosted, call specific function |
| `luajit lsp.lua` | Start the Moonlift LSP server |

For programmatic compilation and execution from Lua, use the unified module
API (§3.3) instead of invoking CLI tools.

---

## 4. Lexical rules

### 4.1 Whitespace

Whitespace separates tokens. Newlines separate statements in the newline/end
form. Hosted Moonlift islands are keyword/end-delimited; braces are not accepted
as alternate declaration or function delimiters anywhere in object-language
source.

### 4.2 Comments

Line comments (standard Lua):

```lua
-- comment until end of line
```

Lua long comments (`--[[ ... ]]`) are skipped by the host island scanner and
can appear anywhere in `.mlua` files, including inside hosted islands.

### 4.3 Identifiers

```text
ident ::= [A-Za-z_][A-Za-z0-9_]*
path  ::= ident { "." ident }
```

Identifiers are case-sensitive. Paths are dot-separated sequences used for
module-qualified names (e.g. `moon.i32` in the builder, `MoonCore.ScalarI32`
in ASDL type paths). In object-language source, dotted names may represent
module paths or field access depending on context — resolution is semantic.

### 4.4 Literals

```text
int_lit   ::= decimal_lit | hex_lit
decimal_lit ::= [0-9]+ | [0-9]+ "_" [0-9]+
hex_lit    ::= "0x" [0-9a-fA-F]+
float_lit  ::= [0-9]+ "." [0-9]+ ( [eE] [+-]? [0-9]+ )?
string_lit ::= '"' { c_string_char | c_escape } '"'
bool_lit   ::= "true" | "false"
nil_lit    ::= "nil"
```

Numeric spellings are preserved as raw strings in the source ASDL and
interpreted later by typed phases. String literals are C-style byte strings with
escapes such as `\\n`, `\\r`, `\\t`, `\\\\`, `\\\"`, octal, and `\\xHH`; they type as
NUL-terminated static `ptr(u8)` data. Underscore separators in decimal integers
are accepted for readability (e.g. `1_000_000`).

Integer overflow at constant time follows the target scalar's semantics — a
`u8` literal of `256` is rejected; a `u8` literal of `255` is accepted.
Signed overflow in constant evaluation produces a diagnostic, not silent
wrapping.

Float literals support decimal notation with optional exponent (`1.5`, `2.0`,
`3.14e-2`). Hex float literals are not supported.

### 4.5 Reserved words

Complete list of reserved words in Moonlift object-language source:

**Declaration / hosted-island keywords:**
```text
func  struct  union  handle  extern  region  expr
```

**Pointer and access modifiers:**
```text
noalias  readonly  writeonly  noescape  invalidate  preserve
lease    requires
bounds   window_bounds  disjoint  same_len
```

**Statement keywords:**
```text
let  var  if  then  else  elseif  switch  case  default  do  end
block  entry  jump  yield  return  emit  call
```

**Expression keywords:**
```text
true  false  nil  and  or  not  as  len
```

**Scalar type keywords (reserved in type position):**
```text
void  bool
i8  i16  i32  i64
u8  u16  u32  u64
f32  f64
index
```

`select(...)` is a recognized special call form, not a reserved word.

Intrinsic names such as `popcount`, `sqrt`, `trap`, and `assume` are ordinary
callee names at the source parser level; intrinsic lowering is not part of the
current source parser.


**Intentionally NOT reserved:**

These names are intentionally NOT reserved in Moonlift object-language source
and may be used freely as identifiers:

```text
for  while  loop  next  break  continue  over  range  zip  zip_eq
fn  closure  ptr  slice  repr  packed  domain  target
```

Sugar keywords (if added later) will be lowering-only and will not add new
source-level semantics.

---

## 5. Type system

### 5.1 Scalar types

```text
void        -- zero-size, only valid as function return
bool        -- 1-byte boolean, values 0 or 1
i8  i16  i32  i64    -- signed integers
u8  u16  u32  u64    -- unsigned integers
f32  f64              -- IEEE 754 floats
index                 -- canonical machine-sized indexing integer (ptr-sized)
```

Scalar semantics:

- Arithmetic on signed and unsigned integers is wrapping by default. Overflow
  semantics can be refined by contracts and vectorization facts.
- Float arithmetic uses strict IEEE 754 semantics unless `fast-math` is
  selected by a target feature fact.
- `bool` is stored as `i8` at the machine level (0 = false, 1 = true).
  Relational/comparison operations produce canonical 0/1 bool values.
- `index` is semantically a pointer-sized unsigned integer. On 64-bit targets
  it is `u64`; on 32-bit targets it is `u32`.
- `void` is zero-size and cannot be used as a parameter type, local type,
  struct field type, or expression type. It exists only as a function return
  type to indicate no return value.

### 5.2 Pointer types

```moonlift
ptr(T)
```

Pointer syntax:

```moonlift
ptr(u8)       -- pointer to one byte
ptr(User)     -- pointer to one User struct
ptr(i32)      -- pointer to one i32
```

`ptr(T)` means a pointer to exactly one `T` value. There is no `ptr(void)`.



Pointer operations:

| Operation | Syntax | Semantics |
|---|---|---|
| Load | `*ptr` | Read a `T` from memory |
| Store | `*ptr = value` | Write a `T` to memory |
| Address-of | `&place` | Take address of a place |
| Pointer add | `ptr + offset` | Add element offset to pointer |

Plain pointer types do not carry mutability, nullability, ownership, or lifetime
information by themselves. Access and lifetime facts are represented explicitly
around the base type with access-qualified types and leases, or as `requires`
contracts at ABI boundaries.

### 5.3 View types

```moonlift
view(T)
```

A view is a typed memory sequence descriptor, not a single record. Views are
the Moonlift equivalent of a slice: a pointer, a length, and a stride.

**Canonical view ABI (C):**

```c
typedef struct MoonView_T {
    T* data;         // pointer to first element
    intptr_t len;    // number of accessible elements
    intptr_t stride; // stride in elements (1 = contiguous)
} MoonView_T;
```

All three fields are mandatory in the internal ABI. Contiguous views use
`stride = 1`. Strided views use `stride > 1`.

**View construction in source:**

```moonlift
view(data_ptr, count)              -- contiguous view, stride = 1
view(data_ptr, count, stride)      -- strided view
```

**View indexing:**

```text
element_address(i) = data + i * stride * sizeof(T)
```

`i` is bounds-checked against `len`. Out-of-bounds access is a trap (when
checks are enabled) or undefined behavior (when checks are elided by facts).

**View properties:**

| Expression | Returns | Description |
|---|---|---|
| `len(v)` | `index` | Number of elements in the view |
| `v[i]` | `T` | Element at index `i` |

### 5.4 Access-qualified and lease types

Access qualifiers are part of the source type surface and survive parsing as
explicit ASDL:

```text
TAccess(TypeAccessReadonly, TView(TScalar(u8)))
```

Source syntax:

```moonlift
readonly view(u8)
writeonly ptr(u8)
noalias ptr(i32)
noescape ptr(Node)
invalidate ptr(Session)
preserve ptr(Store)
lease ptr(T)
lease(owner) view(u8)
```

The access words are:

| Qualifier | Meaning |
|---|---|
| `noalias` | This access path does not alias another relevant access path |
| `readonly` | Memory reachable through the access path is only read |
| `writeonly` | Memory reachable through the access path is only written |
| `noescape` | The access path must not be retained beyond the current dynamic extent |
| `invalidate` | The operation may move, free, compact, clear, or reuse reachable storage |
| `preserve` | The operation may inspect/update metadata but preserves live leases |

`lease T` is temporary access. A lease may appear in function, block, and
continuation parameters, but it may not become durable data: no struct fields,
statics, ordinary returns, or region-call result payloads. Use `emit` when a
region carries leased access in a continuation payload.

Parameter modifiers are parsed as access wrappers on the parameter type. For
compatibility with the local borrow checker, `noescape p: ptr(T)` is represented
as `TAccess(TypeAccessNoEscape, TLease(TPtr(T)))`: the `noescape` source fact is
preserved and the existing lease discipline remains active.

### 5.5 Named types

Named types refer to declared structs, tagged unions, or qualified type paths:

```moonlift
User              -- locally declared struct
Pairs             -- locally declared struct
MoonCore.Scalar   -- qualified named type path
```

Named types are resolved during typechecking against the module's type
declarations and imports. Unresolved names produce type errors.

### 5.6 Struct types

Declared via `struct ... end` islands in `.mlua` files:

```moonlift
struct Vec3
    x: f32
    y: f32
    z: f32
end
```

Or inline:

```moonlift
struct Vec3 x: f32, y: f32, z: f32 end
```

Fields are product members: they coexist, so fields are comma-separated just
like function parameters. Fields are laid out in declaration order with natural
alignment.

### 5.7 Tagged union types

```moonlift
union Result ok(i32) | err(i32) end

-- Protocol-style variants use named payload fields.
union Scanner
    hit(pos: i32)
  | miss(pos: i32)
end
```

Tagged unions carry an implicit discriminant tag followed by the variant
payload. The tag is an integer starting from 0 in declaration order. Useful
for explicit phase/result dispatch.

Union variants are sum alternatives, so they are separated by `|`. A bare variant name
means no payload. When a tagged union is used as a region result protocol
(`region r(...): Scanner`), its variants become exits and named variant fields
become continuation parameters. Protocol variants must use named fields.

### 5.8 Array types

```moonlift
[T; N]       -- fixed-length array of T with N elements
```

Array types carry a compile-time constant length and an element type. They are
value types — the array data is stored inline (not behind a pointer). Arrays are
used with array literals and for struct fields that need inline storage.

In the type system, arrays are represented as `TArray(count, elem)`. The count
can be a constant integer (`ArrayLenConst`) or a computed value (`ArrayLenExpr`).

**Comparison to views:** Arrays are fixed-size value types; views are
runtime-sized descriptors (pointer + length + stride). Use arrays when the size
is known at compile time and you want inline storage. Use views for
runtime-sized or dynamically allocated sequences.

### 5.9 Function and closure types (source syntax)

In type position:

```text
func(i32, i32): i32           -- function pointer type
closure(i32): i32             -- closure type (function + context)
```

Function pointer values are scalar pointer-sized values. They can be passed as
parameters, returned, produced with `&some_func`/function-address lowering, cast
from `ptr(u8)`, and called indirectly:

```moonlift
func call_fp(fp: func(i32): i32, x: i32): i32
    return fp(x)
end

func call_raw(raw: ptr(u8), x: i32): i32
    let fp: func(i32): i32 = as(func(i32): i32, raw)
    return fp(x)
end
```

The builder API uses `moon.func_type(params, result)` and `moon.closure_type(params, result)`.

### 5.10 Source-level genericity

There is none. Use Lua to generate specialized concrete types/functions/fragments.

---

## 6. Functions

```moonlift
func [name] ( param_list? ) [: type]
    requires_clause*
    stmt*
end
```

Rules:

- Function bodies are always `end`-delimited. Brace-delimited function bodies
  are rejected.
- Functions are standalone compiled values. There is no module-level visibility system.
  Symbol visibility is controlled by the compilation/linker target.
- The name is optional. When the function is assigned (`local f = func(...)`
  or `M.f = func(...)`), the name is inferred from the assignment target.
  When the name is omitted without an assignment (e.g. `return func(...)`),
  an auto-generated internal name is used.
- Omitting the result type means `void` return.
- The parameter list may be empty: `func name(): i32 ... end` or `func name()
  ... end` for void.
- Function parameters are immutable bindings. They cannot be assigned to.

Examples:

```moonlift
func add(a: i32, b: i32): i32
    return a + b
end

-- Inferred name from assignment
local add = func(a: i32, b: i32): i32
    return a + b
end

-- Anonymous return
return func(a: i32, b: i32): i32
    return a + b
end

func zero_buffer(dst: ptr(u8), n: index)
    block loop(i: index = 0)
        if i >= n then return end
        dst[i] = 0
        jump loop(i = i + 1)
    end
end
```

### 6.3 Parameters

```text
param      ::= modifier* name ":" type
modifier   ::= "noalias" | "readonly" | "writeonly"
             | "noescape" | "invalidate" | "preserve"
```

Parameter modifiers are both source contracts and explicit type facts. The parser
wraps the parameter type in `TAccess(...)`; the compatibility contract path still
feeds alias, vector safety, and local invalidation checks.

| Modifier | Meaning |
|---|---|
| `noalias` | This pointer does not alias any other pointer parameter |
| `readonly` | Memory reachable through this pointer is only read, never written |
| `writeonly` | Memory reachable through this pointer is only written, never read |
| `noescape` | Access may be used by the callee but not retained |
| `invalidate` | Callee may invalidate storage reachable through this parameter |
| `preserve` | Callee preserves live leases associated with this parameter |

Example:

```moonlift
func sum(readonly noalias xs: ptr(i32), n: i32): i32
    block loop(i: index = 0, acc: i32 = 0)
        if i >= n then return acc end
        jump loop(i = i + 1, acc = acc + xs[i])
    end
end
```

Modifiers can be combined. `noalias readonly xs: ptr(T)` means the pointer is
both non-aliasing and the memory it points to is only read. Combined modifiers
produce nested explicit access nodes, so the source facts remain visible to later
phases.





### 6.4 Type declarations

In `.mlua` files, use `struct`, `union`, and `handle` islands. The name is optional when
assigned — inferred from the assignment target:

```moonlift
struct Pair left: i32, right: i32 end
local Pair = struct left: i32, right: i32 end   -- same, name inferred

union Result ok(i32) | err(string) | none end
local Result = union ok(i32) | err(string) | none end  -- same, name inferred

handle ComponentRef : u32 invalid 0
    domain ComponentStore
    target Component
end

-- Anonymous (auto-named)
return struct x: f32, y: f32 end
return union ok(i32) | err(i32) end
```



---

## 7. Hosted declarations

The `.mlua` source parser recognizes these hosted declaration islands.
Names in brackets are optional — when omitted, the name is inferred from the
Lua assignment target or auto-generated.

Syntax follows the product/sum split: product lists use commas (`struct` fields,
function parameters, region runtime parameters, variant payload fields); sum
alternatives use `|` (`union` variants and region exits). Newlines are formatting,
not separators. Trailing separators are accepted.

A named product type may appear in product-list position and expands to its
fields. A named union type may appear in region protocol position and expands to
its variants as exits:

```moonlift
struct Point x: i32, y: i32 end
union ParseExit ok(value: i32) | err(code: i32) end

func length2(Point): i32
    return x * x + y * y
end

region parse_point(p: ptr(u8), n: index; ParseExit)
```

- `struct [Name] field: T, field: T end` (product fields use commas)
- `union [Name] variant(...) | variant(...) end` (sum alternatives use `|`)
- `handle [Name] : repr [invalid int] [domain Type] [target Type] end`
- `extern [name](params...) [: T] [as "symbol"] end`
- `func [name](params...) [: T] ... end`
- `region [name](params; exit(payload...) | empty_exit) ... end`
- `expr [name](params): T expr end`

### 7.1 Name inference and anonymous forms

In `.mlua`, assignment is the preferred way to name declarations. The source
name can be omitted and is inferred from the Lua assignment target; this avoids
repeating the name on both sides:

```lua
local add = func(a: i32, b: i32): i32                 -- name = "add"
    return a + b
end

local scan = region(p: ptr(u8), n: i32;
                    hit(pos: i32))
entry loop(i: i32 = 0)
    if i >= n then jump hit(pos = -1) end
    jump loop(i = i + 1)
end
end                                                       -- name = "scan"

local T = struct                                        -- name = "T"
    x: f32,
    y: f32,
    z: f32,
end

local U = union                                         -- name = "U"
    ok(value: i32)
  | err(code: i32)
  | none
end
```

The explicit forms still work (`struct T ... end`, `region scan(...) ... end`),
but are usually redundant when the declaration is assigned.

Name inference also works in other positions:

```lua
-- Table field assignment
M.add = func(a: i32, b: i32): i32                      -- name = "add"
    return a + b
end

-- Return anonymous function (generates a stable internal name)
return func(a: i32, b: i32): i32                       -- auto-named
    return a + b
end

-- Anonymous struct / union (type context determines usage)
return struct x: f32, y: f32 end
return union ok(i32) | err(i32) end
```

Name inference handles identifiers ending in digits (e.g. `load_u64`,
`parse_i32`) correctly — the trailing digits are part of the identifier, not
treated as an index suffix.

The same inference rules apply to `region`, `expr`, and `extern` anonymous forms.

### 7.2 Type and fragment reference resolution

In `.mlua` files, every type or fragment reference in a hosted island is a
Lua expression evaluated at parse time.  Declarations register themselves
under their full Lua expression path (e.g. `T.RingBuf`) when assigned.
Later islands resolve references through this registry — no separate
Moonlift type namespace.

```lua
-- These declarations register "T.RingBuf", "T.Handle", etc. in the registry.
T.RingBuf = struct
    data: ptr(u8),
    head: index,
end

T.MyHandle = handle : u32 invalid 0 end

-- Later islands resolve T.RingBuf and T.MyHandle as Lua expressions or dotted paths.
T.Conn = struct
    rx: T.RingBuf,         -- resolves via the registry
    handle: T.MyHandle,    -- resolves via the registry
end
```

This applies to fragment references in `emit` and `call` as well:

```lua
R.scan = region scan(p: ptr(u8), n: i32; hit(pos: i32) | miss)
    ...
end

func find(p: ptr(u8), n: i32): i32
    return region: i32
    entry start()
        emit R.scan(p, n; hit = found, miss = not_found)
    end
    ...
    end
end
```

Rules:

- Declarations must **precede** their use.  `T.RingBuf` cannot be referenced
  in a struct field unless it was declared in an earlier island in the same
  file.
- Any Lua expression works — `T.types.int32`, `get_type()`, `module[key]`.
- `@{...}` is still required for **expression** positions (where bare names
  would conflict with Moonlift bindings) and for **spread** positions.
- The name inferred from `T.RingBuf = struct` is `RingBuf` — the last segment
  of the Lua assignment path.  The full expression path `T.RingBuf` is also
  registered automatically.

Name inference handles identifiers ending in digits (e.g. `load_u64`,

Extern declarations create typed imported function items. The source name is the
Moonlift callee name; the optional `as "symbol"` names the dynamic symbol to
resolve through the JIT/linker:

```lua
local strlen = extern strlen(s: ptr(u8)): index end
local host_add = extern add7(x: i32): i32 as "host_add7" end
```

Host-facing APIs such as exposure policies, proxy generation, module assembly,
and native method registration are provided through the Lua builder/host APIs,
not through additional Moonlift source keywords.

---

## 8. Statements

### 8.1 Statement list

```text
stmt ::= let_stmt
       | var_stmt
       | set_stmt
       | if_stmt
       | switch_stmt
       | emit_stmt
       | jump_stmt
       | yield_stmt
       | return_stmt
       | control_stmt
       | single_block_stmt
       | expr_stmt
```

Statements appear inside function bodies, block bodies, and `if`/`else`/`case`
branches. All statements in a block or branch are executed sequentially.
There is no implicit statement separator other than newlines.

### 8.2 Let and var

```moonlift
let name[: T] = expr
var name[: T] = expr
```

| Binding | Mutability | Semantics |
|---|---|---|
| `let` | Immutable | Value binding. The name is an alias for the value. Cannot be assigned to after initialization. |
| `var` | Mutable | Cell binding. The name refers to a mutable storage location. Can appear on the left side of `=`. |

`let` bindings are SSA-like: they name a value. The backend may reuse the
register or stack slot at its discretion. `var` bindings are always backed
by storage (stack slot or register with spill).

Type annotations on `let` and `var` are optional. If omitted, the parser marks
the type for later inference/checking.

Examples:

```moonlift
let x: i32 = 42
let name: ptr(u8) = &buffer[0]
let sum: f64 = as(f64, a) + as(f64, b)

var i: index = 0
var acc: i32 = 0
i = i + 1
acc = acc + xs[i]
```

### 8.3 Assignment

```moonlift
place = expr
```

Places that can appear on the left side of `=`:

- `var` bindings: `i = i + 1`
- Pointer dereferences: `*p = value`
- Index expressions on views or pointers: `xs[i] = value`
- Field accesses on struct pointers: `(*p).field = value`
- Nested combinations: `xs[i].field = value`

Assignment requires the place type and expression type to match exactly.
Implicit conversions are not performed. Use `as(T, expr)` for conversions.

### 8.4 If statement

```moonlift
if cond then
    stmt*
end
```

With else branch:

```moonlift
if cond then
    stmt*
else
    stmt*
end
```

With elseif chains:

```moonlift
if cond1 then
    stmt*
elseif cond2 then
    stmt*
elseif cond3 then
    stmt*
else
    stmt*
end
```

`elseif` behaves exactly as a nested `if` in the else branch — there is no
separate `elseif` IR construct. All conditional paths must be properly
terminated if inside a control region (see §10).

Single-line forms are common in hosted islands:

```moonlift
if i >= n then jump done() end
if cond then jump loop(i = i + 1, acc = acc + 1) end
```

### 8.5 Switch statement

```moonlift
switch value do
case key1 then
    stmt*
case key2 then
    stmt*
default then
    stmt*
end
```

Rules:

- **No fallthrough.** Each case arm is an independent control branch. There is
  no implicit continuation from one case to the next. This is a deliberate
  design choice — every case provides its own complete termination.
- **Case keys** are integer or boolean literal expressions. They must be
  compile-time constants.
- **Default arm** is required. Every possible value of the switch expression
  must be covered, either by an explicit case or by the default arm. If the
  switch type is `bool`, both `true` and `false` must have cases (or default
  must be present).
- **Switch type** must be a scalar integer type (`i8`..`i64`, `u8`..`u64`,
  `index`) or `bool`. Enum types are supported through their integer
  representation.
- **Duplicate case keys** are rejected.

When switch arms are generated from Lua data, they can be built as plain tables
and spread into a source switch with `@{arms...}`:

```lua
local arms = {}
for i, key in ipairs(keys) do
    arms[i] = {
        raw_key = tostring(key),
        body = moon.stmts("jump handler_" .. key .. "(result)")
    }
end
```

```moonlift
switch opcode do
@{arms...}
default then jump unknown()
end
```

Each arm is `{ raw_key, body }` where `body` is a statement list (`Stmt[]`)
produced by `moon.stmts(...)`. String concatenation handles parametric
bodies; the Lua `for` loop handles generation.

### 8.6 Emit statement

```moonlift
emit fragment(arg1, arg2, ...; exit1 = block1, exit2 = block2, ...)
```

`emit` splices a region fragment's control graph into the surrounding function
or region. It is a compile-time control-flow composition operation, not a
runtime function call.

The fragment's runtime parameters are passed positionally before the semicolon.
The fragment's continuation exits are mapped to locally-defined block labels
after the semicolon.

Every continuation exit declared by the fragment must be filled (mapped to a
local block). Extra fills for undeclared continuations are rejected. Missing
fills for declared continuations are rejected.

Example:

```moonlift
region parse_digit(p: ptr(u8), n: i32, pos: i32;
                   ok(next: i32, value: i32),
                   err(pos: i32, code: i32))
    ...
end

-- Usage:
return region: i32
entry start()
    emit parse_digit(p, n, 0; ok = got_digit, err = bad)
end
block got_digit(next: i32, value: i32)
    yield value
end
block bad(pos: i32, code: i32)
    yield -1
end
end
```

### 8.6.1 Call statement

```moonlift
call fragment(arg1, arg2, ...; exit1 = block1, exit2 = block2, ...)
```

`call` has the same source position and fill syntax as `emit`, but chooses a
function boundary instead of an inline splice. The frontend generates an ordinary
result tagged union and wrapper function for the region protocol, calls that
wrapper, then immediately switches on the result and jumps to the mapped local
continuation block.

In short:

- `emit` = inline CFG splice; continuation payloads remain in control flow.
- `call` = generated function + result union + local dispatch.

Because `call` packs the continuation protocol into data, continuation payloads
must be durable data. Payloads containing leases are rejected; use `emit` when a
region carries temporary access so that the lease stays in control flow.

### 8.7 Jump statement

```moonlift
jump label(name = expr, name = expr, ...)
```

Jump arguments are named, not positional. A jump terminates the current
execution path — no statements after a jump in the same block are reachable.

Rules:

- The target label must be a block in the current control region.
- Jump argument names must match target block parameter names exactly
  (order-insensitive matching by name).
- Jump argument types must match target block parameter types.
- All target block parameters must be provided. Extra jump arguments are
  rejected.

### 8.8 Yield statement

```moonlift
yield           -- void yield
yield expr      -- value yield
```

`yield` exits the nearest enclosing control region.

- `yield expr` is valid inside a value-producing control region (control
  expression). The expression type must match the region's declared result
  type.
- Bare `yield` is valid inside a void/statement control region.
- `yield` is rejected outside a control region.
- After a `yield`, execution continues at the point immediately after the
  enclosing `region: T ... end` or `block ... end` construct.

### 8.9 Return statement

```moonlift
return          -- void return
return expr     -- value return
```

`return` exits the enclosing function, not merely the local control region.
A `return` inside a nested control region exits all enclosing regions and
the function.

- `return expr` requires the expression type to match the function's declared
  result type.
- Bare `return` requires the function to have `void` result type.

### 8.10 Expression statement

An expression can appear as a statement. This is mainly useful for:

- Void function calls: `do_something(x, y)`
- Discarded value expressions

---

## 9. Expressions

### 9.1 Expression categories

```text
expr ::= literal
       | name        (variable reference)
       | call        (function call)
       | field       (named field access)
       | index       (indexed access)
       | deref       (pointer dereference)
       | addrof      (address-of place)
       | unary       (negation, bitwise not, boolean not)
       | binary      (arithmetic, bitwise, shift)
       | comparison  (equality, relational)
       | logic       (and, or)
       | as_expr     (semantic conversion)
       | select_expr (dataflow choice)
       | len_expr    (view length)
       | view_expr   (view construction)
       | agg_expr    (struct literal construction)
       | array_expr  (array literal construction)
       | emit_expr   (expression fragment emit)
       | region_expr (multi-block region expression)
       | switch_expr (switch expression)
```

### 9.2 Literals

```moonlift
42              -- integer literal (type determined by context or as(T, ...))
0xFF            -- hex integer literal
1_000_000       -- decimal with underscores
3.14            -- float literal
1.5e-2          -- float with exponent
"hello\n"       -- C-style NUL-terminated ptr(u8) string
true            -- bool literal
false           -- bool literal
nil             -- nil literal (typed as ptr(u8) null pointer in most contexts)
```

Numeric literals carry no inherent type. The type is determined by the
expected type at the expression's position: a parameter typed `i32` gives an
`i32` literal, a `let x: f64 = 42` produces `42.0`, etc. String literals have
inherent type `ptr(u8)` and point at read-only static bytes with an added `\0`.
When the expected type is ambiguous, use `as(T, literal)`.

### 9.3 Name references

```moonlift
x               -- local variable or parameter
p               -- pointer parameter
xs              -- view parameter
```

Name resolution follows lexical scoping: function parameters and `let`/`var`
bindings. Host-provided/module bindings may also be made available by the
surrounding compilation environment. Shadowing is permitted with inner bindings
hiding outer bindings.

### 9.4 Function calls

```moonlift
callee(arg1, arg2, arg3)
```

Call target resolution is a semantic phase. Calls resolve to:

- **Direct calls:** Named function in the current module or an imported module.
  Compiled as a direct `call` instruction.
- **Extern calls:** Named extern function. Compiled as a C-ABI call to an
  external symbol.
- **Indirect calls:** Call through a function pointer value. The pointer must
  have a function type.
- **Closure calls:** Call through a closure value (function pointer + context).

All argument types must match the callee's parameter types. Implicit
conversions are not performed at call sites. Use `as(T, arg)` for conversions.

### 9.5 Field access

```moonlift
base.field
```

Dotted syntax is preserved first and resolved later in the semantic phase.
It can mean:

- **Field projection:** Access a field on a struct value or pointer.
  `ptr.field` reads the field from the struct.
- **Qualified binding path:** Access a binding through a module path.
  Resolution priority: local bindings > module items > type fields.

When the base is a pointer to a struct, field access implicitly dereferences
the pointer (like C's `->` operator). There is no separate arrow syntax.

### 9.6 Index access

```moonlift
base[index]
```

Index access applies to:

- `ptr(T)`: indexes as `*(base + index)`, accessing the `index`-th `T` after
  the pointer. Equivalent to C's `base[index]` on arrays.
- `view(T)`: bounds-checked access to the `index`-th element of the view.

The index expression must have type `index` or a compatible integer type.

### 9.7 Pointer dereference

```moonlift
*expr
```

Dereferences a pointer value. `*p` where `p: ptr(T)` produces a value of type
`T` at the expression level. In place position, `*p = value` writes through
the pointer.

### 9.8 Address-of

```moonlift
&place
```

Takes the address of a place. Valid places include `var` bindings, statics,
indexed locations, and struct fields. The result type is `ptr(T)` where `T`
is the place type.

### 9.9 Semantic conversion

```moonlift
as(target_type, expr)
```

`as(T, value)` is the only source-level type conversion form. It is a semantic
conversion request. The compiler chooses the concrete machine operation from
the source and target scalar types:

| Source → Target | Machine operation |
|---|---|
| smaller int → larger int | Sign-extend or zero-extend |
| larger int → smaller int | Truncate |
| int → float | `scalar_to_float` (signed) or `uint_to_float` |
| float → int | `float_to_scalar` or `float_to_uint` |
| float → smaller float | `fdemote` |
| float → larger float | `fpromote` |
| same-size int ↔ same-size int | `bitcast` (reinterpret bits) |
| int ↔ float | numeric conversion (`as`) or explicit same-width reinterpret (`bitcast`) |
| same type | Identity (no-op) |

All valid conversions between supported scalars are defined. Conversions
between fundamentally incompatible types (e.g. `as(ptr(u8), f64_value)`) are
rejected at typecheck time.

Examples:

```moonlift
let c: i32 = as(i32, p[i])          -- u8 → i32 (unsigned extend)
let x: f64 = as(f64, count)         -- i32 → f64 (int to float)
let byte: u8 = as(u8, word)         -- i32 → u8 (truncate)
let bits: i32 = bitcast(i32, float_val) -- f32 bits → i32 bits
```

### 9.10 Select expression

```moonlift
select(cond, then_expr, else_expr)
```

`select` is dataflow choice, distinct from control-flow `if`. Both branches are
evaluated (modulo dead-code elimination) and the result is selected based on
the condition. Equivalent to C's ternary `cond ? a : b`.

The condition must have type `bool`. Both branches must have the same type.
Unlike `if` statements, `select` does not introduce new control blocks.

### 9.11 Len expression

```moonlift
len(view_expr)
```

Returns the number of elements in a view, typed as `index`.

### 9.12 View construction

```moonlift
view(data_ptr, count)
view(data_ptr, count, stride)
```

- `view(ptr, count)` creates a contiguous view with `stride = 1`.
- `view(ptr, count, stride)` creates a strided view.

### 9.13 Struct literals (aggregate construction)

```moonlift
{ field1 = expr1, field2 = expr2, ... }         -- anonymous struct literal
TypeName{ field1 = expr1, field2 = expr2, ... }  -- named struct literal
```

Struct literals construct a value of struct type with named field initializers.

**Anonymous form** `{ field = expr, ... }` produces a value whose type is
inferred from context. The expected type at that position must be a struct type
with matching field names. Each field must be initialized exactly once.

**Named form** `TypeName{ field = expr, ... }` specifies the struct type
explicitly. `TypeName` can be a locally declared struct, an imported type, or a
fully qualified path.

Fields are initialized in source order but matched by name at typecheck time.
Missing fields or extra fields produce a type error. Field order in the literal
need not match declaration order — the compiler resolves by name.

Examples:

```moonlift
struct Vec3 x: f32, y: f32, z: f32 end

func magnitude(v: Vec3): f32
    return sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
end

func example(): Vec3
    -- Anonymous struct literal, type inferred from return type
    return { x = 1.0, y = 2.0, z = 3.0 }
end

func example2(): f32
    -- Named struct literal
    let v = Vec3{ x = 3.0, y = 4.0, z = 0.0 }
    return magnitude(v)
end
```

Struct literals may also be used in `let` and `var` bindings with explicit type:

```moonlift
let v: Vec3 = { x = 1.0, y = 0.0, z = 0.0 }
```

At the ASDL level, struct literals are `ExprAgg` nodes containing a type and a
list of `FieldInit(name, value, offset)` records. Field offsets are computed
during semantic layout resolution.

### 9.14 Array literals

```moonlift
[elem1, elem2, ...]          -- array literal
```

Array literals construct a fixed-length array value. The element type is
inferred from the expected type context or from the element expressions. All
elements must have the same type.

Examples:

```moonlift
func sum(xs: [i32; 4]): i32
    return xs[0] + xs[1] + xs[2] + xs[3]
end

func example(): [i32; 3]
    return [1, 2, 3]
end

let a: [i32; 4] = [10, 20, 30, 40]
```

Array literal vs view construction:

| Expression | Type | Semantics |
|---|---|---|
| `[1, 2, 3]` | `[i32; 3]` | Inline array value (value type) |
| `view(ptr, 3)` | `view(i32)` | Runtime descriptor (pointer + length) |

At the ASDL level, array literals are `ExprArray` nodes containing an element
type and a list of element expressions.

### 9.15 Unary operators

```text
- expr       numeric negation (integers and floats)
not expr     boolean not (expects bool, returns bool)
~ expr       bitwise not (integers only)
```

Negation on unsigned types is rejected. Negation on signed types is wrapping.
Floating-point negation is IEEE 754 `fneg`.

### 9.16 Binary arithmetic operators

```text
+            addition
-            subtraction
*            multiplication
/            division (float only; integer division is not source-defined)
%            remainder (signed/unsigned integer, or float)
```

Integer arithmetic is wrapping by default. Float arithmetic uses strict IEEE
754 semantics.

Division `/` on integers is NOT defined. Use explicit integer division through
the lowering path or through ASDL construction (`BackCmd.Sdiv` / `BackCmd.Udiv`).

### 9.17 Bitwise operators

```text
&            bitwise and
|            bitwise or
~            bitwise xor (in binary position)
<<           left shift
>>           arithmetic right shift (sign-extending)
>>>          logical right shift (zero-extending)
```

Bitwise operators require integer operands. Shift amounts are masked to the
bit width of the shifted type.

### 9.18 Comparison operators

```text
==           equality
~=           inequality
<            less than
<=           less than or equal
>            greater than
>=           greater than or equal
```

Comparisons return `bool`. Both operands must have the same type.

Signed/unsigned comparison semantics depend on the operand types. `i32 < i32`
uses signed comparison. `u32 < u32` uses unsigned comparison. Mixed-sign
comparisons require explicit `as` conversions.

Float comparisons follow IEEE 754: `NaN ~= NaN` is true, `NaN < x` and `NaN > x`
are false.

### 9.19 Logical operators

```text
and          logical and (short-circuit)
or           logical or (short-circuit)
```

Both operands must have type `bool`. `and` and `or` are short-circuiting:
the right operand is evaluated only if needed.

For dataflow choice without control flow, use `select(cond, a, b)`.

### 9.20 Operator precedence

From lowest to highest:

| Level | Operators |
|---|---|
| 1 | `or` |
| 2 | `and` |
| 3 | `==` `~=` `<` `<=` `>` `>=` |
| 4 | `\|` (bitwise or) |
| 5 | `~` (bitwise xor) |
| 6 | `&` (bitwise and) |
| 7 | `<<` `>>` `>>>` |
| 8 | `+` `-` |
| 9 | `*` `/` `%` |
| 10 | unary: `-` `not` `~` `&` `*` |
| 11 | postfix: `f(args)` `.field` `[index]` |

Parentheses `(expr)` override precedence as usual.

### 9.21 Emit expression

```moonlift
emit fragment(arg1, arg2)
```

Expression fragment emit. Expression fragments return a typed expression result
and lower through `ExprUseExprFrag`. Unlike region fragment emits, expression
fragment emits produce a value (not a control-flow splice).

### 9.22 Switch expression

```moonlift
switch value do
case key1 then
    stmt*
    result_expr
case key2 then
    stmt*
    result_expr
default then
    stmt*
    result_expr
end
```

Like a switch statement but each arm produces a final expression value. All
arms must produce the same scalar type. Integer/boolean constant cases lower to
backend switch blocks with a join value. Arm-local statements and default-arm
statements are supported.

---

## 10. Control regions

Control regions are the heart of Moonlift. They replace traditional structured
loops (`for`, `while`) with explicit typed blocks, named jump arguments, and
explicit `yield` / `return` exits.

### 10.1 Concepts

```text
control region  = a delimited scope containing one or more labeled blocks
entry block     = the first block in a control region; parameters have initializers
block           = a labeled continuation / state point with typed parameters
jump            = typed state transition from one block to another
yield           = exit the control region, optionally producing a value
return          = exit the enclosing function entirely
```

A control region has a result type (for expressions) or is void (for
statements). Every block path must terminate explicitly. There is no implicit
fallthrough between blocks.

### 10.2 Single-block control statement

The simplest control region — a single labeled block with a void yield:

```moonlift
block loop(i: index = 0)
    if i >= n then
        yield
    end
    dst[i] = 0
    jump loop(i = i + 1)
end
```

A void `yield` exits the control statement. Execution continues at the
statement immediately after the `end` of the block.

### 10.3 Single-block control expression

A single block that produces a value:

```moonlift
let total: i32 = block loop(i: index = 0, acc: i32 = 0): i32
    if i >= n then
        yield acc
    end
    jump loop(i = i + 1, acc = acc + xs[i])
end
```

The result type (`: i32`) is declared after the block parameters. The `yield`
expression must match this type.

### 10.4 Multi-block control expression

Multiple named blocks with explicit state transitions:

```moonlift
return region: i32
entry start()
    jump loop(i = 0, acc = 0)
end
block loop(i: index, acc: i32)
    if i >= n then
        yield acc
    end
    if xs[i] < 0 then
        jump fail()
    end
    jump loop(i = i + 1, acc = acc + xs[i])
end
block fail()
    yield -1
end
end
```

A multi-block control expression wraps blocks in `region: T ... end`.
The first block is the entry block. Entry blocks can use `entry` or `block`
keyword — both are accepted for the first block.

### 10.5 Block parameters

**Entry block parameters** (with initializers):

```moonlift
block loop(i: index = 0, acc: i32 = 0)
```

The initializer expression determines the value on first entry. The type
annotation determines the parameter's type.

**Non-entry block parameters** (target signatures):

```moonlift
block done(value: i32)
block found(pos: i32, code: i32)
```

Non-entry block parameters have no initializers. They receive their values
from `jump` arguments. Each parameter name in the block must match a jump
argument name from callers.

### 10.6 Block labels

Block labels are scoped to the nearest enclosing control region (`block` or
`region`). Labels are not visible outside their region. Duplicate labels within
a region are rejected.

Block labels in a control expression can be used as jump targets and as emit
continuation fill targets.

### 10.7 Termination rules

Every control-block path must terminate with exactly one of:

1. `jump label(args...)` — transfer to another block in the same region
2. `yield expr` or `yield` — exit the control region
3. `return expr` or `return` — exit the enclosing function
4. An `if` or `switch` where every branch terminates

Paths that do not terminate are rejected. Paths with multiple terminating
statements (dead code after a jump/yield/return) produce warnings.

There is no implicit fallthrough from one block to the next. If you want
sequential block execution, use an explicit `jump` from the first block to
the second.

### 10.8 Function-tail loop pattern

When a loop is the last thing in a function, `return` can be used directly
from within the block instead of yielding and then returning:

```moonlift
func sum(xs: view(i32), n: index): i32
    block loop(i: index = 0, acc: i32 = 0)
        if i >= n then
            return acc
        end
        jump loop(i = i + 1, acc = acc + xs[i])
    end
end
```

This avoids the extra `let total = block ... end; return total` indirection.

### 10.9 Validation facts

Control validation produces explicit ASDL facts and rejects:

- **Labels:** declared block labels, their parameter signatures
- **Params:** entry initializer types, non-entry target signatures
- **Jump edges:** source block, target label, named argument bindings
- **Jump args:** per-argument name, type, and source expression
- **Yield sites:** yield type vs region result type
- **Return sites:** return type vs function result type
- **Backedges:** identified from jump targets that dominate the jump source
  (structural backedge detection, not runtime)
- **Duplicate/missing labels:** reported as control rejects
- **Missing/extra/duplicate jump args:** per-edge validation
- **Type mismatches:** jump arg type vs block param type
- **Unterminated blocks:** blocks with paths that don't terminate

Optimization and vectorization consume these facts and decisions. They never
rediscover control structure from raw IR.

---

## 11. Region fragments and continuation protocols

### 11.1 Region fragment declaration

A region fragment is a typed, reusable control component with a declared
continuation protocol:

```moonlift
region scan_until(p: ptr(u8), n: i32, target: i32;
                  hit(pos: i32)
                | miss(pos: i32))
entry loop(i: i32 = 0)
    if i >= n then
        jump miss(pos = i)
    end
    if as(i32, p[i]) == target then
        jump hit(pos = i)
    end
    jump loop(i = i + 1)
end
end
```

**Anatomy:**

```text
region name ( runtime_params ;
             exit1_name(exit1_params...)
             exit2_name(exit2_params...)
             empty_exit_name )
    body (same as a control region)
end
```

- **Runtime parameters** (before the semicolon): values passed by the caller
  at each emit site.
- **Continuations** (after the semicolon): the fragment's output protocol.
  Each continuation declares a name and typed parameters using the same
  protocol-variant style as named-field union variants. Continuation
  alternatives are separated by `|`. A bare continuation name means no payload.
- **Body:** exactly one entry block and zero or more additional blocks. The
  body uses `jump cont_name(args...)` to exit through a continuation.

Region fragments are not functions — they are control-flow templates that
are spliced (inlined) at each `emit` site. There is no runtime call overhead.
The backend sees a combined control-flow graph after expansion.

### 11.2 Emit use (region fragments)

```moonlift
return region: i32
entry start()
    emit scan_until(p, n, target; hit = found, miss = missing)
end
block found(pos: i32)
    yield pos
end
block missing(pos: i32)
    yield -1
end
end
```

The caller provides:
1. Runtime arguments (positional, before the semicolon)
2. Continuation mappings (named, after the semicolon)

The caller's blocks receive the continuation parameters. The caller decides
what each exit means — the fragment only declares its protocol.

The same fragment can also be used with `call`:

```moonlift
call scan_until(p, n, target; hit = found, miss = missing)
```

`emit` and `call` share the same region protocol and continuation-fill syntax.
They differ only in the cost boundary and representation chosen by the frontend:

| Use | Lowering | When to use |
| --- | --- | --- |
| `emit` | Inline control-flow graph splice | Default composition; zero call overhead; leases may remain in control flow |
| `call` | Generated wrapper function returning a generated tagged-union result, followed by a local variant dispatch | Code-size or sharing boundary; continuation payloads must be durable data |

A `call` must disappear during open/RNF expansion. Backend lowering sees only
ordinary functions, calls, tagged-union constructors/switches, jumps, and traps.
If a continuation payload contains a lease, the generated result type is
rejected; use `emit` so temporary access stays in control flow.

### 11.3 Continuation forwarding

A fragment can emit another fragment and forward exits to its own continuation
slots:

```moonlift
region wrapper(p: ptr(u8), n: i32; out(pos: i32))
entry start()
    emit inner(p, n; hit = out)      -- forward inner.hit → wrapper.out
end
end
```

Forwarding is represented as `SlotValueContSlot` in the open/expand phase and
expands to ordinary jumps. No trampoline or runtime indirection.

### 11.4 Fragment composition patterns

**Sequential composition:**

```moonlift
emit first(args; ok = middle_start)
block middle_start(...)
    emit second(args2; ok = done, err = fail)
end
```

**Conditional composition:**

```moonlift
if cond then
    emit path_a(args; done = out)
else
    emit path_b(args; done = out)
end
```

**Switch-based dispatch:**

```moonlift
switch tag do
case 0 then emit handler_0(args; done = out)
case 1 then emit handler_1(args; done = out)
default then jump out(value = -1)
end
```

---

## 12. Expression fragments

Expression fragments are staged scalar/dataflow components. They are simpler
than region fragments — they produce a value, not a control-flow graph.

### 12.1 Declaration

```moonlift
expr clamp_nonneg(x: i32): i32
    select(x < 0, 0, x)
end

expr square(x: f64): f64
    x * x
end
```

Expression fragments have:
- A parameter list using the same open-param grammar as region fragments
- A single result type
- A single expression body (no statements)

They cannot contain jumps, yields, returns, or control regions.

### 12.2 Emit use

```moonlift
let score: i32 = emit clamp_nonneg(v)
let area: f64 = emit square(radius)
```

Expression fragment emits produce a typed value. They lower through
`ExprUseExprFrag` and are expanded (inlined) at each use site, like region
fragments.

### 12.3 Lua-generated expression fragment families

```lua
local function threshold_after(tag, pivot)
    local name = "threshold_after_" .. tag
    return expr @{name}(x: i32): i32
        select(x > @{pivot}, x - @{pivot}, 0)
    end
end

local score_after_50 = threshold_after("50", 50)
local score_after_60 = threshold_after("60", 60)
```

Each call to the Lua factory produces a distinct, monomorphic expression
fragment with a stable name. Used in tight inner loops where the fragment
is inlined at the emit site.

---

## 13. Contracts

Function parameters and `requires` clauses produce binding-backed contract
facts. Contracts are consumed by the vector safety phase (for alias and
bounds proofs) and by the backend validation phase.

### 13.1 Parameter modifiers

```moonlift
func f(noalias readonly xs: ptr(i32), writeonly dst: ptr(i32), n: i32): i32
    ...
end
```

Modifiers apply to pointer and view parameters. They are part of the
function's type signature and are checked at call sites.

### 13.2 Requires clauses

`requires` clauses appear in function bodies, before the first statement:

```moonlift
func copy(dst: ptr(u8), src: ptr(u8), n: index)
    requires disjoint(dst, src)
    requires bounds(dst, n)
    requires bounds(src, n)
    ...
end
```

**Available contract predicates:**

| Predicate | Parameters | Meaning |
|---|---|---|
| `bounds(ptr, len)` | pointer, length | The pointer points to at least `len` valid elements |
| `window_bounds(base, base_len, start, len)` | view, start, len | A window of `len` elements starting at `start` is within the base view |
| `disjoint(a, b)` | pointer, pointer | The two pointers point to non-overlapping memory |
| `same_len(a, b)` | view, view | The two views have the same length |
| `noalias(x)` | pointer | This pointer does not alias any other pointer in the function |
| `readonly(x)` | pointer/view | Memory reachable through this reference is only read |
| `writeonly(x)` | pointer/view | Memory reachable through this reference is only written |
| `invalidate(x)` | pointer/view | Operation may invalidate live leases from this store/access path |
| `preserve(x)` | pointer/view | Operation preserves live leases from this store/access path |

Contracts are not runtime checks — they are compile-time facts that enable
optimizations (vectorization, alias analysis, bounds check elimination).
Violating a contract at runtime is undefined behavior.

---

## 14. Lua splicing and antiquote

Inside hosted source islands, Lua values are spliced into Moonlift source with
the antiquote syntax:

```moonlift
@{lua_expr}      -- one value
@{lua_expr...}   -- spread a Lua list into a Moonlift list position
```

`@{x}` inserts one typed value. `@{xs...}` evaluates `xs` and expands its
sequential Lua elements in the current syntactic list. The parser owns
separators; Lua values do not include commas or semicolons.

**In `.mlua` files**, bare Lua expressions (without `@{...}`) are accepted in
type, fragment reference, and emit-call positions.  Each expression is
evaluated through the splice mechanism at parse time against declarations
from earlier islands in the same file.  `@{...}` is still required for
expression positions, spread positions, and list positions.

Unlike the three-phase `.mlua` carrier model (parse → fill → expand), standalone
`moon.XXX[[]]` quotes evaluate `@{}` eagerly at quote time using an explicit
values table (see §14.4).

### 14.0 Type and fragment references without @{...}

Same-file bare names (	exttt{Arena}, 	exttt{Pair}) in type position are resolved
by the typechecker from the module's own declarations.  They require no
	exttt{@\{\}} syntax:

```lua
local Texture = handle Texture : u32 invalid 0 end

local load = func load(id: u32): ptr(Texture)   -- bare name, resolved at typecheck time
    ...
end
```

Dotted names (	exttt{M.T.Arena}) in type position are cross-module Lua value
references.  They create splice slots resolved through bindings, like any
other 	exttt{@\{expr\}}.  They work in 	exttt{.mlua} files where the transform
supplies bindings automatically, but in hosted code they require the binder
path:\

```lua
-- .mlua file (bindings automatic)
func f(a: ptr(M.T.Arena))   -- dotted name = cross-module, works via bindings
    ...
end

-- Hosted Lua (must use @{})
moon.func { Arena = M.T.Arena } [[ func f(a: ptr(@{Arena})) ... end ]]
```

Fragment references in 	exttt{emit} / 	exttt{call} positions always require
	exttt{@\{expr\}}:\

```lua
emit @{R.scan}(p, n; hit = found, miss = not_found)
```

### 14.1 Splice positions and expected kinds

| Source position | Expected splice kind |
|---|---|
| Type position (`let x: @{T}`, `as(ptr(@{T}), x)`) | A type value. All non-scalar names create splice slots; same-file names are filled from the module's items, cross-file names from bindings. |
| Type list position (`func(@{types...}): T`) | A Lua array of type values. |
| Expression position (`@{val} + 1`) | A literal/expression source value. `@{...}` required — bare names resolve as Moonlift bindings. |
| Expression list position (`f(@{args...})`, `emit frag(@{args...}; ...)`) | A Lua array of expression values/literals. |
| Function parameter list (`func f(@{params...})`) | A Lua array of `moon.params{...}` values or raw `MoonType.Param` nodes. |
| Struct field list (`struct S @{fields...} end`) | A Lua array of `moon.fields{...}` values or raw `MoonType.FieldDecl` nodes. |
| Tagged-union variant list (`union ... @{variants...} end`) | A Lua array of `moon.variants{...}` values or raw `MoonType.VariantDecl` nodes. |
| Statement/body position (`@{stmts...}`) | A Lua array of `MoonTree.Stmt` nodes, commonly produced by `moon.stmts[[]]`. |
| Region runtime/open parameter list (`region r(@{params...}; ...)`) | A Lua array of params/open params. Spliced params are visible by name in the region body. |
| Region continuation list (`region r(...; @{conts...})`) | A Lua array of continuation descriptors (`{ name = ..., params = {...} }`) or `MoonOpen.ContSlot` nodes. Spliced continuations are visible by name for `jump`. |
| Region block parameter list (`entry e(@{entry_params...})`, `block b(@{params...})`) | Entry params from `moon.entry_params{...}`; block/continuation params from `moon.params{...}` or `MoonTree.BlockParam`. |
| Region block list (`@{blocks...}` after an entry block) | A Lua array of raw `MoonTree.ControlBlock` nodes or `moon.blocks{...}` values. |
| Switch arm list (`@{arms...}` before `default`) | A Lua array of arm values — either `MoonTree.SwitchStmtArm` nodes, or plain tables `{ raw_key, body }` where `body` is `Stmt[]`. `body` is typically produced by `moon.stmts[[]]`. |
| Emit fragment position (`emit frag(...)`, `emit @{frag}(...)`) | A region or expression fragment value.  Bare/dotted names resolve through bindings; `@{}` also supported. |
| Block label/name position | String/source value containing the complete label or generated identifier |
| Integer constant position | Number (integer), or source value that parses as an integer expression |

A splice in a name position must replace the whole name token. Partial identifier
splicing such as `foo_@{tag}` is not supported by the parser; build the complete
name in Lua instead (`local name = "foo_" .. tag`) and write `@{name}`.

### 14.2 Examples within `.mlua` source islands

```lua
-- Spread generated params and body statements
local params = moon.params { {"a", moon.i32}, {"b", moon.i32} }
local body = moon.stmts [[ return a + b ]]

return func add(@{params...}): i32
    @{body...}
end

-- Spread region params and continuations
local rparams = moon.params { {"n", moon.i32} }
local exits = { { name = "done", params = { {name="v", type=moon.i32} } } }
return region generated(@{rparams...}; @{exits...})
entry start()
    jump done(v = n)
end
end

-- Splice a type (@{...} never required in type position in .mlua files)
local T = moon.i32
local inc = expr(x: T): T
    x + 1
end

-- Bare fragment reference (no @{...} needed)
return func parse_A(p: ptr(u8), n: i32): i32
    return region: i32
    entry start()
        emit frag(p, n; hit = done, miss = bad)
    end
    block done(pos: i32)
        yield pos
    end
    block bad(pos: i32)
        yield -1
    end
    end
end

-- @{...} when the fragment is a local variable (not a table path)
local frag = make_scanner(65)
return func scan_B(p: ptr(u8), n: i32): i32
    return region: i32
    entry start()
        emit @{frag}(p, n; hit = done, miss = bad)
    end
    ...
    end
end

-- Splice constants
local ALIGN = 16
local SIZE = 1024
struct Buffer
    data: ptr(u8)
    len: index
end
```

### 14.3 Splicing semantics

Splicing is checked against the expected syntactic role. Typed host values are
preferred (`moon.i32`, params, fields, statements, region fragment values,
expression fragment values, source values). Spread splices are role-checked per
element, so `@{params...}` is accepted in parameter-list positions and rejected
where fields/statements/expressions are expected.

For pragmatic generated-code cases, strings are treated as explicit complete
Moonlift source/name fragments, not as quoted string literals; use
`moon.string_lit(...)` or a Moonlift string literal when you want a runtime
`ptr(u8)` string.

There is no runtime splicing. All `@{...}` expressions are evaluated exactly
once when the `.mlua` file is loaded. The parser records typed holes and the
host bridge fills them with checked Lua values.

### 14.4 Binding values: `moon.XXX{values}[[src]]`

Standalone quotes (`moon.stmts[[]]`, `moon.expr[[]]`, etc.) do NOT evaluate
`@{}` by default — they reject splices with an error. To pass Lua values into
a quote, use the **values binder** pattern:

```lua
moon.stmts { val = moon.int(42) } [[ let y: i32 = @{val}; return y ]]
```

The values table comes FIRST and returns a **quote function**. The `[[]]`
invocation parses the string, looks up each `@{}` key in the values table,
fills the slot, expands, and returns clean ASDL.

```lua
-- Multiple values
moon.stmts { T = moon.i32, init = moon.int(0) } [[ let x: @{T} = @{init} ]]

-- Spread lists
moon.func { params = param_list } [[ add(@{params...}): i32 @{body} end ]]

-- Reusable binder
local with_i32 = moon.stmts { T = moon.i32 }
local body1 = with_i32 [[ let x: @{T} = 0 ]]
local body2 = with_i32 [[ return as(@{T}, val) ]]
```

If a pure quote has no `@{}`, the pure `moon.stmts[[]]` form is used directly
without a values table:

```lua
local body = moon.stmts [[ let y: i32 = x + 1; return y ]]
```

---

## 15. Quoting and table builder API reference

The unified `require("moonlift")` module exposes a small set of quoting forms
that turn Moonlift source strings into live Lua values. The central abstraction
is the **signature closure**: a Lua closure that carries a typed Moonlift signature
and lazily compiles to native code when its body is provided.

| Form | Returns |
|---|---|
| `moon.XXX[[src]]` | Parsed ASDL value — a type, expression, func, region, etc. |
| `moon.XXX{values}[[src]]` | Same, with `@{}` splices filled from values table |
| `moon.XXX[[sig]][[body]]` | **Signature closure** if body omitted; `CallableFunc` if body provided |
| `moon.XXX{array}` | Table builder — array of record tables → typed ASDL |

The third form is the key insight: **a Moonlift function signature is a first-class
Lua value** that can be stored, passed, specialized, and compiled independently
from its body.

```lua
-- Pure signature, no body — returns a closure
local add = moon.func[[ add(a: i32, b: i32): i32 ]]
-- add is a Lua closure carrying a typed ASDL signature
-- It stores: name, params, result — no compiled code yet

-- Provide the body — returns a callable native function
local compiled = add[[ return a + b ]]
print(compiled(3, 4))  -- 7
compiled:free()

-- One-shot: both sig and body at once
local f = moon.func[[ sub(a: i32, b: i32): i32 ]][[ return a - b ]]
print(f(10, 3))  -- 7
f:free()
```

### 15.1 Signature closures — func, region, extern

Every `moon.*` quote form follows the same pattern: parse the source, detect
whether it has a body or not. If no body, return a **signature closure**.
If body present, return a **CallableFunc** (lazily compiles on first call).

```lua
-- func signature closure
local h = moon.func[[ load(id: i32): ptr(User) ]]
h.kind   -- "func_header"
h.name   -- "load"

-- region signature closure
local r = moon.region[[ scan(p: ptr(u8), n: i32;
                              hit(pos: i32)
                            | miss(pos: i32)) ]]
r.kind   -- "region_header"
r.name   -- "scan"

-- extern — always bodyless, always a signature (no closure needed)
local e = moon.extern[[ write(fd: i32, buf: ptr(u8), count: index): index ]]
e.kind   -- "extern_func"
```

A signature closure can be:
- **Stored**: put it in a table, return it from a module, pass it to a function
- **Compiled**: `h[[ return value ]]` returns a CallableFunc
- **Specialized**: `h{ T = f64 }[[ return a ]]` overrides bindings, then compiles
- **Composed**: pass it in a values table to another function as a dependency
- **Ignored**: never called, never compiles, produces no code, no error

Header calls take body-only strings. Do not include the outer `func`/`region`
declaration and do not include the outer closing `end`; the header closure
supplies that boundary.

In `.mlua` source, function and region headers are implemented via `@{expr}`
syntax — the expression evaluates to the header value (a signature closure):

```lua
local add_h = func add(a: i32, b: i32): i32 end
local add = func @{add_h}
    return a + b
end

local scan_h = region scan(; done) end
local scan = region @{scan_h}
entry start()
    jump done()
end
end
```

The `@{expr}` is a splice slot resolved through bindings — the same mechanism
used everywhere else.  The header closure is called with the body-only text
and supplies the outer `func`/`region` boundary.  Do not include the outer
`func`/`region` keyword or the outer closing `end` in the body; the header
provides them.

Cross-file implementations use `moon.require` to import the header module,
then reference the header via a dotted Lua expression:

```lua
local M = moon.require("mwui_types")

local release = func @{M.R.ctx_release}
    field.data = as(ptr(u8), 0)
    field.len = 0
    field.stride = 1
end

local store = region @{M.R.ctx_store_text}
entry start()
    ...
end
end
```

### 15.2 Bindings and specialization

The `{values}[[src]]` pattern fills `@{}` holes in the source. When applied
to a signature closure, the bindings can **override** the closure's captured
signature before compiling the body.

```lua
-- Generic header with type binding
local h = moon.func{ T = moon.i32 }[[ add(a: @{T}, b: @{T}): @{T} ]]

-- Same bindings, provide body
local f = h{}[[ return a + b ]]
-- equivalent to: h{ T = moon.i32 }[[ return a + b ]]
print(f(3, 4))  -- 7
f:free()

-- Override bindings to specialize
local g = h{ T = moon.f64 }[[ return a + b ]]
print(g(3.5, 2.5))  -- 6.0
g:free()

-- The override pattern follows Lua's variable shadowing rule:
-- new bindings shadow old ones with the same key
```

### 15.3 Module pattern — headers and implementations

Because signature closures are Lua values, a Lua module can export them
as a **header** — declarations without implementations:

```lua
-- types.lua — header module
local moon = require("moonlift")
return {
    Vec3 = moon.struct[[ x: f32; y: f32; z: f32 end ]],
    load = moon.func[[ load(id: i32): ptr(Vec3) ]],
    mul  = moon.func{ T = moon.f32 }[[ mul(a: @{T}, b: @{T}): @{T} ]],
}
```

```lua
-- app.mlua — implementation
local T = require("types")
local load = T.load[[ return some_calc(id) ]]
local mul_f32 = T.mul{}[[ return a * b ]]
local mul_f64 = T.mul{ T = moon.f64 }[[ return a * b ]]
```

The header module carries the **product graph** (structs) and **protocol graph**
(region signatures, function signatures). The implementation module provides
the bodies. The compiler type-checks each implementation independently — if
a signature closure is never compiled, it produces no code and no error.

### 15.4 Callable functions — auto-compile on first call

When a complete function (signature + body) is provided, `moon.func` returns
a **CallableFunc** — a callable table that lazily compiles on first invocation.

```lua
local add = moon.func [[add(a: i32, b: i32): i32 return a + b end]]
print(add(3, 4))  -- 7 — first call compiles ephemeral module
print(add(10, 20)) -- 30 — cached pointer, no compilation
add:free()
```

### 15.5 Values table as module — cross-function dependencies

When a function calls another function by name, declare the dependency in the
values table. The function is registered in the ephemeral module's item list,
and the typechecker resolves the name reference during compilation.

```lua
local dep = moon.func [[dep(x: i32): i32 return x + 1 end]]
local main = moon.func { dep = dep } [[
main(x: i32): i32
    return @{dep}(x)
end
]]
print(main(5))  -- 6 — auto-compiled with dep in ephemeral module
main:free()
dep:free()
```

The `@{fn}(args)` syntax makes the dependency explicit: the `@{}` shows that
`fn` comes from the values table (a Lua value), not from Moonlift scope.

### 15.6 Module path — explicit bundle

For complex multi-function artifacts:

```lua
local b = moon.bundle("decoder")
b:add_func(parse_array)
b:add_func(parse_value)
b:add_region(skip_ws)
local compiled = b:compile()
local fn = compiled:get("decode")
```

### 15.7 Expressions

```lua
-- Quote form
moon.expr [[x + 1]]                            -- → ExprValue
moon.expr [[select(x < 0, 0, x)]]              -- → ExprValue
moon.expr [[as(i32, val)]]                     -- → ExprValue

-- Literal constructors
moon.int(42)
moon.bool_lit(true)
moon.string_lit("hello")
moon.nil_lit(ty)

-- Arithmetic (on expression values)
expr:neg()
expr:add(other)
expr:sub(other)
expr:mul(other)
expr:div(other)

-- Bitwise
expr:band(other)
expr:bor(other)
expr:bxor(other)
expr:shl(other)
expr:ashr(other)
expr:lshr(other)
```

### 15.8 Statements

```lua
moon.stmts[[let x: i32 = 42]]
moon.stmts[[return a + b]]
```

### 15.9 Types

```lua
-- Scalar type constants
moon.i8  moon.i16  moon.i32  moon.i64
moon.u8  moon.u16  moon.u32  moon.u64
moon.f32 moon.f64  moon.bool  moon.void  moon.index

-- Quote form
moon.type [[i32]]               -- → TypeValue
moon.type [[ptr(u8)]]           -- → TypeValue
moon.type [[func(i32): i32]]  -- → TypeValue

-- Compound type constructors
moon.ptr(T)
moon.view(T)
moon.named(module, name)
moon.func_type(params, result)
moon.closure_type(params, result)
```

### 15.10 Structs and unions

```lua
moon.struct[[Point x: i32; y: i32 end]]  -- returns StructValue
moon.union[[ok(i32) | err(string) end]]  -- returns UnionValue
```

Structs and unions are already declarations (no body). They always return
complete ASDL values, never closures.

-- Comparisons (on expression values)
expr:eq(other)          -- equality
expr:ne(other)          -- inequality
expr:lt(other)          -- less than
expr:le(other)          -- less than or equal
expr:gt(other)          -- greater than
expr:ge(other)          -- greater than or equal

-- Conversions and access (on expression values)
expr:as(T)              -- semantic conversion to T
expr:field("name", T?)  -- field access
expr:index(i)           -- index access
expr:select(a, b)       -- conditional value selection

-- Other expression constructors
moon.select(cond, a, b)        -- dataflow choice
moon.load(addr, T)             -- load T from address
moon.addr_of(place)            -- take address of place
moon.len(view_expr)            -- view length
moon.agg(ty, fields)           -- struct literal (aggregate)
moon.array_expr(elem_ty, elems) -- array literal
```

### 15.6 Modules and functions

```lua
-- Module creation
local M = moon.bundle("Demo")

-- Exported function (uses function builder body)
M:export_func("add", {
    {"a", moon.i32},
    {"b", moon.i32},
}, moon.i32, function(fn)
    fn:return_(fn:param("a") + fn:param("b"))
end)

-- Local function
M:func("helper", {
    {"x", moon.i32},
}, moon.i32, function(fn)
    fn:return_(fn:param("x") * moon.int(2))
end)

-- Extern function
M:extern_func("puts", {
    {"s", moon.ptr(moon.u8)},
}, moon.i32)

-- Bind extern symbols for JIT compilation from Lua.
M:symbol("puts", ffi.cast("void *", ffi.C.puts))
```

Function params are specified as Lua arrays of `{name, type}` record tables.
The duck-typed table `{"a", moon.i32}` is accepted everywhere
`moon.param("a", moon.i32)` was previously required.

Inside function bodies, parameter names are available as expression values
through `fn:param("name")` and on builder-backed functions also via bare
binding accessors where installed.

### 15.7 Statement lists

`moon.stmts` constructs a `MoonTree.Stmt[]` value. Three forms:

**Pure quote** — no `@{}`:

```lua
local body = moon.stmts [[
    let y: i32 = x + 1
    if y > 10 then
        return y
    else
        return 0
    end
]]
```

**Values binder** — quote with `@{}`:

```lua
local body = moon.stmts { T = moon.i32, limit = moon.int(10) } [[
    let y: @{T} = @{limit}
    return y
]]
```

**ASDL pass-through** — raw array of statement nodes:

```lua
local body = moon.stmts { raw_stmt1, raw_stmt2 }
```

**Example: dynamic if-else via quoting:**

```lua
local body = moon.stmts { cond = moon.expr [[x > 10]] } [[
    if @{cond} then
        return x
    else
        return 0
    end
]]
```

Use `moon.stmts { ... } [[ src ]]` instead of the retired `moon.stmts({...}, function(b) ... end)` pattern.

### 15.8 Parameters, fields, variants, continuations, blocks, entry params

Table builders for declaration-shaped things. Each returns an array of typed ASDL.

```lua
-- Parameters
local params = moon.params {
    {name="a", type=moon.i32, mods={noalias=true}},
    {"b", moon.i32},
}

-- Fields
local fields = moon.fields {
    {"x", moon.i32},
    {"y", moon.f64},
}

-- Variants
local variants = moon.variants {
    {"Some", moon.i32},
    "none",
    {name="Pair", fields={ {"a", moon.i32}, {name="b", type=moon.f64} }},
}

-- Continuations (named map — keyed by continuation name)
local conts = moon.conts {
    hit  = { params = { {name="pos", type=moon.i32} } },
    miss = { params = {} },
}

-- Blocks
local blocks = moon.blocks {
    {
        label = "loop",
        params = { {name="i", type=moon.i32, init=moon.int(0)} },
        body = moon.stmts [[ ... ]],
    },
}

-- Entry params (for region entry blocks)
local entry_params = moon.entry_params {
    {name="i", type=moon.i32, init=moon.int(0)},
}
```

### 15.9 Regions

Use `moon.region[[]]` to define a region fragment from Moonlift source:

```lua
local scan = moon.region [[
    scan(p: ptr(u8), n: i32, target: i32;
         hit(pos: i32) | miss(pos: i32))
    entry loop(i: i32 = 0)
        if i >= n then jump miss(pos = i) end
        if as(i32, p[i]) == target then jump hit(pos = i) end
        jump loop(i = i + 1)
    end
    end
]]
```

In pure `.mlua` island syntax, a region header can be implemented later by
referencing the header value via `@{expr}` after `region` and then writing
the body directly.  The header may itself be anonymous and assignment-named:

```moonlift
local scan = region(p: ptr(u8), n: i32;
                    hit(pos: i32) | miss) end

local scan_impl = region @{scan}
entry loop(i: i32 = 0)
    if i >= n then jump miss() end
    jump hit(pos = i)
end
end
```

This is transformed as a call on the Lua value `scan`, so normal Lua lexical
scope applies. Dotted references such as `region API.scan` are also accepted.

For generated region interfaces (dynamic params, conts, blocks), use the
table builders and spread them inside the `.mlua` source:

```lua
local params = moon.params { ... }
local conts = { {name="ok", params={...}}, ... }
local blocks = moon.blocks { ... }
```

```moonlift
return region @{name}(@{params...}; @{conts...})
entry start()
    ...
end
@{blocks...}
end
```

### 15.10 Expression fragments

```lua
-- Quote form
local inc = moon.expr_frag [[
    inc(x: i32): i32
        x + 1
    end
]]
```

### 15.11 Structs and unions

```lua
-- Quote form
local Point = moon.struct [[Point x: i32, y: i32 end]]
local Option = moon.union [[Option Some(i32) | None end]]

-- Using spread (inside .mlua)
-- local fields = moon.fields { ... }
-- return struct Point @{fields...} end
```

### 15.12 Extern declarations

```lua
local write = moon.extern [[
    write(fd: i32, buf: ptr(u8), count: index): index end
]]
```

### 15.13 Compilation and JIT

```lua
-- Compile the module
local compiled = M:compile()

-- Get a function pointer by name
local add = compiled:get("add")
print(add(1, 2))            -- 3 (native call)

-- Free the compiled artifact
compiled:free()
```

The `:compile()` method returns a compiled artifact. You can call `:get(name)`
multiple times; it returns the same function pointer. After `:free()`, the
artifact is invalidated and function pointers become dangling — calling them
is undefined behavior.

---

## 16. Metaprogramming and composition guide

Moonlift metaprogramming has one coherent rule:

```text
Lua builds Moonlift values.
@{x} splices one value.
@{xs...} spreads a Lua array of values.
Moonlift receives one monomorphic, typed program.
```

String quoting (`moon.XXX[[]]`) is the primary tool for writing Moonlift code
inside Lua. Table builders (`moon.params{...}`, `moon.fields{...}`, etc.)
handle the data-shaped things where Lua iteration is natural. The two work
together: build a Lua array with a `for` loop, then splice it into a quote.

### 16.0 The signature closure pattern

The fundamental metaprogramming primitive is the **signature closure** —
a Moonlift declaration (function, region, extern) carried as a Lua closure.

```lua
-- A function signature is a Lua value:
local add = moon.func[[ add(a: i32, b: i32): i32 ]]
-- Not compiled. Not callable. Just a typed signature in a closure.
```

The closure decouples **signature** from **implementation** into two separate
Lua values. This enables a clean module boundary between headers and bodies:

```lua
-- ============ types.lua ============
-- This module IS the header. It exports ONLY signatures.
-- Products (structs, unions) and protocols (func, region signatures).
local moon = require("moonlift")
return {
    Vec3 = moon.struct[[ x: f32; y: f32; z: f32 end ]],
    load = moon.func[[ load(id: i32): ptr(Vec3) ]],
    mul  = moon.func{ T = moon.i32 }[[ mul(a: @{T}, b: @{T}): @{T} ]],
}

-- ============ app.mlua ============
-- This module provides the bodies.
local types = require("types")
local load = types.load[[ return some_op(id) ]]
local mul = types.mul{}[[ return a * b ]]
```

The header closure can be:
- **Stored in a table**, returned from a Lua module, passed to a function
- **Compiled**: `h[[body]]` returns a CallableFunc that lazily compiles
- **Specialized**: `h{ T = f64 }[[body]]` overrides type bindings before compiling
- **Composed**: passed as a dependency in another function's values table
- **Ignored**: never compiled, produces no code, no error

This means the **product graph** (structs, unions) and **protocol graph**
(function signatures, region protocols) are first-class Lua values that can
live in a separate module from the implementations. The Lua module system
handles the file boundaries — no new parser, no new pipeline, no new syntax.

### 16.1 Real-world patterns with signature closures

The closure pattern unlocks several architectural patterns that were
previously impractical. Here are the most important ones.

#### Generic data structures (one algorithm, any type)

A header declares operations with a type binding. Each specialization
compiles to separate monomorphic native code:

```lua
local Stack = {
    new  = moon.func{ T = moon.i32 }[[ new(capacity: i32): ptr(@{T}) ]],
    push = moon.func{ T = moon.i32 }[[ push(s: ptr(ptr(@{T})), v: @{T}) ]],
    pop  = moon.func{ T = moon.i32 }[[ pop(s: ptr(ptr(@{T}))): @{T} ]],
}

-- Specialize to i32
local push_i32 = Stack.push{}[[
    local sp: ptr(i32) = s[0]
    sp[0] = v
    s[0] = sp + 1
end
]]

-- Specialize to f64 — same algorithm, checked against same signature
local push_f64 = Stack.push{ T = moon.f64 }[[
    local sp: ptr(f64) = s[0]
    sp[0] = v
    s[0] = sp + 1
end
]]
```

No generics system, no type parameter erasure, no monomorphization pass.
The bindings table IS the type parameter. Each specialization is a separate
Lua closure call that produces a distinct native function.

#### Multi-backend systems (same protocol, different implementations)

A header module defines the interface. Multiple implementations provide
bodies, all checked against the same signatures at compile time:

```lua
-- render.lua — product graph + protocol graph (the architecture)
local moon = require("moonlift")
return {
    Mesh = moon.struct[[ verts: ptr(Vec3); count: i32 end ]],
    render = moon.func[[ render(m: ptr(Mesh)) ]],
    load   = moon.func[[ load(path: ptr(u8)): ptr(Mesh) ]],
}
```

```lua
-- opengl.mlua — OpenGL backend
local R = require("render")
local render_gl = R.render[[ glDrawElements(m.verts, m.count) end ]]
local load_gl   = R.load[[ return loadObj(path) ]]
```

```lua
-- vulkan.mlua — Vulkan backend (same header, different specialization)
local R = require("render")
local render_vk = R.render[[ vkCmdDraw(m.verts, m.count) end ]]
local load_vk   = R.load[[ return loadVkMesh(path) ]]
```

The header is the contract. A backend that provides a body with mismatched
parameter types or return type is rejected at compile time. A backend that
forgets to implement a function is caught at link time.

#### Test mocks and dependency injection

Because signatures are closures, they can be replaced for testing:

```lua
-- Database interface (header module)
local DB = {
    query = moon.func[[ query(db: i32, sql: ptr(u8)): ptr(u8) ]],
    close = moon.func[[ close(db: i32) ]],
}

-- Production implementation
local prod = {
    query = DB.query[[ return pg_query(db, sql) ]],
    close = DB.close[[ pg_close(db) end ]],
}

-- Mock implementation — same header, different bodies
-- Both are type-checked against the same signatures
local mock = {
    query = DB.query[[ return "mock_result" ]],
    close = DB.close[[ end ]],
}

-- Swap at load time, not at compile time
local impl = os.getenv("TEST") and mock or prod
```

#### Bindings override for specialization

A header can declare defaults. Implementations override them to specialize:

```lua
-- Generic transform (default: f32)
local transform = moon.func{ T = moon.f32 }[[
    transform(m: ptr(Mesh), mat: @{T}): @{T}
]]

-- Double-precision variant (override T)
local transform_f64 = transform{ T = moon.f64 }[[
    return mat * m.verts[0]
end
]]
```

Override follows Lua's variable shadowing rule: inner bindings shadow outer
bindings with the same key. The header provides defaults, the implementation
overrides what it needs.

#### Plugin systems

A plugin API is a table of function headers. Each plugin provides bodies.
The host verifies all plugins implement the same protocol:

```lua
-- Plugin API (declared by host)
local Plugin = {
    on_load = moon.func[[ on_load(ctx: ptr(u8)) ]],
    on_tick = moon.func[[ on_tick(dt: f32) ]],
    on_draw = moon.func[[ on_draw() ]],
}

-- Plugin A
local plugin_a = {
    on_load = Plugin.on_load[[ init_plugin_a(ctx) end ]],
    on_tick = Plugin.on_tick[[ update_a(dt) end ]],
    on_draw = Plugin.on_draw[[ draw_a() end ]],
}

-- Plugin B — added later, same signatures, compiler checks both
local plugin_b = {
    on_load = Plugin.on_load[[ init_plugin_b(ctx) end ]],
    on_tick = Plugin.on_tick[[ update_b(dt) end ]],
    on_draw = Plugin.on_draw[[ draw_b() end ]],
}
```

#### Summary of the pattern

The signature closure unifies five concerns that were previously separate:

| Concern | Before | After |
|---|---|---|
| Interface definition | Documentation, convention, or OOP | Lua table of function headers |
| Implementation | Same file, coupled | Separate closure call, same signature checked |
| Generics | No Moonlift support — Lua string generation | Bindings table with `@{}` splices |
| Dependency injection | Manual registration or callbacks | Values table passed through `{}` |
| Testing | Monkey-patching or separate build | Swap bodies at `require` time |

Use the lowest level that expresses the pattern cleanly.

1. **Value quoting** — write Moonlift inline:

   ```lua
   local body = moon.stmts [[
       let y: i32 = x + 1
       return y
   ]]
   ```

2. **Value splicing** — insert one generated value into a quote:

   ```lua
   moon.stmts { T = moon.i32 } [[
       let y: @{T} = 0
       return y
   ]]
   ```

3. **List spreading** — insert many generated values into a syntactic list:

   ```lua
   local params = moon.params { {"a", moon.i32}, {"b", moon.i32} }

   return func add(@{params...}): i32
       return a + b
   end
   ```

4. **Typed region composition** — use `emit` to compose control-flow fragments:

   ```moonlift
   emit scan_byte(p, n, pos, 65; ok = got_A, err = bad)
   ```

### 16.2 Lists are ordinary Lua arrays

A spread splice expects a sequential Lua table. The role is determined by the
Moonlift grammar position and checked per element.

```lua
local params = moon.params {
    {"a", moon.i32},
    {"b", moon.i32},
}

local fields = moon.fields {
    {"x", moon.f64},
    {"y", moon.f64},
}

local args = { 20, 22 }
```

```moonlift
func add(@{params...}): i32
    return a + b
end

struct Point
    @{fields...}
end

return add(@{args...})
```

The parser supplies commas/newlines/field separators. Do not put separator text
in Lua values.

### 16.3 Dynamic statement bodies

Function and region bodies are statement lists. Write them as `moon.stmts[[]]`
quotes:

```lua
local body = moon.stmts [[
    let y: i32 = x + 1
    return y * 2
]]
```

For bodies that need Lua iteration, build the quote string or use `@{}`:

```lua
-- Generate N accumulator additions via string concatenation
local body_src = "let acc0: i32 = 0\n"
for i = 1, 4 do
    body_src = body_src .. "let acc" .. i .. ": i32 = acc" .. (i - 1) .. " + " .. i .. "\n"
end
body_src = body_src .. "return acc4 + x\n"
local body = moon.stmts([[@{body_src}]], { body_src = body_src })
```

Or construct the params/body using the `.mlua` carrier model with `@{}` spread:

```lua
-- In .mlua:
local generated = moon.stmts [[
    let y: i32 = x + 1
    return y * 2
]]
```

```moonlift
func f(x: i32): i32
    @{generated...}
end
```

### 16.4 Generated data declarations

Structs, unions, params, and callable types are all list-spliceable:

```lua
local fields = moon.fields {}
for i = 0, N - 1 do
    fields[#fields + 1] = {name="lane" .. i, type=moon.f32}
end

local variants = moon.variants {
    {"ok", moon.i32},
    {"err", moon.i32},
}
```

```moonlift
local VecN = struct
    @{fields...}
end

local Result = union
    @{variants...}
end
```

When returning a named multiline union, the name is explicit:

```moonlift
return union Result
    @{variants...}
end
```

Anonymous unions still work when the first token is a variant:

```moonlift
return union ok(i32) | err(i32) end
```

### 16.5 Generated region interfaces

Region fragments are especially good metaprogramming targets because their
interfaces are typed control contracts.

```lua
local params = moon.params {
    {name="p", type=moon.ptr(moon.u8)},
    {"n", moon.i32},
}

local exits = {
    {name="hit",  params={ {name="pos", type=moon.i32} }},
    {name="miss", params={ {name="pos", type=moon.i32} }},
}
```

```moonlift
return region scan(@{params...}; @{exits...})
entry loop(i: i32 = 0)
    if i >= n then jump miss(pos = i) end
    jump loop(i = i + 1)
end
end
```

Spliced runtime params are visible by name in the region body. Spliced
continuations are visible as jump targets.

Entry/block/continuation parameter lists and additional blocks can also be
spread. Use `moon.blocks{...}` for generated blocks:

```lua
local blocks = moon.blocks {
    { label = "done", params = { {name="v", type=moon.i32} },
      body = moon.stmts [[ yield v ]] },
}
```

```moonlift
entry start(@{entry_params...})
    jump done(v = 42)
end
@{blocks...}
```

### 16.6 Fragment factories

The common pattern for specialization is a Lua factory that returns a typed
fragment:

```lua
local function expect_byte(name, byte, code)
    return moon.region [[
        @{name}(p: ptr(u8), n: i32, pos: i32;
                ok(next: i32) | err(pos: i32, code: i32))
        entry start()
            if pos >= n then jump err(pos = pos, code = @{code}) end
            if as(i32, p[pos]) == @{byte} then jump ok(next = pos + 1) end
            jump err(pos = pos, code = @{code})
        end
        end
    ]], { name = name, byte = byte, code = code }
end

local expect_A = expect_byte("expect_A", 65, 10)
local expect_B = expect_byte("expect_B", 66, 20)
```

Inside `.mlua` files, constants (integers, booleans) can be spliced directly
via `@{expr}`:

```moonlift
-- Inside .mlua, @{byte} splices the Lua number 65 into the expression position.
```

Use fragments with `emit`; do not generate call wrappers for zero-cost control
composition:

```moonlift
emit @{expect_A}(p, n, 0; ok = got_A, err = bad)
```

### 16.7 Expression construction

For generated expressions, use `moon.expr[[]]`:

```lua
local e = moon.expr [[x + 1]]
```

Expression value operators remain available for generated expression values;
use quoted source for named leaves instead of a separate reference API:

```lua
local x = moon.expr [[x]]
local e = x + 1
```

```moonlift
return @{e}
```

When code needs to refer to an outer source binding, prefer writing the name in
source or binding a quoted expression value:

```lua
local body = moon.stmts [[ return x + 1 ]]
local body_with_binding = moon.stmts { x = moon.expr [[x]] } [[ return @{x} + 1 ]]
```

### 16.8 Names and hygiene

Moonlift name splices replace whole tokens only:

```moonlift
func @{generated_name}(x: i32): i32
    return x
end
```

Partial token splicing is intentionally unsupported:

```moonlift
-- Not supported:
func prefix_@{tag}(x: i32): i32 ... end
```

Build the complete name in Lua:

```lua
local generated_name = "prefix_" .. tag
```

### 16.9 Composition recipes

**Generate an unrolled body (via .mlua spread):**

```lua
-- In .mlua:
local body = moon.stmts { xs = moon.ptr(moon.i32) } [[
    let acc0: i32 = xs[0]
    let acc1: i32 = acc0 + xs[1]
    let acc2: i32 = acc1 + xs[2]
    return acc2
]]
```

```moonlift
func sum3(xs: ptr(i32)): i32
    @{body...}
end
```

**Generate a family of fragments:**

```lua
local scanners = {}
for _, spec in ipairs(specs) do
    scanners[#scanners + 1] = expect_byte(spec.name, spec.byte, spec.err)
end
```

**Generate a packed type and functions over it:**

```lua
local fields = moon.fields {}
local params = {}
for i = 1, N do
    fields[#fields + 1] = {name="v" .. i, type=moon.i32}
    params[#params + 1] = {name="x" .. i, type=moon.i32}
end
```

```moonlift
local Pack = struct
    @{fields...}
end

func make_pack(@{params...}): Pack
    -- body may be source-shaped or produced by moon.stmts[[]]
end
```

### 16.10 Anti-patterns

Avoid these unless deliberately escaping:

- concatenating whole Moonlift functions as strings;
- encoding types/control flow in string names;
- generating comma-separated text in Lua;
- keeping semantic compiler state in Lua side tables instead of ASDL values;
- using function calls where a region `emit` is the intended zero-cost control
  composition.

Prefer these instead:

- Lua arrays + `@{xs...}` for repeated syntax;
- `moon.stmts[[]]` for generated bodies;
- `moon.expr[[]]` for generated expressions;
- fragment factories + `emit` for reusable control;
- modules/types/functions as explicit host values.
## 17. View and host ABI semantics

### 17.1 Canonical view descriptor

```c
typedef struct MoonView_T {
    T* data;         // pointer to first element
    intptr_t len;    // number of elements
    intptr_t stride; // stride in elements (1 = contiguous)
} MoonView_T;
```

All three fields are present in the internal ABI. When a view is passed to
or from C code through host/API exposure, the ABI depends on the target's
policy:

- **`descriptor` policy:** passes the full three-field descriptor as a struct
  (by value or by pointer depending on target platform ABI).
- **`data_len_stride` policy:** passes or receives three separate arguments
  (data pointer, length, stride).
- **`pointer` policy:** passes only the data pointer (for single-element
  pointer semantics).

### 17.2 Indexing

```text
element_address(i) = data + i * stride * sizeof(T)
```

For contiguous views (`stride = 1`), this simplifies to standard C array
indexing: `data[i]`.

### 17.3 Windowing

```text
windowed_data    = data + start * stride * sizeof(T)
windowed_len     = requested_len
windowed_stride  = stride
```

Windowing does not copy data. It creates a new view descriptor pointing
to a subrange of the original view.

### 17.4 Lua proxy semantics

Lua proxies are exposure/access facets of Moonlift views and pointers. They
are generated by the host access plan phase and use LuaJIT FFI for zero-copy
access where possible. Proxy/exposure declarations are configured through the
host APIs, not Moonlift source syntax.

---

## 18. Vectorization and facts

Moonlift vectorization is fact-driven. The source language provides typed
control and contracts; phases decide whether vectorization applies.

### 18.1 Vectorization fact pipeline

```text
source control region
  → counted-loop facts (block params + backedges)
  → memory base/access/store facts
  → alias/dependence facts
  → bounds obligations and decisions
  → target feature facts (SIMD capabilities)
  → vector kernel plan
  → explicit reject for unsupported shapes
```

### 18.2 Canonical counted shape

The vectorizer recognizes this pattern:

```moonlift
block loop(i: index = 0, acc: i32 = 0)
    if i >= n then
        yield acc
    end
    -- body with memory accesses indexed by i
    jump loop(i = i + 1, acc = acc + ...)
end
```

The fact phase identifies:
- `i` as the induction variable (monotonically incrementing by 1)
- `n` as the trip count upper bound
- `acc` as the reduction accumulator
- Memory accesses with stride patterns

### 18.3 Vector types

Vector types are represented as `BackVec` with an element scalar type and
lane count (must be power of two ≥ 2):

```text
BackVec { elem: i32, lanes: 4 }    -- 4 x i32 = 128-bit SSE/NEON vector
BackVec { elem: f64, lanes: 2 }    -- 2 x f64 = 128-bit vector
BackVec { elem: i32, lanes: 8 }    -- 8 x i32 = 256-bit AVX2 vector
```

### 18.4 Vector kernel plan

The vector kernel planner consumes counted-loop facts and memory access
facts, then produces a vector schedule:

- **Stride analysis:** determines if memory accesses have strides compatible
  with vector loads/stores (contiguous, strided, or gather/scatter).
- **Lane count selection:** chooses the optimal SIMD width based on target
  features and trip count.
- **Epilogue handling:** generates scalar remainder loop for trip counts not
  divisible by the vector width.
- **Reduction lowering:** scalar reductions are accumulated in a vector
  register and horizontally reduced at loop exit.

### 18.5 Explicit rejects

Vectorization produces explicit rejects for unsupported shapes, including:
- Non-affine induction variables
- Loop-carried dependencies that prevent vectorization
- Memory access patterns that require gather/scatter on targets without support
- Mixed-precision operations without vector support
- Control flow divergence within the loop body

---

## 19. Error and diagnostic model

Moonlift errors are structured, typed, and span-resolved. Every error condition
in every compiler phase produces a stable E0xxx error code through a
domain-specific **explainer** function. Explainers are co-located with the
phase that produces the error — a typecheck explainer knows about site strings
and type names, a backend explainer knows about the provenance map and entity IDs.

### 19.1 Error codes

| Code range | Phase | Examples |
|---|---|---|
| E0101–E0103 | Parse | Unexpected token, unterminated construct, missing keyword |
| E0201–E0203 | Name resolution | Unresolved name, unresolved path, duplicate name |
| E0301–E0305 | Type checking | Type mismatch, not callable, invalid operator, arg count |
| E0401–E0407 | Control flow | Unterminated block, missing jump target, yield outside region |
| E0501–E0506 | Host declarations | Duplicate field, invalid packed align, boundary bool |
| E0601–E0603 | Backend validation | Missing definition, duplicate definition, order violation |
| E0701–E0703 | Splice/metaprogramming | Splice type mismatch, missing fill, splice eval error |
| E0801–E0804 | Open/fragment expansion | Unfilled slot, unexpanded fragment use |
| E0901–E0905 | Link planning | Missing input, tool unavailable, command failed |
| E1001–E1005 | Vectorization | Loop not vectorized, dependence, target shape |
| E1101–E1105 | Source text apply | Wrong document, stale version, overlapping ranges |

### 19.2 Error pipeline

Errors flow through a multi-stage pipeline:

```
compiler phase  → collector:emit(issue, phase)  → ResolvedIssue
  → CascadeFilter (suppresses cascading errors from unresolved names)
  → phase explainer (constructs ErrorReport from ASDL issue)
  → present_terminal or present_lsp
```

Every issue has a **non-nil source span** (enforced by the collector). Spans are
resolved by static per-phase span resolvers that use anchor indices, provenance
maps, or offset-to-line conversions depending on the phase.

### 19.3 Terminal output

```
ERROR[E0301]: type mismatch
  ┌─ file.mlua:2:9
   1 │ func main(): i32
   2 │     let x: i32 = "hello"
     │         ^
   3 │     return x
   4 │ end

  = note: the initializer has type `ptr(u8)`, but the variable is declared as `i32`
```

- Color is disabled by default; set `MOONLIGHT_COLOR=1` or `CLICOLOR_FORCE=1`
- Notes use `= note:` prefix (in blue, if color enabled)
- Suggestions use `= help:` prefix (in green)
- Source context shows 3 lines before/after the error
- Underline uses `^^^` for primary, `~~~` for secondary spans

### 19.4 LSP diagnostics

Each ErrorReport maps to an LSP Diagnostic with:
- Primary span → `range`
- Secondary spans → `relatedInformation`
- Notes and suggestions → concatenated in `message`
- Code → `code` field for IDE filtering

### 19.5 Cascade suppression

When an unresolved name causes downstream type errors (void-typed expressions),
the CascadeFilter suppresses the cascading errors. The user sees only the root
cause: `"unresolved name 'foo'"`, not the 47 type mismatches it causes.

---

## 20. Intrinsics

Intrinsic operations are currently a backend/builder API concern, not dedicated
Moonlift source syntax. At the parser level names such as `popcount`, `sqrt`,
`trap`, and `assume` are ordinary calls. If an intrinsic is needed, construct it
through the Lua builder/ASDL API or provide a normal function binding.

---

## 21. Memory Management Convention

Moonlift's raw pointer and view operations are intentionally low-level. They do
not, by themselves, express ownership, lifetimes, cleanup, arena reset policy,
resource close policy, or stale-handle behavior. Those facts belong in the
ordinary product forest and protocol graph.

The convention is:

```text
Products own bytes.
Handles name durable identity.
Handle facts name domain and target.
Regions control access.
Leases embody temporary access.
Protocols name failure.
```

There is no separate memory DSL or memory API. A memory-sensitive subsystem
declares its owners, handles, protocols, and regions directly. The design
doctrine lives in Chapter 22 of [`THE_MOONLIFT_DESIGN_BIBLE.md`](THE_MOONLIFT_DESIGN_BIBLE.md).

### 21.1 Design Method

Design memory from the outside inward:

1. Name the owner product.
2. Decide whether access needs a stable handle.
3. If the reference is a handle, declare its `domain Store` and `target Item`.
4. Name the access region.
5. Name every failure or alternate outcome in the region protocol.
6. Put successful access in the continuation payload as `lease ptr(T)` or
   `lease view(T)`.
7. Keep borrowed pointers/views inside the region extent or pass them into
   sealed kernels.
8. Name lifetime changes as `reset_*`, `publish_*`, `retire_*`, or `close_*`
   regions.

Use the smallest model that fits:

| Situation | Model |
|---|---|
| Same lifetime as parent | Field in the parent product |
| Stable references, reuse, stale handles | `handle Ref domain *Store target Item`, `borrow_*` / `resolve_*` |
| Temporary frame/block memory | `*Scratch` / arena, `reset_*` |
| Host buffer for one call | Boundary region with views/pointers |
| Version becomes visible | `publish_*` |
| Old version is removed | `retire_*` |
| External resource released | `close_*` |

Inline region signatures are the default. Name separate request/result products
only when those products are real values that are stored, passed around, or
reused by more than one region.

### 21.2 Stable Stores And Borrows

Use a typed handle when a reference can outlive a raw pointer. A handle is a
nominal, opaque scalar identity; the store owns location, liveness, generations,
free lists, compaction, and destruction policy. A handle declaration may carry
explicit metadata tying that identity to its owning domain and logical target:

```moonlift
struct VoicePool
    states: ptr(VoiceState),
    generations: ptr(u16),
    cap: index,
    active_count: index,
    free_head: u32,
end

struct VoiceState
    phase: f32,
    gain: f32,
end

handle Voice : u32 invalid 0
    domain VoicePool
    target VoiceState
end

region borrow_voice_state(pool: ptr(VoicePool), voice: Voice;
    borrowed(state: lease(pool) ptr(VoiceState))
  | stale_ref(voice: Voice)
  | already_free(voice: Voice)) end
```

A handle may be copied, stored, passed, returned, and serialized. It cannot be
dereferenced or used for arithmetic, and it does not implicitly cast to its
representation. Store implementations that must pack or unpack the scalar
representation use the explicit trusted boundary operations `repr(handle_value)`
and `Handle.from_repr(raw)`.

`domain` and `target` are not dereference rules. They are ASDL facts on the
handle declaration:

```text
TypeDeclHandle(
  name = Voice,
  repr = u32,
  invalid = 0,
  facts = {
    HandleDomain(VoicePool),
    HandleTarget(VoiceState),
  })
```

The checker uses these facts at resolver signatures. A region that accepts a
`Voice` and grants `lease ptr(VoiceState)` must also take access to the matching
`VoicePool` domain. A region that accepts `Voice` and grants `lease ptr(Texture)`
is rejected. The handle remains durable identity; only the successful
continuation grants temporary memory access.

A lease is the temporary access fact produced by the store. A lease may access
memory, but it must not become durable identity: no storing it in long-lived
memory, no returning it as an ordinary pointer, and no hiding it behind a raw
pointer field. `lease(pool) ptr(T)` associates the lease with the `pool`
parameter for invalidation checks; unqualified `lease ptr(T)` is conservative and
may be treated as originating from any store.

Store functions declare invalidation effects on pointer/view parameters:

```moonlift
func read_voice_count(readonly pool: ptr(VoicePool)): index
func update_voice_metadata(preserve pool: ptr(VoicePool))
func destroy_voice(invalidate pool: ptr(VoicePool), voice: Voice)
```

`readonly` and `preserve` keep live leases valid. `invalidate` may free, move,
compact, or reuse storage. An unannotated mutable pointer/view parameter is
conservatively treated as invalidating. A call that may invalidate `pool` is
rejected while a `lease(pool) ...` value is live.

Inline region signatures are the default memory boundary. Name a separate
request or result product only when the value is stored, passed around, or reused
by more than one region.

### 21.3 Arenas, Scratch, And Reset

```moonlift
struct ByteArena
    data: ptr(u8),
    cap: index,
    used: index,
end

struct RenderScratch
    arena: ByteArena,
    voice_l: view(f32),
    voice_r: view(f32),
end

region reset_render_scratch(scratch: ptr(RenderScratch), shape: BlockShape;
    reset
  | bad_buffer
  | wrong_thread) end
```

Arena allocation is grouped ownership. If an object must be individually
retired, use a pool/store protocol instead.

### 21.4 Host-Owned Buffers

Host-owned buffers are borrowed at ABI boundaries and passed as views or
pointers into internal regions:

```moonlift
region enter_render_memory(synth: ptr(Synth),
                           events: view(HostEvent),
                           scratch: ptr(RenderScratch),
                           out_l: view(f32),
                           out_r: view(f32);
    ready(program: ptr(PreparedProgram),
          storage: ptr(SynthStorage),
          scratch: ptr(RenderScratch),
          events: view(HostEvent),
          out_l: view(f32),
          out_r: view(f32))
  | no_program
  | bad_buffer
  | bad_state(code: i32)) end
```

Do not cache host-owned raw pointers or views globally.

### 21.5 Cleanup And Publication

Close, reset, publish, retire, and generation bump are named operations with
named outcomes. There are no semantic destructors:

```moonlift
region close_synth_storage(synth: ptr(Synth);
    closed
  | already_closed
  | audio_busy) end
```

### 21.6 Review Laws

1. Every memory object has exactly one owner product.
2. The model shape is chosen before pointer fields are written.
3. Stable references are typed handles, not raw pointers.
4. Meaningful failure is a protocol, not a null pointer or status code.
5. Raw pointer/view access has a visible lifetime boundary.
6. Cleanup and publication are explicit protocols.
7. Hot kernels receive already-borrowed pointers/views and do not discover
   ownership themselves.

---

## 22. Memory operations

### 22.1 Load and store

In Moonlift source, memory operations use pointer dereference and assignment
syntax:

```moonlift
let value: i32 = *p           -- load i32 from pointer p
*p = 42                       -- store i32 to pointer p
xs[i] = value                 -- store through view/pointer indexing
```

In the builder API:

```lua
moon.load(addr, T)            -- load T from address
moon.store(addr, value)       -- store value to address
```

### 22.2 Memory copy and set

```moonlift
-- In ASDL construction:
moon.memcpy(dst, src, len)    -- copy len bytes from src to dst
moon.memset(dst, byte, len)   -- set len bytes at dst to byte value
```

Both `memcpy` and `memset` take pointer arguments and a length argument.
The length is in bytes, not elements.

### 22.3 Memory access facts

Every load and store carries memory access facts:

| Fact | Values | Meaning |
|---|---|---|
| Alignment | `Unknown`, `Known(N)`, `AtLeast(N)`, `Assumed(N)` | Pointer alignment guarantee |
| Dereference size | `Unknown`, `Bytes(N)`, `Assumed(N)` | Known accessible bytes at pointer |
| Trap behavior | `MayTrap`, `NonTrapping`, `Checked` | Whether access can trap |
| Motion | `MayNotMove`, `CanMove` | Whether the access can be reordered |
| Access mode | `Read`, `Write`, `ReadWrite` | Direction of the access |

These facts are consumed by the optimizer for bounds-check elimination,
alias analysis, and instruction scheduling.

### 22.4 Atomic memory operations

Moonlift atomics are explicit memory commands, not hidden effects on ordinary
loads/stores.  The current backend-supported ordering is `seq_cst`, matching
Cranelift's atomic operations and fence semantics.

Source forms:

```moonlift
let x: i32 = atomic_load(i32, p)
atomic_store(i32, p, 42)
let old: i32 = atomic_fetch_add(i32, p, 1)
let old2: i32 = atomic_fetch_sub(i32, p, 1)
let mask_old: i32 = atomic_fetch_and(i32, p, mask)
let bits_old: i32 = atomic_fetch_or(i32, p, bits)
let xor_old: i32 = atomic_fetch_xor(i32, p, bits)
let swapped: i32 = atomic_xchg(i32, p, value)
let seen: i32 = atomic_cas(i32, p, expected, replacement)
atomic_fence()
```

All atomic read-modify-write operations return the old value. `atomic_cas`
returns the old value regardless of success; compare it with `expected` to test
whether the replacement happened.

Supported atomic load/store/CAS value types are integer-like scalar types,
`bool`, `index`, and pointers. Atomic arithmetic/bitwise RMW operations are for
integer-like values; `atomic_xchg` also supports `bool` and pointers.
Floating-point atomics are not part of the Moonlift source contract. Lua
factories should generate monomorphic variants exactly as with ordinary memory
kernels.

Builder API equivalents:

```lua
moon.atomic_load(addr, T)
moon.atomic_store(addr, value, T)
moon.atomic_rmw("add", addr, value, T)   -- add/sub/band/bor/bxor/xchg
moon.atomic_cas(addr, expected, replacement, T)
moon.atomic_fence()
```

In ASDL/backend form these lower to explicit `CmdAtomicLoad`,
`CmdAtomicStore`, `CmdAtomicRmw`, `CmdAtomicCas`, and `CmdAtomicFence` commands
with `BackAtomicSeqCst` ordering and ordinary `BackMemoryInfo` facts.

---

## 23. Complete examples

### 23.1 Typed dispatch over bytes

```moonlift
region parse_digit(p: ptr(u8), n: i32, pos: i32;
                   ok(next: i32, value: i32),
                   err(pos: i32, code: i32))
entry start()
    if pos >= n then jump err(pos = pos, code = 1) end
    let c: i32 = as(i32, p[pos])
    if c >= 48 then
        if c <= 57 then
            jump ok(next = pos + 1, value = c - 48)
        end
    end
    jump err(pos = pos, code = 2)
end
end
```

### 23.2 Switch + emit dispatch

```moonlift
func classify(p: ptr(u8), n: i32): i32
    return region: i32
    entry start()
        if n <= 0 then yield -1 end
        switch as(i32, p[0]) do
        case 65 then
            emit parse_digit(p, n, 1; ok = got_A, err = bad)
        case 66 then
            emit parse_digit(p, n, 1; ok = got_B, err = bad)
        default then
            yield -9
        end
    end
    block got_A(next: i32, value: i32)
        yield 1000 + value
    end
    block got_B(next: i32, value: i32)
        yield 2000 + value
    end
    block bad(pos: i32, code: i32)
        yield 0 - code
    end
    end
end
```

### 23.3 Lua-generated monomorphic fragments

```lua
local function expect_byte(tag, byte, err_code)
    local name = "expect_" .. tag
    return region @{name}(p: ptr(u8), n: i32, pos: i32;
        ok(next: i32),
        err(pos: i32, code: i32))
    entry start()
        if pos >= n then jump err(pos = pos, code = @{err_code}) end
        if as(i32, p[pos]) == @{byte} then
            jump ok(next = pos + 1)
        end
        jump err(pos = pos, code = @{err_code})
    end
    end
end

local expect_A = expect_byte("A", 65, 10)
local expect_B = expect_byte("B", 66, 20)
local expect_semicolon = expect_byte("semicolon", 59, 30)
```

### 23.4 Hosted struct declaration

```moonlift
struct User
    id: i32
    age: i32
    active: bool
end
```

Host exposure and proxy methods are configured from Lua host APIs.

### 23.5 Multi-block state machine

```moonlift
func scan_byte(p: ptr(u8), n: i32, target: u8): i32
    return region: i32
    entry start()
        jump loop(i = 0)
    end
    block loop(i: i32)
        if i >= n then yield -1 end
        if p[i] == target then yield i end
        jump loop(i = i + 1)
    end
    end
end
```

### 23.6 Counted sum with region fragment

```moonlift
region sum_range(xs: view(i32), start: index, len: index;
                 done(total: i32))
entry loop(i: index = 0, acc: i32 = 0)
    if i >= len then jump done(total = acc) end
    jump loop(i = i + 1, acc = acc + xs[start + i])
end
end

func sum_first_n(xs: view(i32), n: index): i32
    return region: i32
    entry start()
        emit sum_range(xs, 0, n; done = out)
    end
    block out(total: i32)
        yield total
    end
    end
end
```

### 23.7 Phase dispatch (tagged union switch)

```moonlift
region classify_uncached(ctx: ptr(i32), tag: i32;
    value(delta: i32))
entry start()
    switch tag do
    case 0 then jump value(delta = 1)     -- OpConst: push
    case 1 then jump value(delta = 0 - 1) -- OpAdd:   pop2 push1
    case 2 then jump value(delta = 0 - 1) -- OpMul
    case 3 then jump value(delta = 0 - 1) -- OpSub
    case 4 then jump value(delta = 0)     -- OpNeg
    case 5 then jump value(delta = 1)     -- OpDup
    case 6 then jump value(delta = 0 - 1) -- OpDrop
    default then jump value(delta = 0)
    end
end
end
```

---

## 24. Implementation/layer map

Important implementation homes (all under `lua/moonlift/`):

```text
-- Parsing
parse.lua                       unified lexer/parser and hosted island scanner
mlua_document_analysis.lua      editor/LSP document analysis over hosted islands

-- Host bridge
mlua_run.lua                    LuaJIT hosted island runner / antiquote bridge (backward compat; prefer require("moonlift"))
host.lua                        quoting and table builder API entry point
host_session.lua                session management
host_module_values.lua          module value construction
host_func_values.lua            function value construction
host_region_values.lua          region value construction
host_expr_values.lua            expression value construction
host_type_values.lua            type value construction
host_struct_values.lua          struct value construction
host_decl_values.lua            declaration value construction
host_decl_parse.lua             declaration parsing
host_decl_validate.lua          declaration validation
host_fragment_values.lua        fragment value construction
host_template_values.lua        template value construction
host_place_values.lua           place value construction
host_issue_values.lua           issue/diagnostic value construction

-- Type system
type_classify.lua               type classification phase
type_size_align.lua             size and alignment computation
type_abi_classify.lua           ABI classification
type_ref_classify_surface.lua   reference type classification
type_to_back_scalar.lua         scalar type → backend scalar
type_func_abi_plan.lua          function ABI planning

-- Tree analysis and MoonCode lowering
tree_typecheck.lua              typecheck/name resolution
tree_expr_type.lua              expression type resolution
tree_stmt_type.lua              statement type resolution
tree_place_type.lua             place type resolution
tree_module_type.lua            module-level type resolution
tree_field_resolve.lua          field/access resolution
tree_control_facts.lua          control validation facts
tree_contract_facts.lua         contract validation facts
tree_to_code.lua                tree → normalized MoonCode
code_validate.lua               MoonCode validation
code_to_back.lua                MoonCode → flat backend commands
code_to_c.lua                   MoonCode → C backend IR
open_expand.lua                 slot/fill/fragment expansion
open_facts.lua                  open/slot validation
open_validate.lua               open region validation
open_rewrite.lua                open region rewriting

-- Semantic phases
sem_call_decide.lua             call resolution
sem_const_eval.lua              constant evaluation
sem_switch_decide.lua           switch resolution
sem_layout_resolve.lua          layout resolution

-- Backend
back_validate.lua               backend validation facts
back_jit.lua                    JIT compilation (Rust FFI)
back_object.lua                 object file emission
back_program.lua                backend program construction
back_command_tape.lua           command tape construction
back_diagnostics.lua            backend diagnostic facts
back_inspect.lua                backend IR inspection
back_target_model.lua           target feature model

-- Kernel fact tower
code_flow_facts.lua             CFG/counting facts over MoonCode
code_mem_facts.lua              memory stream facts over MoonCode
code_kernel_plan.lua            KernelBodyCounted semantic planning
kernel_validate.lua             kernel semantic validation
code_lower_plan.lua             choose Code vs whole-function Kernel lowering
lower_to_back.lua               LowerModule → backend commands
lower_to_c.lua                  LowerModule → C projection policy

-- Linker
link_target_model.lua           linker target model
link_plan_validate.lua          link plan validation
link_command_plan.lua           link command generation
link_execute.lua                system linker execution

-- Host ABI
host_layout_facts.lua           struct layout facts
host_layout_resolve.lua         layout resolution
host_view_abi_plan.lua          view ABI planning
host_access_plan.lua            host access path planning
host_c_emit_plan.lua            C code emission
host_lua_ffi_emit_plan.lua      Lua FFI binding emission
host_terra_emit_plan.lua        Terra binding emission
host_arena_abi.lua              arena ABI bridge
host_arena_native.lua           native arena support
moonlift_sar.lua                substrate LuaJIT scope/arena/resource mechanics
buffer_view.lua                 buffer view utilities

-- PVM framework
pvm.lua                         PVM context, phases, context
triplet.lua                     triplet iterator algebra
asdl.lua                        ASDL main module
asdl_model.lua                  ASDL value model
asdl_parser.lua                 ASDL text parser
asdl_lexer.lua                  ASDL lexer
asdl_context.lua                ASDL context (interning)
asdl_builder.lua                ASDL builder API

-- PVM surface (schema → values)
pvm_surface_model.lua           PVM surface model
pvm_surface_builder.lua         PVM surface builder
pvm_surface_region_values.lua   region value lowering
pvm_surface_schema_values.lua   schema value lowering
pvm_surface_union_values.lua    union value lowering
pvm_surface_cache_values.lua    cache value lowering

-- LSP / Editor
editor_diagnostic_facts.lua     diagnostic fact extraction
editor_completion_items.lua     completion item generation
editor_completion_context.lua   completion context
editor_hover.lua                hover information
editor_definition.lua           go-to-definition
editor_references.lua           find references
editor_rename.lua               rename symbol
editor_semantic_tokens.lua      semantic token generation
editor_signature_help.lua       signature help
editor_inlay_hints.lua          inlay hints
editor_folding_ranges.lua       folding range generation
editor_code_actions.lua         code action generation
editor_document_highlight.lua   document highlight
editor_selection_ranges.lua     selection range expansion
editor_symbol_facts.lua         document symbol facts
editor_binding_facts.lua        binding resolution
editor_binding_scope_facts.lua  scope resolution
editor_workspace_apply.lua      workspace edits
editor_transition.lua           open/edit/close transitions
editor_subject_at.lua           subject resolution at position

-- LSP protocol
lsp_capabilities.lua            LSP capabilities
lsp_payload_adapt.lua           payload adaptation
rpc_lsp_decode.lua              LSP message decoding
rpc_lsp_encode.lua              LSP message encoding
rpc_json_decode.lua             JSON-RPC decoding
rpc_json_encode.lua             JSON-RPC encoding
rpc_out_commands.lua            outgoing command buffer
rpc_stdio_loop.lua              stdio I/O loop

-- Schema (clean schema source of truth)
schema/init.lua                 schema module index/loader
schema/core.asdl                MoonCore schema
schema/type.asdl                MoonType schema
schema/tree.asdl                MoonTree schema
schema/sem.asdl                 MoonSem schema
schema/back.asdl                MoonBack schema
schema/link.asdl                MoonLink schema
schema/host.asdl                MoonHost schema
schema/open.asdl                MoonOpen schema
schema/bind.asdl                MoonBind schema
schema/mlua.asdl                MoonMlua schema
schema/editor.asdl              MoonEditor schema
schema/lsp.asdl                 MoonLsp schema
schema/rpc.asdl                 MoonRpc schema
schema/source.asdl              MoonSource schema
schema/pvm_surface.asdl         MoonPvmSurface schema
```

---

## 25. Summary doctrine

Moonlift source is small on purpose:

```text
monomorphic typed data
+ typed regions
+ explicit continuation exits
+ switch/emit/jump composition
+ semantic as(T, value) conversion
```

Lua supplies all genericity. Memory management is ordinary Moonlift design:
owner products, typed handles, request products, protocol sums, and access
regions. Memory failure is a named outcome, and raw access is a dynamic extent.

The backend consumes flat facts and commands — `BackCmd` values, not nested
IR trees.

No hidden generic source layer is needed because Moonlift's control language
is already the low-level composition model:

```text
blocks are continuation points
jumps are state transitions
emits are compile-time graph splicing
yields are region exits
switches are explicit dispatch
```

Everything the machine needs to know is explicit in ASDL. Everything the
programmer needs to abstract is expressed in Lua. The host may be poetic; the
generated machine must be inspectable.
