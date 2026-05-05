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
15. [Lua builder API reference](#15-lua-builder-api-reference)
16. [View and host ABI semantics](#16-view-and-host-abi-semantics)
17. [Vectorization and facts](#17-vectorization-and-facts)
18. [Error and diagnostic model](#18-error-and-diagnostic-model)
19. [Intrinsics](#19-intrinsics)
20. [Memory operations](#20-memory-operations)
21. [Complete examples](#21-complete-examples)
22. [Implementation/layer map](#22-implementationlayer-map)
23. [Summary doctrine](#23-summary-doctrine)

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
- emitting multiple monomorphic variants from a single parameterized factory

Lua genericity is real genericity. Moonlift source genericity does not exist.
When you want a function parameterized by type, you write a Lua function that
returns a Moonlift function specialized to that type.

### 1.2 Hosted declaration layer

Inside `.mlua`, Moonlift recognizes top-level hosted islands:

- `struct ... end`
- `expose Name: subject` or `expose Name: subject ... end`
- `func ... end`
- `module ... end`
- `region ... entry ... end ... end`
- `expr ... -> T ... end`
- `type Name = ... end`

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
local function make_id(T)
    return expr id_for_@{T}(x: @{T}) -> @{T}
        x
    end
end
```

Moonlift receives only the monomorphic result with all types resolved.

### 2.2 No angle-bracket type argument syntax

Moonlift source does not use angle brackets for type arguments or casts.
This applies everywhere: declarations, calls, conversions, and intrinsics.

The single source-level conversion form is:

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
operation (extend, truncate, float conversion, bitcast, or identity) from the
source and target scalar types. All combinations of supported scalars are
defined. Invalid combinations (e.g. `as(ptr(u8), f64_value)`) are rejected at
typecheck time.

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

A `.mlua` file is standard LuaJIT Lua with Moonlift hosted islands embedded as
Lua strings. It is loaded by the host quote bridge:

```lua
local Host = require("moonlift.host_quote")
local chunk = Host.loadfile("file.mlua")
local result = chunk()
```

From the repo runner:

```bash
luajit run_mlua.lua file.mlua
```

The `.mlua` file can return a compiled module, a function, or any Lua value.
If it returns a table with a `:compile()` method, `run_mlua.lua` attempts to
call an exported `main`, `run`, or `test` function.

### 3.2 Moonlift source strings

Moonlift modules, functions, and regions can also be built from source strings
through `host_quote` or parsed directly:

```lua
local parse = require("moonlift.mlua_parse")
local result = parse.parse(source, "@source_name")
```

The parser returns a `MoonTree.Module` ASDL value with attached issues.

### 3.3 Lua builder API (two surfaces)

Moonlift provides two builder APIs, both of which produce the same ASDL values
consumed by the same PVM phases. Neither is a separate compiler IR.

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
generation, session management, and JIT compilation.

Both APIs construct identical ASDL values. Choose based on preference and task.

### 3.4 Command-line tools

| Command | Purpose |
|---|---|
| `luajit run_mlua.lua file.mlua` | JIT and run a `.mlua` file |
| `luajit emit_object.lua input.mlua -o output.o` | Compile to relocatable object file |
| `luajit emit_shared.lua input.mlua -o liboutput.so` | Compile to shared library |
| `luajit lsp.lua` | Start the Moonlift LSP server |

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

**Declaration and module keywords:**
```text
export  extern  func  const  static  import  type
struct  union   enum  view
```

**Pointer and access modifiers:**
```text
noalias  readonly  writeonly  requires
bounds   window_bounds  disjoint  same_len
```

**Statement keywords:**
```text
let  var  if  then  else  elseif  switch  case  default  do  end
block  control  entry  jump  yield  return  emit  expr
```

**Expression keywords:**
```text
true  false  nil  and  or  not  as  select  len
```

**Scalar type keywords (reserved in type position):**
```text
void  bool
i8  i16  i32  i64
u8  u16  u32  u64
f32  f64
index
```

**Intrinsic keywords (reserved in intrinsic-call position):**
```text
popcount  clz  ctz  rotl  rotr  bswap
fma  sqrt  abs  floor  ceil  trunc_float  round
trap  assume
```

**Hosted boundary aliases (reserved in type position):**
```text
bool8  bool32
bool stored <scalar>
```

**Intentionally NOT reserved:**

These names are intentionally NOT reserved in Moonlift object-language source
and may be used freely as identifiers:

```text
for  while  loop  next  break  continue  over  range  zip  zip_eq
fn  closure  ptr  slice  repr  packed
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

In object-language source, the alternate spelling `&T` is also accepted:

```moonlift
&u8
&i32
&User
```

These are identical at the ASDL level (`MoonType.Ptr`).

Pointer operations:

| Operation | Syntax | Semantics |
|---|---|---|
| Load | `*ptr` or `load(ptr, T)` | Read a `T` from memory |
| Store | `*ptr = value` or `store(ptr, value)` | Write a `T` to memory |
| Address-of | `&place` or `addr_of(place)` | Take address of a place |
| Pointer add | `ptr + offset` | Add element offset to pointer |
| Pointer offset | `ptr_offset(ptr, elem_size, count)` | Byte-level pointer arithmetic |

Pointer types do not carry mutability, nullability, or lifetime information at
the type level. These properties are expressed through parameter modifiers and
`requires` contracts.

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
view_window(base_view, start, len) -- window into existing view
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

### 5.4 Named types

Named types refer to declared structs, unions, enums, or imported type paths:

```moonlift
User              -- locally declared struct
Pairs             -- locally declared struct
MoonCore.Scalar   -- type from imported module (import syntax)
```

Named types are resolved during typechecking against the module's type
declarations and imports. Unresolved names produce type errors.

### 5.5 Struct types

Declared via hosted `struct ... end` blocks or object-level `type Name = struct ... end`:

```moonlift
struct Vec3
    x: f32
    y: f32
    z: f32
end
```

Fields are laid out in declaration order with natural alignment (`repr(c)`
by default). Explicit representation controls packing:

```moonlift
struct Packet repr(packed(1))
    tag: u8
    len: u32
end
```

Supported representations: `repr(c)` (default), `repr(packed(N))` where `N`
is the byte alignment (1, 2, 4, 8, 16).

### 5.6 Enum types

```moonlift
type Color = enum
    red
    green
    blue
end
```

Enum variants are assigned consecutive integer values starting from 0. The
underlying type is `i32` by default. Enums can be used in `switch` statements
and compared with `==` and `~=`.

### 5.7 Union types

Untagged unions:

```moonlift
type Bits = union
    i: i32
    f: f32
end
```

All fields share the same storage. The size is the maximum field size. Field
access performs a bitcast.

### 5.8 Tagged union types

```moonlift
type Result = ok(i32) | err(i32)
```

Tagged unions carry an implicit discriminant tag followed by the variant
payload. The tag is an integer starting from 0 in declaration order. Used
extensively in PVM-LL lowering for phase dispatch.

### 5.9 Hosted boundary storage types

Hosted structs use exposed types plus explicit storage facts to define
FFI-compatible layouts:

```moonlift
active: bool8                    -- 1-byte bool
active: bool32                   -- 4-byte bool (i32-backed)
active: bool stored i32          -- bool stored with i32 representation
```

Bare hosted boundary `bool` storage is intentionally ambiguous and should
be rejected in host boundary structs. Always specify the storage width.

### 5.10 Function and closure types (source syntax)

In type position:

```text
func(i32, i32) -> i32           -- function pointer type
closure(i32) -> i32             -- closure type (function + context)
```

These are used primarily for indirect calls and interface types. The builder
API uses `moon.func_type(params, result)` and `moon.closure_type(params, result)`.

### 5.11 Source-level genericity

There is none. Use Lua to generate specialized concrete types/functions/fragments.

---

## 6. Modules and items

### 6.1 Module syntax

Modules are the top-level compilation unit. Two forms exist:

**Object-language module** (item list without explicit name):

```moonlift
export func add(a: i32, b: i32) -> i32
    return a + b
end

func helper(x: i32) -> i32
    return x * 2
end
```

**Hosted named module** (`.mlua` top-level islands):

```moonlift
module Name
    item*
end
```

A module may contain: functions, externs, consts, statics, type declarations,
regions, and expression fragments. The module name determines the default
symbol prefix for JIT and object emission.

### 6.2 Functions

```moonlift
[export] func name ( param_list? ) [-> type]
    requires_clause*
    stmt*
end
```

Rules:

- Function bodies are always `end`-delimited. Brace-delimited function bodies
  are rejected.
- `export func` is visible to importing modules and produces an exported
  symbol in emitted objects/shared libraries.
- Plain `func` is module-local. The linker may strip unreferenced local
  functions.
- Omitting the result type means `void` return.
- The parameter list may be empty: `func name() -> i32 ... end` or `func name()
  ... end` for void.
- Function parameters are immutable bindings. They cannot be assigned to.

Examples:

```moonlift
export func add(a: i32, b: i32) -> i32
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
```

Parameter modifiers become source contracts. They are consumed by the contract
facts phase and used by vector safety and alias/proof decisions.

| Modifier | Meaning |
|---|---|
| `noalias` | This pointer does not alias any other pointer parameter |
| `readonly` | Memory reachable through this pointer is only read, never written |
| `writeonly` | Memory reachable through this pointer is only written, never read |

Example:

```moonlift
export func sum(readonly noalias xs: ptr(i32), n: i32) -> i32
    block loop(i: index = 0, acc: i32 = 0)
        if i >= n then return acc end
        jump loop(i = i + 1, acc = acc + xs[i])
    end
end
```

Modifiers can be combined. `noalias readonly xs: ptr(T)` means the pointer is
both non-aliasing and the memory it points to is only read.

### 6.4 Extern functions

```moonlift
extern func name ( param_list? ) [-> type]
```

Extern functions declare a C-ABI function with an external symbol. The local
name is the default external symbol name. The symbol can be overridden by a
linker-level symbol policy.

```moonlift
extern func puts(x: ptr(u8)) -> i32
extern func malloc(size: index) -> ptr(u8)
extern func free(p: ptr(u8))
extern func memcpy(dst: ptr(u8), src: ptr(u8), n: index) -> ptr(u8)
```

Extern functions have C calling convention. They are not inlined. Their
signatures must use scalar types, pointers, and views — struct arguments
by value are not supported in extern declarations.

### 6.5 Constants and statics

```moonlift
const answer: i32 = 42
const name_len: index = 256
const scale: f64 = 1.5

static counter: i32 = 0
static buffer: [256]u8 = []u8 { 0, ... }  -- (aggregate init syntax)
```

- `const` creates a compile-time value. Const expressions are evaluated during
  typechecking. Supported const expressions include literals, references to
  other consts, and simple arithmetic.
- `static` creates module-level storage with an initial value. Statics have
  addresses and can be referenced by pointer. Static initializers must be const
  expressions.

### 6.6 Type declarations (object-language)

```moonlift
type Pair = struct
    left: i32
    right: i32
end

type Tag = enum
    A
    B
    C
end

type Bits = union
    i: i32
    f: f32
end

type Result = ok(i32) | err(i32)
```

In `.mlua` hosted syntax, use the top-level `struct`, `enum`, and `union`
declaration forms instead.

### 6.7 Imports

```moonlift
import other_module
```

Imports introduce qualified namespaces. `import other_module` makes
`other_module.TypeName` available in type position. The exact import
resolution mechanism depends on the compilation context (module path,
file system, or programmatic registration).

---

## 7. Hosted declarations

Hosted declarations are `.mlua` top-level islands that create `MoonHost` facts
plus corresponding object-language ASDL where appropriate. They are the primary
way to define types and host-facing interfaces in `.mlua` files.

### 7.1 Structs

```moonlift
struct User
    id: i32
    age: i32
    active: bool32
end
```

Default representation is `repr(c)`. Explicit representation:

```moonlift
struct Packet repr(packed(1))
    tag: u8
    len: u32
end
```

Struct facts produced:
- `HostStructDecl` — structural declaration with fields
- `HostFieldDecl` — per-field type and layout facts
- `HostTypeLayout` — size, alignment, field offsets
- `HostFieldLayout` — per-field offset and access path
- `MoonTree.TypeDeclStruct` — object-language struct type

### 7.2 Field attributes

Field type attributes are suffixes on the field type:

```moonlift
field: i32 readonly
field: ptr(u8) noalias
field: view(i32) mutable
```

| Attribute | Meaning |
|---|---|
| `readonly` | Field is only read in host access paths |
| `writeonly` | Field is only written in host access paths |
| `noalias` | Pointer field does not alias other pointers |
| `mutable` | View/pointer field can be mutated through the host proxy |

### 7.3 Expose declarations

```moonlift
expose UserRef: ptr(User)
expose Users: view(User)
```

Expose declarations name the public host surface first, then the semantic
subject. A one-line declaration means the default Lua + Terra + C facets.

For explicit target control, use the end-delimited form:

```moonlift
expose MutableUserRef: ptr(User)
    lua mutable
end

expose LuaOnlyUsers: view(User)
    lua
end

expose FullExposure: view(Packet)
    lua               -- Lua proxy, default policy
    terra             -- Terra view, default policy
    c proxy           -- C proxy accessor
    moonlift          -- Internal Moonlift view (data,len,stride)
end
```

**Expose targets:**

| Target | Description |
|---|---|
| `lua` | LuaJIT FFI proxy with field accessor methods |
| `terra` | Terra-compatible view/pointer type |
| `c` | C-compatible view/pointer with accessor functions |
| `moonlift` | Internal Moonlift view ABI (data, len, stride) |

**Facet policy words:**

```text
proxy          | typed_record  | buffer_view
descriptor     | pointer       | data_len_stride | expanded_scalars
readonly       | mutable       | interior_mutable
checked        | unchecked
eager_table    | full_copy     | borrowed_view
```

**Default policies per target:**

| Target | ptr default | view default |
|---|---|---|
| `lua` | `proxy readonly checked` | `proxy readonly checked` |
| `c` / `terra` | `pointer readonly unchecked` | `descriptor readonly unchecked` |
| `moonlift` | N/A (raw pointer) | `data_len_stride` (internal ABI) |

### 7.4 Lua-hosted methods

Ordinary Lua method syntax attaches host-side proxy methods to a struct type:

```lua
function User:is_adult()
    return self.age >= 18
end

function User:full_name()
    return self.first .. " " .. self.last
end
```

These are Lua closures over generated proxy accessors. They are recorded as
host accessor facts and can be called on any Lua proxy to a `User` value
(including `ptr(User)` and `view(User)` proxies).

### 7.5 Moonlift-native methods

Moonlift-native methods use `func Type:name` syntax and compile to ordinary
Moonlift object functions with stable generated symbols:

```moonlift
func User:is_active(self: ptr(User)) -> bool
    return self.active
end

func User:set_age(self: ptr(User), new_age: i32)
    self.age = new_age
end
```

The first parameter (`self`) is the receiver. It must be a pointer or view
type. Native methods are recorded as native host accessor facts and can be
called from Lua proxies, C code, or other Moonlift functions.

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
let name: T = expr
var name: T = expr
```

| Binding | Mutability | Semantics |
|---|---|---|
| `let` | Immutable | Value binding. The name is an alias for the value. Cannot be assigned to after initialization. |
| `var` | Mutable | Cell binding. The name refers to a mutable storage location. Can appear on the left side of `=`. |

`let` bindings are SSA-like: they name a value. The backend may reuse the
register or stack slot at its discretion. `var` bindings are always backed
by storage (stack slot or register with spill).

Type annotations are required on `let` and `var` — there is no type inference
for local bindings.

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

In the Lua builder API, the equivalent is:

```lua
block:switch_(value, {
    { key = 0, body = function(case) ... end },
    { key = 1, body = function(case) ... end },
}, function(default) ... end)
```

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
                   ok: cont(next: i32, value: i32),
                   err: cont(pos: i32, code: i32))
    ...
end

-- Usage:
return region -> i32
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
  enclosing `control ... end` or `block ... end` construct.

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
- Control intrinsics: `trap()`, `assume(cond)`
- Discarded value expressions (diagnosed as a warning in strict mode)

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
       | emit_expr   (expression fragment emit)
       | control_expr(control region expression)
       | if_expr     (if expression)
       | switch_expr (switch expression)
       | block_expr  (block expression with final value)
       | closure_expr(fn expression)
       | intrinsic   (builtin intrinsic call)
       | agg_lit     (aggregate/struct literal)
       | array_lit   (array literal)
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
x               -- local variable, parameter, const, or static
p               -- pointer parameter
xs              -- view parameter
```

Name resolution follows lexical scoping: function parameters, `let`/`var`
bindings, `const`/`static` declarations, and module-level items. Shadowing
is permitted with inner bindings hiding outer bindings.

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
addr_of(place)
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
| same-size int ↔ float | `bitcast` |
| same type | Identity (no-op) |

All valid conversions between supported scalars are defined. Conversions
between fundamentally incompatible types (e.g. `as(ptr(u8), f64_value)`) are
rejected at typecheck time.

Examples:

```moonlift
let c: i32 = as(i32, p[i])          -- u8 → i32 (unsigned extend)
let x: f64 = as(f64, count)         -- i32 → f64 (int to float)
let byte: u8 = as(u8, word)         -- i32 → u8 (truncate)
let bits: i32 = as(i32, float_val)  -- f32 → i32 (bitcast)
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
view_window(base_view, start, requested_len)
```

- `view(ptr, count)` creates a contiguous view with `stride = 1`.
- `view(ptr, count, stride)` creates a strided view.
- `view_window(base, start, len)` creates a sub-view from an existing view,
  starting at element `start` with `len` elements. The stride is inherited.

### 9.13 Unary operators

```text
- expr       numeric negation (integers and floats)
not expr     boolean not (expects bool, returns bool)
~ expr       bitwise not (integers only)
```

Negation on unsigned types is rejected. Negation on signed types is wrapping.
Floating-point negation is IEEE 754 `fneg`.

### 9.14 Binary arithmetic operators

```text
+            addition
-            subtraction
*            multiplication
/            division (float only; integer division uses intrinsics)
%            remainder (signed/unsigned integer, or float)
```

Integer arithmetic is wrapping by default. Float arithmetic uses strict IEEE
754 semantics.

Division `/` on integers is NOT defined. Use explicit integer division through
the lowering path or through the builder API (`BackCmd.Sdiv` / `BackCmd.Udiv`).

### 9.15 Bitwise operators

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

### 9.16 Comparison operators

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

### 9.17 Logical operators

```text
and          logical and (short-circuit)
or           logical or (short-circuit)
```

Both operands must have type `bool`. `and` and `or` are short-circuiting:
the right operand is evaluated only if needed.

Note: logical operators currently lower through control flow and are marked as
"deferred" in the tree-to-back lowering. For dataflow choice without control
flow, use `select(cond, a, b)`.

### 9.18 Operator precedence

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

### 9.19 Emit expression

```moonlift
emit fragment(arg1, arg2)
```

Expression fragment emit. Expression fragments return a typed expression result
and lower through `ExprUseExprFrag`. Unlike region fragment emits, expression
fragment emits produce a value (not a control-flow splice).

### 9.20 If expression

```moonlift
if cond then expr else expr end
```

An expression-producing `if`. Both branches must have the same type. Currently
deferred in the tree-to-back lowering — use `select(cond, a, b)` for immediate
dataflow choices.

### 9.21 Switch expression

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
arms must produce the same type. Currently deferred in lowering — use control
regions with `yield` for multi-path value production.

### 9.22 Block expression

```moonlift
do
    stmt*
    result_expr
end
```

An expression block with statements followed by a final expression. This is
not a control region — it does not introduce block labels or support `jump`.
Currently deferred in lowering.

### 9.23 Aggregate (struct) literals

```moonlift
Pair { left = 1, right = 2 }
Vec3 { x = 1.0, y = 0.0, z = 0.0 }
```

Creates a struct value by naming fields. All fields must be provided. Field
order does not matter. Field values must match the declared field types.

### 9.24 Array literals

```moonlift
[]i32 { 1, 2, 3, 4 }
[u8 { 0xFF, 0x00, 0xAB }
```

Creates an array value. The type determines the element type and the literal
list determines the length. Array literals are primarily useful for static
initialization and constant data.

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
let total: i32 = block loop(i: index = 0, acc: i32 = 0) -> i32
    if i >= n then
        yield acc
    end
    jump loop(i = i + 1, acc = acc + xs[i])
end
```

The result type (`-> i32`) is declared after the block parameters. The `yield`
expression must match this type.

### 10.4 Multi-block control expression

Multiple named blocks with explicit state transitions:

```moonlift
return control -> i32
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

A multi-block control expression wraps blocks in `control -> T ... end`.
The first block is the entry block. Entry blocks can use `entry` or `block`
keyword — both are accepted for the first block.

### 10.5 Multi-block control statement

Same as above but without a result type:

```moonlift
control
entry start()
    jump loop(i = 0)
end
block loop(i: index)
    if i >= n then yield end
    do_work(i)
    jump loop(i = i + 1)
end
end
```

### 10.6 Block parameters

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

### 10.7 Block labels

Block labels are scoped to the nearest enclosing control region (`block`,
`control`, or `region`). Labels are not visible outside their region. Duplicate
labels within a region are rejected.

Block labels in a control expression can be used as jump targets and as emit
continuation fill targets.

### 10.8 Termination rules

Every control-block path must terminate with exactly one of:

1. `jump label(args...)` — transfer to another block in the same region
2. `yield expr` or `yield` — exit the control region
3. `return expr` or `return` — exit the enclosing function
4. A terminating intrinsic call: `trap()`
5. An `if` or `switch` where every branch terminates

Paths that do not terminate are rejected. Paths with multiple terminating
statements (dead code after a jump/yield/return) produce warnings.

There is no implicit fallthrough from one block to the next. If you want
sequential block execution, use an explicit `jump` from the first block to
the second.

### 10.9 Function-tail loop pattern

When a loop is the last thing in a function, `return` can be used directly
from within the block instead of yielding and then returning:

```moonlift
func sum(xs: view(i32), n: index) -> i32
    block loop(i: index = 0, acc: i32 = 0)
        if i >= n then
            return acc
        end
        jump loop(i = i + 1, acc = acc + xs[i])
    end
end
```

This avoids the extra `let total = block ... end; return total` indirection.

### 10.10 Validation facts

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
                  hit: cont(pos: i32),
                  miss: cont(pos: i32))
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
             cont1_name : cont(cont1_params...),
             cont2_name : cont(cont2_params...), ... )
    body (same as a control region)
end
```

- **Runtime parameters** (before the semicolon): values passed by the caller
  at each emit site.
- **Continuations** (after the semicolon): the fragment's output protocol.
  Each continuation declares a name and typed parameters.
- **Body:** exactly one entry block and zero or more additional blocks. The
  body uses `jump cont_name(args...)` to exit through a continuation.

Region fragments are not functions — they are control-flow templates that
are spliced (inlined) at each `emit` site. There is no runtime call overhead.
The backend sees a combined control-flow graph after expansion.

### 11.2 Emit use (region fragments)

```moonlift
return region -> i32
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

### 11.3 Continuation forwarding

A fragment can emit another fragment and forward exits to its own continuation
slots:

```moonlift
region wrapper(p: ptr(u8), n: i32; out: cont(pos: i32))
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
expr clamp_nonneg(x: i32) -> i32
    select(x < 0, 0, x)
end

expr square(x: f64) -> f64
    x * x
end
```

Expression fragments have:
- A parameter list (no modifiers)
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
    return expr threshold_after_@{tag}(x: i32) -> i32
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
func f(noalias readonly xs: ptr(i32), writeonly dst: ptr(i32), n: i32) -> i32
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

Contracts are not runtime checks — they are compile-time facts that enable
optimizations (vectorization, alias analysis, bounds check elimination).
Violating a contract at runtime is undefined behavior.

---

## 14. Lua splicing and antiquote

Inside hosted source islands, Lua values are spliced into Moonlift source with
the antiquote syntax:

```moonlift
@{lua_expr}
```

### 14.1 Splice positions and expected kinds

| Source position | Expected splice kind |
|---|---|
| Type position (`let x: @{T}`) | A type value (from `moon.i32`, `moon.ptr(T)`, etc.) |
| Expression position (`@{val} + 1`) | An expression/literal value |
| Emit fragment position (`emit @{frag}(...)`) | A region or expression fragment value |
| Declaration/module site | Declaration or module value |
| Block label position | String (label name) |
| Integer constant position | Number (integer) |

### 14.2 Examples

```lua
-- Splice a type
local T = moon.i32
local inc = expr inc(x: @{T}) -> @{T}
    x + 1
end

-- Splice a fragment
local frag = make_scanner(65)
return func parse_A(p: ptr(u8), n: i32) -> i32
    return region -> i32
    entry start()
        emit @{frag}(p, n; hit = done, miss = bad)
    end
    block done(pos: i32)
        yield pos
    end
    block bad(pos: i32)
        yield -1
    end
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

Splicing inserts typed ASDL values, never raw source text. The splice is
resolved at `.mlua` load time, during hosted island construction. The
resulting ASDL is then processed by the normal compilation pipeline.

There is no runtime splicing. All `@{...}` expressions are evaluated exactly
once when the `.mlua` file is loaded. The expanded form (with all splices
resolved) is a pure Moonlift module or declaration.

---

## 15. Lua builder API reference

The builder API mirrors source constructs. This section documents the
high-level `moonlift.host` API. The low-level `moonlift.ast` API constructs
the same ASDL values with more explicit field-by-field control.

### 15.1 Sessions

```lua
local moon = require("moonlift.host")
local session = moon.new_session({ prefix = "demo" })
local api = session:api()

-- Or use the default session
local M = moon.module("Demo")
```

The session manages name generation, symbol prefixes, and compilation context.
The default `moon` object uses a session with prefix `"moon"`.

### 15.2 Types

```lua
-- Scalar types (direct properties on the API object)
moon.void
moon.bool
moon.i8    moon.i16   moon.i32   moon.i64
moon.u8    moon.u16   moon.u32   moon.u64
moon.f32   moon.f64
moon.index

-- Compound types (constructor functions)
moon.ptr(T)                    -- pointer to T
moon.view(T)                   -- view of T
moon.named(module, name)       -- named type from module
moon.path_named("Foo")         -- named type from path
moon.func_type(params, result) -- function type
moon.closure_type(params, result) -- closure type
```

### 15.3 Expressions (on the API object)

```lua
-- Literals
moon.int(42)
moon.float("1.5")
moon.bool_lit(true)
moon.string_lit("hello\n")
moon.nil_lit()

-- Arithmetic (on expression values)
expr:neg()              -- unary negation
expr:bnot()             -- bitwise not
expr:add(other)         -- addition
expr:sub(other)         -- subtraction
expr:mul(other)         -- multiplication
expr:div(other)         -- division
expr:rem(other)         -- remainder

-- Bitwise (on expression values)
expr:band(other)        -- bitwise and
expr:bor(other)         -- bitwise or
expr:bxor(other)        -- bitwise xor
expr:shl(other)         -- left shift
expr:shr(other)         -- arithmetic right shift
expr:ushr(other)        -- logical right shift

-- Comparisons (on expression values)
expr:eq(other)          -- equality
expr:ne(other)          -- inequality
expr:lt(other)          -- less than
expr:le(other)          -- less than or equal
expr:gt(other)          -- greater than
expr:ge(other)          -- greater than or equal

-- Conversions and access (on expression values)
expr:as(T)              -- semantic conversion to T
expr:field("name", T)   -- field access with result type T
expr:index(i)           -- index access

-- Other expression constructors
moon.select(cond, a, b)        -- dataflow choice
moon.load(addr, T)             -- load T from address
moon.store(addr, value)        -- store value to address
moon.addr_of(place)            -- take address of place
moon.len(view_expr)            -- view length
moon.view(data, len)           -- create contiguous view
moon.view(data, len, stride)   -- create strided view
moon.call(callee, args)        -- function call
```

### 15.4 Parameters and functions

```lua
-- Parameters
moon.param("x", moon.i32)
moon.param("xs", moon.ptr(moon.u8), { noalias = true, readonly = true })

-- Module creation
local M = moon.module("Demo")

-- Export a function
M:export_func("add", {
    moon.param("a", moon.i32),
    moon.param("b", moon.i32),
}, moon.i32, function(fn)
    fn:return_(fn.a:add(fn.b))
end)

-- Local function
M:local_func("helper", {
    moon.param("x", moon.i32),
}, moon.i32, function(fn)
    fn:return_(fn.x:mul(moon.int(2)))
end)

-- Extern function
M:extern_func("puts", {
    moon.param("s", moon.ptr(moon.u8)),
}, moon.i32)
```

Inside function bodies, parameter names are available as expression values
directly on the `fn` object (e.g. `fn.a`, `fn.b`).

### 15.5 Regions

```lua
-- Declare a region fragment
local frag = moon.region_frag("scan", {
    moon.param("p", moon.ptr(moon.u8)),
    moon.param("n", moon.i32),
    moon.param("target", moon.i32),
}, {
    hit = moon.cont({ moon.param("pos", moon.i32) }),
    miss = moon.cont({ moon.param("pos", moon.i32) }),
}, function(r)
    r:entry("loop", {
        moon.param("i", moon.i32, moon.int(0)),
    }, function(loop)
        loop:if_(loop.i:ge(r.n), function()
            loop:jump(r.miss, { pos = loop.i })
        end, function()
            loop:if_(r.p:index(loop.i):as(moon.i32):eq(r.target), function()
                loop:jump(r.hit, { pos = loop.i })
            end, function()
                loop:jump(loop, { i = loop.i:add(moon.int(1)) })
            end)
        end)
    end)
end)
```

**Block builder methods:**

```lua
block:jump(target, { name = value, ... })     -- jump with named args
block:yield_(expr?)                             -- yield with optional value
block:return_(expr?)                            -- return with optional value
block:emit(fragment, { arg, ... }, { exit = block, ... })  -- emit region fragment
block:if_(cond, then_fn, else_fn?)             -- if statement
block:switch_(value, arms, default_fn)          -- switch statement
block:let(name, type, expr)                    -- let binding
block:var(name, type, expr)                    -- var binding
block:set_(place, expr)                        -- assignment
block:stmt(expr)                                -- expression statement
```

### 15.6 Expression fragments

```lua
-- Declare
local inc = moon.expr_frag("inc", {
    moon.param("x", moon.i32),
}, moon.i32, function(e)
    return e.x:add(moon.int(1))
end)

-- Use
local result = moon.emit_expr(inc, { moon.int(5) })
```

### 15.7 Host declarations (in builder)

```lua
-- Struct
local User = moon.struct("User", {
    { name = "id", type = moon.i32 },
    { name = "active", type = moon.bool32 },
})

-- Expose
local Users = moon.expose("Users", moon.view(User))

-- Native method
moon.native_method(User, "is_active", {
    moon.param("self", moon.ptr(User)),
}, moon.bool, function(fn)
    fn:return_(fn.self:field("active", moon.bool))
end)
```

### 15.8 Compilation and JIT

```lua
-- Compile the module
local compiled = M:compile()

-- Get a function pointer by name
local add = compiled:get("add")
print(add(1, 2))            -- 3 (native call)

-- Check if a function exists
if compiled:has("helper") then
    local h = compiled:get("helper")
end

-- Enumerate function names
for name in compiled:functions() do
    print(name)
end

-- Free the compiled artifact
compiled:free()
```

The `:compile()` method returns a compiled artifact. You can call `:get(name)`
multiple times; it returns the same function pointer. After `:free()`, the
artifact is invalidated and function pointers become dangling — calling them
is undefined behavior.

---

## 16. View and host ABI semantics

### 16.1 Canonical view descriptor

```c
typedef struct MoonView_T {
    T* data;         // pointer to first element
    intptr_t len;    // number of elements
    intptr_t stride; // stride in elements (1 = contiguous)
} MoonView_T;
```

All three fields are present in the internal ABI. When a view is passed to
or from C code through an expose declaration, the ABI depends on the target's
policy:

- **`descriptor` policy:** passes the full three-field descriptor as a struct
  (by value or by pointer depending on target platform ABI).
- **`data_len_stride` policy:** passes or receives three separate arguments
  (data pointer, length, stride).
- **`pointer` policy:** passes only the data pointer (for single-element
  pointer semantics).

### 16.2 Indexing

```text
element_address(i) = data + i * stride * sizeof(T)
```

For contiguous views (`stride = 1`), this simplifies to standard C array
indexing: `data[i]`.

### 16.3 Windowing

```text
windowed_data    = data + start * stride * sizeof(T)
windowed_len     = requested_len
windowed_stride  = stride
```

Windowing does not copy data. It creates a new view descriptor pointing
to a subrange of the original view.

### 16.4 Lua proxy semantics

For `expose UserRef: ptr(User)` with Lua target:

```lua
local user = get_user_ref()
print(user.id)              -- field access
print(user.age)
user.id = 42                -- field mutation (if mutable policy)
```

For `expose Users: view(User)` with Lua target:

```lua
local users = get_users()
print(users[1].id)          -- indexed field access
print(#users)               -- length operator
users:get_id(1)             -- accessor method
users:set_id(1, 42)         -- mutator method (if mutable policy)
```

Lua proxies are exposure/access facets of Moonlift views and pointers. They
are generated by the host access plan phase and use LuaJIT FFI for zero-copy
access where possible.

---

## 17. Vectorization and facts

Moonlift vectorization is fact-driven. The source language provides typed
control and contracts; phases decide whether vectorization applies.

### 17.1 Vectorization fact pipeline

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

### 17.2 Canonical counted shape

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

### 17.3 Vector types

Vector types are represented as `BackVec` with an element scalar type and
lane count (must be power of two ≥ 2):

```text
BackVec { elem: i32, lanes: 4 }    -- 4 x i32 = 128-bit SSE/NEON vector
BackVec { elem: f64, lanes: 2 }    -- 2 x f64 = 128-bit vector
BackVec { elem: i32, lanes: 8 }    -- 8 x i32 = 256-bit AVX2 vector
```

### 17.4 Vector kernel plan

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

### 17.5 Explicit rejects

Vectorization produces explicit rejects for unsupported shapes, including:
- Non-affine induction variables
- Loop-carried dependencies that prevent vectorization
- Memory access patterns that require gather/scatter on targets without support
- Mixed-precision operations without vector support
- Control flow divergence within the loop body

---

## 18. Error and diagnostic model

Moonlift diagnostics are ASDL values, not format strings. Every phase that
can fail produces typed issue values.

### 18.1 Diagnostic categories

| Category | Phase | Examples |
|---|---|---|
| Parse issues | `mlua_parse`, `parse` | Unexpected token, unclosed block, invalid literal |
| Host declaration rejects | `host_decl_validate` | Invalid struct field type, ambiguous bool storage |
| Open slot/fill issues | `open_validate` | Missing continuation fill, extra fill, type mismatch |
| Type issues | `tree_typecheck` | Type mismatch, unknown identifier, invalid conversion |
| Control rejects | `tree_control_facts` | Unterminated block, duplicate label, missing jump arg |
| Contract issues | `tree_contract_facts` | Invalid bounds expression, conflicting modifiers |
| Vector rejects | `vec_loop_facts`, `vec_kernel_safety` | Non-counted loop, unsafe memory pattern |
| Backend issues | `back_validate` | Mismatched operand types, invalid switch cases |

### 18.2 Diagnostic structure

Each diagnostic carries:

```text
- category (error, warning, info)
- message (human-readable)
- source location (file, line, column span)
- optional related locations ("see declaration here")
- optional fix suggestion (for code actions)
```

### 18.3 Consuming diagnostics

Tools and LSP features consume diagnostic facts directly as ASDL values. They
should not rediscover language semantics from raw text or re-parse source
files to create diagnostics.

---

## 19. Intrinsics

Intrinsics are built-in operations that map directly to Cranelift IR
instructions. They are called like functions but have no function call
overhead.

### 19.1 Bit manipulation intrinsics

```moonlift
popcount(x)     -- count of set bits (integer types)
clz(x)          -- count leading zeros
ctz(x)          -- count trailing zeros
rotl(x, n)      -- rotate left by n bits
rotr(x, n)      -- rotate right by n bits
bswap(x)        -- byte swap (endianness reversal)
```

All bit manipulation intrinsics require integer operand types. The result
type matches the operand type.

### 19.2 Float math intrinsics

```moonlift
sqrt(x)         -- square root
abs(x)          -- absolute value (float or integer)
floor(x)        -- round toward negative infinity
ceil(x)         -- round toward positive infinity
trunc_float(x)  -- round toward zero
round(x)        -- round to nearest, ties to even
fma(a, b, c)    -- fused multiply-add: a * b + c
```

Float math intrinsics follow IEEE 754 semantics where applicable. `abs` is
overloaded: it works on both integer and float types, using `iabs` for
integers and `fabs` for floats.

### 19.3 Control intrinsics

```moonlift
trap()          -- trigger an unrecoverable trap (ud2 on x86)
assume(cond)    -- hint to the optimizer that cond is true
```

- `trap()` terminates execution immediately. It can be used as a terminating
  statement in control blocks (satisfies the termination requirement).
- `assume(cond)` tells the optimizer that `cond` is guaranteed to be true at
  this point. If `cond` is false at runtime, behavior is undefined. Used to
  communicate facts that the compiler cannot prove.

**Note:** Intrinsic lowering from source to backend commands is currently
deferred. Intrinsics are available in the schema and typed phases but the
source-level intrinsic syntax lowering to `BackCmd` is in development. Use
the builder API for supported intrinsics in the meantime.

---

## 20. Memory operations

### 20.1 Load and store

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

### 20.2 Memory copy and set

```moonlift
-- In builder API:
moon.memcpy(dst, src, len)    -- copy len bytes from src to dst
moon.memset(dst, byte, len)   -- set len bytes at dst to byte value
```

Both `memcpy` and `memset` take pointer arguments and a length argument.
The length is in bytes, not elements.

### 20.3 Memory access facts

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

---

## 21. Complete examples

### 21.1 Typed dispatch over bytes

```moonlift
region parse_digit(p: ptr(u8), n: i32, pos: i32;
                   ok: cont(next: i32, value: i32),
                   err: cont(pos: i32, code: i32))
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

### 21.2 Switch + emit dispatch

```moonlift
export func classify(p: ptr(u8), n: i32) -> i32
    return region -> i32
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

### 21.3 Lua-generated monomorphic fragments

```lua
local function expect_byte(tag, byte, err_code)
    return region expect_@{tag}(p: ptr(u8), n: i32, pos: i32;
        ok: cont(next: i32),
        err: cont(pos: i32, code: i32))
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

### 21.4 Host declaration + native methods

```lua
struct User
    id: i32
    age: i32
    active: bool32
end

expose UserRef: ptr(User)
expose Users: view(User)

func User:is_active(self: ptr(User)) -> bool
    return self.active
end

func User:set_age(self: ptr(User), new_age: i32)
    self.age = new_age
end

-- Lua-hosted method
function User:is_adult()
    return self.age >= 18
end
```

### 21.5 Multi-block state machine

```moonlift
export func scan_byte(p: ptr(u8), n: i32, target: u8) -> i32
    return control -> i32
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

### 21.6 Counted sum with region fragment

```moonlift
region sum_range(xs: view(i32), start: index, len: index;
                 done: cont(total: i32))
entry loop(i: index = 0, acc: i32 = 0)
    if i >= len then jump done(total = acc) end
    jump loop(i = i + 1, acc = acc + xs[start + i])
end
end

export func sum_first_n(xs: view(i32), n: index) -> i32
    return region -> i32
    entry start()
        emit sum_range(xs, 0, n; done = out)
    end
    block out(total: i32)
        yield total
    end
    end
end
```

### 21.7 PVM-LL phase dispatch (tagged union switch)

```moonlift
region classify_uncached(ctx: ptr(i32), tag: i32;
    value: cont(delta: i32))
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

## 22. Implementation/layer map

Important implementation homes (all under `lua/moonlift/`):

```text
-- Parsing
parse.lua                       object source parser
mlua_parse.lua                  .mlua hosted island parser
mlua_lex.lua                    .mlua lexer
mlua_island_parse.lua           island detection and extraction
mlua_loop_expand.lua            loop sugar → block/jump lowering

-- Host bridge
host_quote.lua                  LuaJIT hosted island bridge
host.lua                        high-level builder API entry point
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

-- Tree → backend lowering
tree_typecheck.lua              typecheck/name resolution
tree_expr_type.lua              expression type resolution
tree_stmt_type.lua              statement type resolution
tree_place_type.lua             place type resolution
tree_module_type.lua            module-level type resolution
tree_field_resolve.lua          field/access resolution
tree_control_facts.lua          control validation facts
tree_control_to_back.lua        region/control → backend commands
tree_contract_facts.lua         contract validation facts
tree_to_back.lua                tree → flat backend commands
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

-- Vectorization
vec_loop_facts.lua              counted-loop fact extraction
vec_loop_decide.lua             vectorization decision
vec_kernel_plan.lua             vector kernel planning
vec_kernel_safety.lua           vector safety proofs
vec_kernel_to_back.lua          vector kernel → backend commands
vec_to_back.lua                 vector lowering pipeline
vec_inspect.lua                 vector plan inspection

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
schema/init.lua                 schema module index
schema/core.lua                 MoonCore schema
schema/type.lua                 MoonType schema
schema/tree.lua                 MoonTree schema
schema/sem.lua                  MoonSem schema
schema/back.lua                 MoonBack schema
schema/link.lua                 MoonLink schema
schema/host.lua                 MoonHost schema
schema/open.lua                 MoonOpen schema
schema/vec.lua                  MoonVec schema
schema/bind.lua                 MoonBind schema
schema/mlua.lua                 MoonMlua schema
schema/editor.lua               MoonEditor schema
schema/lsp.lua                  MoonLsp schema
schema/rpc.lua                  MoonRpc schema
schema/source.lua               MoonSource schema
schema/pvm_surface.lua          MoonPvmSurface schema
```

---

## 23. Summary doctrine

Moonlift source is small on purpose:

```text
monomorphic typed data
+ typed regions
+ explicit continuation exits
+ switch/emit/jump composition
+ semantic as(T, value) conversion
```

Lua supplies all genericity.

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
programmer needs to abstract is expressed in Lua.
