# .mlua zero-copy view/data ABI design

Status: full design and implementation checklist.

This document defines the complete path for `.mlua` language-backed, zero-copy
data passing between Lua staging code, Moonlift object source, Terra, C/FFI, and
the Cranelift backend.

The design is intentionally **not** JSON-specific. JSON projection is one
producer of declared layouts; it does not own the layout model.

---

## 1. Core thesis

```text
.mlua hosted top-level declarations define data layouts, regions, loops,
functions, and exposure policy.
Moonlift source is a first-class object/declaration language, not an afterthought.
Moonlift views are the only semantic view model.
Moon2Host facts describe layout/access/exposure/ABI.
Lua FFI and Terra consume the same facts.
Crossing the language boundary passes pointers/descriptors, not converted values.
```

This gives the desired combination:

```text
high-level Lua ergonomics
  + low-level Moonlift object code
  + Terra/C-compatible ABI
  + zero-copy boundary crossing
  + generated table-shaped Lua access
```

Non-negotiable boundaries:

- no JSON in Rust
- no JSON in Moonlift compiler/core
- no Rust dynamic object/array/map/string arena as a shortcut
- no separate Lua/Terra/JSON view semantics
- no layout meaning hidden in Lua tables after declaration sealing

The source of truth is ASDL facts.

`.mlua` is the language. It is not Lua scripts with incidental Moonlift strings,
and it is not a builder-only API with syntax bolted on later. A `.mlua` file is a
staged language file with two first-class layers:

```text
Lua host layer:
  staging computation, imports, specialization, module assembly

Moonlift object/declaration layer:
  structs, views, exposes, regions, loops, functions, methods, contracts
```

Both layers construct the same ASDL values. For every meaningful construct there
must be:

```text
.mlua source syntax
Lua builder/splice API
ASDL representation
PVM validation/lowering phases
```

`moonlift.ast` is the base ASDL constructor facade for this builder/splice side:
it exposes LuaLS-documented constructors for existing source `Moon2Core`,
`Moon2Type`, and `Moon2Tree` nodes.  Hosted declaration/value APIs may stay more
ergonomic, but their outputs should remain plain ASDL values compatible with the
same constructor surface and the same PVM phases.

---

## 2. One semantic view model

Moonlift already owns the real low-level view semantics:

```asdl
Moon2Type.Type
  = TView(Type elem)

Moon2Tree.View
  = ViewContiguous(data, elem, len)
  | ViewStrided(data, elem, len, stride)
  | ViewWindow(base, start, len)
  | ViewRestrided(base, elem, stride)
  | ViewRowBase(base, row_offset, elem)
  | ViewInterleaved(...)
```

The host/Lua/Terra layer must not invent a second meaning for `view`.

Correct model:

```text
Moonlift view(T)
  = semantic typed memory view

Lua view / Terra view / C view
  = exposure/ABI/access facets of Moonlift view(T)
```

Canonical executable view descriptor:

```c
typedef struct MoonView_User {
    User* data;
    intptr_t len;
    intptr_t stride;
} MoonView_User;
```

Decision:

```text
stride is in elements, not bytes.
```

Index address:

```text
addr(i) = data + (i * stride * sizeof(elem))
```

Contiguous views use:

```text
stride = 1
```

Window views canonicalize by adjusting `data` and preserving `stride`:

```text
data'   = data + start * stride * sizeof(elem)
len'    = requested_len
stride' = stride
```

A `view(User)` is a sequence. It is not a single `User`.

```text
ptr(User)  -> one record/user
view(User) -> indexed sequence of records/users
```

Lua API reflects this:

```lua
user.id          -- ptr(User)
users[1].id      -- view(User)
#users           -- view length
users:get_id(1)  -- generated direct accessor
```

---

## 3. `.mlua` is the declaration and object-code language

Terra's important ergonomic lesson is that structs are declared at Lua staging
time. Moonlift keeps that power, but does not demote source syntax to an
afterthought. `.mlua` is the integrated hosted language:

```text
Lua host/staging code
  + Moonlift top-level declarations
  + Moonlift object-code bodies
  + ASDL splicing/antiquote
```

`.mlua` top-level source:

```lua
local checked = true -- ordinary Lua staging value

struct User
    id: i32
    age: i32
    active: bool32
end

expose UserRef: ptr(User)

expose Users: view(User)

region CountActive(users: view(User)) -> i32
    block loop(i: index = 0, acc: i32 = 0)
        if i >= len(users) then yield acc end
        if users[i].active then
            jump loop(i = i + 1, acc = acc + 1)
        end
        jump loop(i = i + 1, acc = acc)
    end
end

export func count_active(users: view(User)) -> i32
    emit CountActive(users)
end
```

This is not runtime Lua object construction and not source-string codegen. It is
hosted source syntax that creates ASDL declarations/facts:

```text
Moon2Tree.TypeDeclStruct(User, ...)
Moon2Host.HostStructDecl(User, ...)
Moon2Host.HostTypeLayout(User, ...)
Moon2Host.HostViewDescriptor(Users, ...)
Moon2Host.HostAccessPlan(UserRef, ...)
Moon2Host.HostAccessPlan(Users, ...)
Moon2Open.RegionFrag(CountActive, ...)
Moon2Tree.Func(count_active, ...)
Moon2Host.HostLuaFfiPlan(...)
Moon2Host.HostTerraPlan(...)
Moon2Host.HostCdef(...)
```

Lua builder APIs are equal frontends, not the real language underneath source.
For example:

```lua
local User = moon.struct("User", {
    moon.i32("id"),
    moon.i32("age"),
    moon.bool32("active"),
})
```

must produce the same ASDL declarations as:

```lua
struct User
    id: i32
    age: i32
    active: bool32
end
```

Moonlift source remains the canonical readable object/declaration form. Lua host
code provides staging, composition, and specialization around it.

---

## 4. Struct declaration semantics

A `.mlua` top-level `struct` is a boundary-stable layout declaration.

```lua
struct User
    id: i32
    age: i32
    active: bool32
end
```

Equivalent explicit form:

```lua
struct User repr(c)
    id: i32
    age: i32
    active: bool stored i32
end
```

### 4.1 Representation

Default representation:

```text
repr(c)
```

Rules:

- field order is source order
- natural C/Terra/LuaJIT ABI alignment is used
- field padding is derived, not authored
- struct size is rounded to struct alignment
- derived size/alignment/offsets appear in `HostTypeLayout`/`HostFieldLayout`

Packed representation is explicit:

```lua
struct Packet repr(packed(1)) {
    tag: u8
    len: u32
}
```

No hidden packing policy is allowed.

### 4.2 Exposed type vs storage type

Every field has two meanings:

```text
exposed type: what Moonlift/Lua/Terra accessors mean
storage type: what bytes are actually stored
```

Normal scalar:

```lua
id: i32
```

means:

```text
exposed type = i32
storage type = i32
```

Boolean boundary fields must use explicit storage:

```lua
active: bool8
active: bool32
active: bool stored i32
```

Decision:

```text
Bare bool is rejected in hosted boundary structs.
```

Reason:

```text
C bool, LuaJIT bool, Terra bool, and Moonlift bool must not silently disagree.
```

Invalid:

```lua
struct Bad
    active: bool
end
```

Diagnostic:

```text
HostRejectAmbiguousBoolStorage("Bad.active")
```

Valid:

```lua
struct User
    active: bool32
end
```

Semantic facts:

```text
HostFieldDecl(active, expose_ty = bool, storage = i32)
HostFieldLayout(active, rep = HostRepBool(HostBoolI32, ScalarI32), offset = ...)
```

### 4.3 Field access semantics

Given:

```lua
struct User
    active: bool32
end
```

Moonlift source:

```moonlift
if users[i].active then ... end
```

typechecks as:

```text
users[i].active : bool
```

Backend lowering:

```text
elem_addr   = users.data + i * users.stride * sizeof(User)
field_addr  = elem_addr + offset(active)
raw         = load i32 field_addr
active_bool = raw != 0
```

Store lowering:

```moonlift
users[i].active = true
```

becomes:

```text
raw = select true ? 1 : 0
store i32 raw
```

The user sees `bool`; the ABI stores `i32`.

---

## 5. `.mlua` top-level grammar

The `.mlua` source file is Lua staging code plus first-class Moonlift declaration
and object-code forms.

### 5.1 Struct declarations

```ebnf
StructDecl
  ::= "struct" Name Repr? "{" StructMember* "}"

Repr
  ::= "repr" "(" "c" ")"
    | "repr" "(" "packed" "(" Int ")" ")"

StructMember
  ::= FieldDecl

FieldDecl
  ::= Name ":" HostFieldType FieldAttr*

HostFieldType
  ::= ScalarType
    | "bool8"
    | "bool32"
    | "bool" "stored" ScalarType
    | "ptr" "(" Type ")"
    | "slice" "(" Type ")"
    | "view" "(" Type ")"
    | Name

FieldAttr
  ::= "readonly"
    | "mutable"
    | "noalias"
```

Examples:

```lua
struct User
    id: i32
    age: i32
    active: bool32
end
```

```lua
struct Header repr(packed(1))
    tag: u8
    len: u32
end
```

### 5.2 Exposure declarations

```ebnf
ExposeDecl
  ::= "expose" Name ":" ExposeSubject [ nl ExposeFacetLine* "end" ]

ExposeSubject
  ::= Type
    | "ptr" "(" Type ")"
    | "view" "(" Type ")"

ExposeFacetLine
  ::= ExposeTarget ExposeFacetClause*

ExposeTarget
  ::= "lua"
    | "terra"
    | "c"
    | "moonlift"

ExposeFacetClause
  ::= HostAbiName
    | ProxyMode
    | Mutability
    | BoundsPolicy
    | MaterializePolicy

HostAbiName
  ::= "pointer"
    | "descriptor"
    | "data_len_stride"
    | "expanded_scalars"

ProxyMode
  ::= "proxy"
    | "typed_record"
    | "buffer_view"

Mutability
  ::= "readonly"
    | "mutable"
    | "interior_mutable"

BoundsPolicy
  ::= "checked"
    | "unchecked"

MaterializePolicy
  ::= "eager_table"
    | "full_copy"
    | "borrowed_view"
```

Default decisions:

```text
ptr(T) C/Terra facet ABI: pointer
view(T) C/Terra facet ABI: descriptor
Lua facet access: proxy readonly checked
non-Lua facet bounds default: unchecked unless specified
view(T) internal Moonlift ABI: data, len, stride with element stride
one-line expose declaration with no body: Lua + Terra + C defaults
```

Examples:

```lua
expose UserRef: ptr(User)
expose Users: view(User)
```

```lua
expose UsersLuaOnly: view(User)
    lua
end
expose MutableUserRef: ptr(User)
    lua mutable
end
```

### 5.3 Methods

Field accessors are automatic.

Lua-hosted methods use ordinary LuaJIT method syntax at top level.

```lua
function User:is_adult()
    return self.age >= 18
end
```

Moonlift-native methods use `func Type:name(...) -> T`. The parser records this
as a `HostAccessorMoonlift` fact and lowers the object code as an ordinary
Moonlift function with a stable generated symbol.

```lua
func User:is_active_adult(self: ptr(User)) -> bool
    return self.active and self.age >= 18
end
```

Semantics:

```text
standard Lua method:
  ordinary Lua closure over generated proxy accessors;
  recorded as HostAccessorLua for exposure planning.

Moonlift func method:
  object-language function compiled by Moonlift;
  recorded as HostAccessorMoonlift for exposure planning.
```

### 5.4 Region declarations

Regions are source-level typed control/data fragments. They are not functions and
not string templates. A region has parameters, a typed yield/result protocol, and
optionally continuation exits.

```ebnf
RegionDecl
  ::= "region" Name "(" ParamList? ")" RegionResult? ContList? BlockBody

RegionResult
  ::= "->" Type

ContList
  ::= ";" ContDecl ("," ContDecl)*

ContDecl
  ::= "cont" Name "(" ParamList? ")"
```

Examples:

```moonlift
region CountActive(users: view(User)) -> i32 {
    block loop(i: index = 0, acc: i32 = 0) {
        if i >= len(users) then yield acc end
        if users[i].active then
            jump loop(i = i + 1, acc = acc + 1)
        end
        jump loop(i = i + 1, acc = acc)
    }
}
```

Continuation region:

```moonlift
region ScanString(p: ptr(u8), n: i32;
                  cont done(pos: i32),
                  cont fail(pos: i32)) {
    entry {
        -- typed block/jump source
    }
}
```

Lowering target:

```text
Moon2Open.RegionFrag
Moon2Open.ContSlot
Moon2Tree.EntryControlBlock
Moon2Tree.ControlBlock*
Moon2Tree.StmtJumpCont
```

### 5.5 Function and module declarations

Functions are executable units with ABI. Regions are compositional fragments.
Both are first-class source constructs.

```ebnf
ModuleDecl
  ::= "module" Name "{" TopLevelDecl* "}"

FuncDecl
  ::= Export? "func" Name "(" ParamList? ")" "->" Type BlockBody

Export
  ::= "export"
```

Example:

```moonlift
module UserKernels
    export func count_active(users: view(User)) -> i32
        emit CountActive(users)
    end
end
```

A function export creates both an internal Moonlift ABI and, when exposed, a host
ABI wrapper plan.

### 5.6 Loop source forms

The core semantic model remains:

```text
blocks are typed continuations
jumps are typed tail calls
```

Source loops are designed patterns over blocks/jumps. They are source constructs,
but not backend primitives.

Canonical block loop:

```moonlift
block loop(i: index = 0, acc: i32 = 0)
    if i >= n then yield acc end
    jump loop(i = i + 1, acc = acc + xs[i])
end
```

Counted loop source pattern:

```moonlift
loop counted i: index = 0 until i >= n
     state acc: i32 = 0
     yield acc
     next acc = acc + xs[i]
end
```

Lowering target for both forms:

```text
entry block
loop block(i, state...)
conditional yield/return/jump
StmtJump with named JumpArg values
```

The counted loop is accepted only because its lowering is exactly the explicit
block/jump form. Any additional loop family must state its block/jump expansion
as an ASDL phase.

### 5.7 Source/builder/splice equivalence

For every top-level construct:

```text
.mlua syntax
Lua builder API
ASDL value
PVM phase
```

must be defined together. Anti-quotation and splicing insert typed ASDL values,
never text.

Allowed splice kinds include:

```text
Type
HostFieldDecl / FieldDecl
HostDecl / Item
RegionFrag
Stmt*
Expr
Module item list
Expose clause / policy value
```

A splice is rejected if the ASDL kind does not match the source site.

---

## 6. Complete ASDL model

`Moon2Host` owns declaration, layout, view ABI, access, exposure, emission, and
diagnostics facts for host boundary data.

Regions, functions, blocks, jumps, and loop expansions remain in the existing
Moonlift object-language ASDL modules:

```text
Moon2Tree.Func / Stmt / ControlBlock / StmtJump / StmtYield
Moon2Open.RegionFrag / ContSlot / SlotBinding / StmtJumpCont
Moon2Back.Cmd flat backend commands
```

The `.mlua` parser is the unifying frontend: it creates `Moon2Host` facts for
boundary layout/exposure and `Moon2Tree`/`Moon2Open` values for object code.

### 6.1 Source declarations

```asdl
HostDeclSet =
  (Moon2Host.HostDecl* decls) unique

HostDecl
  = HostDeclStruct(Moon2Host.HostStructDecl decl)
  | HostDeclExpose(Moon2Host.HostExposeDecl decl)
  | HostDeclAccessor(Moon2Host.HostAccessorDecl decl)

HostStructDecl =
  (Moon2Host.HostLayoutId id,
   string name,
   Moon2Host.HostRepr repr,
   Moon2Host.HostFieldDecl* fields) unique

HostRepr
  = HostReprC
  | HostReprPacked(number align)
  | HostReprOpaque(string name)

HostFieldDecl =
  (Moon2Host.HostFieldId id,
   string name,
   Moon2Type.Type expose_ty,
   Moon2Host.HostStorageRep storage,
   Moon2Host.HostFieldAttr* attrs) unique

HostFieldAttr
  = HostFieldReadonly
  | HostFieldMutable
  | HostFieldNoalias
  | HostFieldOpaque(string name)

HostStorageRep
  = HostStorageSame
  | HostStorageScalar(Moon2Core.Scalar scalar)
  | HostStorageBool(Moon2Host.HostBoolEncoding encoding,
                    Moon2Core.Scalar scalar)
  | HostStoragePtr(Moon2Type.Type pointee)
  | HostStorageSlice(Moon2Type.Type elem)
  | HostStorageView(Moon2Type.Type elem)
  | HostStorageOpaque(string name)
```

### 6.2 Layout facts

```asdl
HostBoolEncoding
  = HostBoolU8
  | HostBoolI32
  | HostBoolNative

HostFieldRep
  = HostRepScalar(Moon2Core.Scalar scalar)
  | HostRepBool(Moon2Host.HostBoolEncoding encoding,
                Moon2Core.Scalar storage)
  | HostRepPtr(Moon2Type.Type pointee)
  | HostRepSlice(Moon2Host.HostFieldRep elem)
  | HostRepView(Moon2Type.Type elem)
  | HostRepStruct(Moon2Host.HostLayoutId layout)
  | HostRepOpaque(string name)

HostFieldLayout =
  (Moon2Host.HostFieldId id,
   string name,
   string cfield,
   Moon2Host.HostFieldRep rep,
   number offset,
   number size,
   number align) unique

HostTypeLayout =
  (Moon2Host.HostLayoutId id,
   string name,
   string ctype,
   Moon2Host.HostLayoutKind kind,
   number size,
   number align,
   Moon2Host.HostFieldLayout* fields) unique

HostLayoutKind
  = HostLayoutStruct
  | HostLayoutSlice
  | HostLayoutViewDescriptor
  | HostLayoutOpaque
```

### 6.3 Target model

Layout depends on target pointer/index ABI. That must be explicit.  The backend
refactor has introduced `Moon2Back.BackTargetModel` as the canonical executable
target fact home; `HostTargetModel` remains the host-layout facet and should be
derived from `BackTargetModel` once the target-model phase is wired.

```asdl
HostEndian
  = HostEndianLittle
  | HostEndianBig

HostTargetModel =
  (number pointer_bits,
   number index_bits,
   Moon2Host.HostEndian endian) unique
```

Default host target for LuaJIT on this project is:

```text
pointer_bits = ffi.abi("64bit") ? 64 : 32
index_bits   = pointer_bits
endian       = host endian
```

No semantic phase may silently hardcode 64-bit layout.

### 6.4 View ABI facts

```asdl
HostExposeSubject
  = HostExposeType(Moon2Type.Type ty)
  | HostExposePtr(Moon2Type.Type pointee)
  | HostExposeView(Moon2Type.Type elem)

HostStrideUnit
  = HostStrideElements
  | HostStrideBytes

HostViewAbi
  = HostViewAbiContiguous(Moon2Host.HostTypeLayout elem_layout)
  | HostViewAbiStrided(Moon2Host.HostTypeLayout elem_layout,
                       Moon2Host.HostStrideUnit stride_unit)

HostViewDescriptor =
  (Moon2Host.HostLayoutId id,
   string name,
   Moon2Host.HostViewAbi abi,
   Moon2Host.HostTypeLayout descriptor_layout) unique
```

Decision:

```text
Moonlift-native exposed views use HostStrideElements.
HostStrideBytes exists only for explicit foreign byte-stride APIs.
```

### 6.5 Access plans

```asdl
HostAccessSubject
  = HostAccessRecord(Moon2Host.HostTypeLayout layout)
  | HostAccessPtr(Moon2Host.HostTypeLayout layout)
  | HostAccessView(Moon2Host.HostViewDescriptor descriptor)

HostAccessKey
  = HostAccessField(string name)
  | HostAccessIndex
  | HostAccessLen
  | HostAccessData
  | HostAccessStride
  | HostAccessMethod(string name)
  | HostAccessPairs
  | HostAccessIpairs
  | HostAccessToTable

HostAccessOp
  = HostAccessDirectField(Moon2Host.HostFieldLayout field)
  | HostAccessDecodeBool(Moon2Host.HostFieldLayout field)
  | HostAccessEncodeBool(Moon2Host.HostFieldLayout field)
  | HostAccessViewIndex(Moon2Host.HostViewDescriptor descriptor)
  | HostAccessViewFieldAt(Moon2Host.HostViewDescriptor descriptor,
                          Moon2Host.HostFieldLayout field)
  | HostAccessViewLen(Moon2Host.HostViewDescriptor descriptor)
  | HostAccessViewData(Moon2Host.HostViewDescriptor descriptor)
  | HostAccessViewStride(Moon2Host.HostViewDescriptor descriptor)
  | HostAccessPointerCast(Moon2Host.HostTypeLayout layout)
  | HostAccessMaterializeTable(Moon2Host.HostAccessSubject subject)
  | HostAccessReject(string reason)

HostAccessEntry =
  (Moon2Host.HostAccessKey key,
   Moon2Host.HostAccessOp op) unique

HostAccessPlan =
  (Moon2Host.HostAccessSubject subject,
   Moon2Host.HostAccessEntry* entries) unique
```

### 6.6 Exposure targets and policies

```asdl
HostExposeTarget
  = HostExposeLua
  | HostExposeTerra
  | HostExposeC
  | HostExposeMoonlift

HostMutability
  = HostReadonly
  | HostMutable
  | HostInteriorMutable

HostBoundsPolicy
  = HostBoundsChecked
  | HostBoundsUnchecked

HostProxyKind
  = HostProxyPtr
  | HostProxyView
  | HostProxyBufferView
  | HostProxyTypedRecord
  | HostProxyOpaque

HostProxyCachePolicy
  = HostProxyCacheNone
  | HostProxyCacheLazy
  | HostProxyCacheEager

HostMaterializePolicy
  = HostMaterializeProjectedFields
  | HostMaterializeFullCopy
  | HostMaterializeBorrowedView

HostExposeMode
  = HostExposeProxy(Moon2Host.HostProxyKind kind,
                    Moon2Host.HostProxyCachePolicy cache,
                    Moon2Host.HostMutability mutability,
                    Moon2Host.HostBoundsPolicy bounds)
  | HostExposeEagerTable(Moon2Host.HostMaterializePolicy policy)
  | HostExposeScalar(Moon2Host.HostFieldRep rep)
  | HostExposeOpaque(string reason)

HostExposeAbi
  = HostExposeAbiDefault
  | HostExposeAbiPointer
  | HostExposeAbiDescriptor
  | HostExposeAbiDataLenStride
  | HostExposeAbiExpandedScalars
  | HostExposeAbiOpaque(string reason)

HostExposeFacet =
  (Moon2Host.HostExposeTarget target,
   Moon2Host.HostExposeAbi abi,
   Moon2Host.HostExposeMode mode) unique

HostExposeDecl =
  (Moon2Host.HostExposeSubject subject,
   string public_name,
   Moon2Host.HostExposeFacet* facets) unique
```

### 6.7 Emission plans

```asdl
HostCdef =
  (Moon2Host.HostLayoutId layout,
   string source) unique

HostLuaFfiPlan =
  (string module_name,
   Moon2Host.HostCdef* cdefs,
   Moon2Host.HostAccessPlan* access_plans) unique

HostTerraPlan =
  (string module_name,
   string source,
   Moon2Host.HostTypeLayout* layouts,
   Moon2Host.HostViewDescriptor* views) unique

HostCPlan =
  (string header_name,
   string source,
   Moon2Host.HostTypeLayout* layouts,
   Moon2Host.HostViewDescriptor* views) unique
```

### 6.8 Accessor declarations

```asdl
HostAccessorDecl
  = HostAccessorField(string owner_name,
                      string name,
                      string field_name)
  | HostAccessorLua(string owner_name,
                    string name,
                    string lua_symbol)
  | HostAccessorMoonlift(string owner_name,
                         string name,
                         Moon2Tree.Func func)
```

### 6.9 Fact stream

```asdl
HostLayoutFact
  = HostFactDecl(Moon2Host.HostDecl decl)
  | HostFactTypeLayout(Moon2Host.HostTypeLayout layout)
  | HostFactField(Moon2Host.HostLayoutId owner,
                  Moon2Host.HostFieldLayout field)
  | HostFactViewDescriptor(Moon2Host.HostViewDescriptor descriptor)
  | HostFactExpose(string public_name,
                   Moon2Host.HostLayoutId layout,
                   Moon2Host.HostExposeFacet facet)
  | HostFactAccessPlan(Moon2Host.HostAccessPlan plan)
  | HostFactLuaFfi(Moon2Host.HostLuaFfiPlan plan)
  | HostFactTerra(Moon2Host.HostTerraPlan plan)
  | HostFactC(Moon2Host.HostCPlan plan)
  | HostFactCdef(Moon2Host.HostCdef cdef)

HostFactSet =
  (Moon2Host.HostLayoutFact* facts) unique
```

---

## 7. Phase boundaries

All meaningful transformations are PVM phases over ASDL values.

### 7.1 `mlua_parse`

Question:

```text
What Lua host forms and Moonlift declaration/object forms appear in this `.mlua`
file, and what ASDL values do they produce?
```

Input:

```text
.mlua source tokens, Lua staging environment, imported ASDL values
```

Output:

```text
Moon2Host.HostDeclSet
Moon2Tree.Module / Item* / Func*
Moon2Open.RegionFrag*
ParseIssue* for syntax or splice-kind failures
```

### 7.2 `host_decl_parse` / `host_decl_extract`

Question:

```text
Which `Moon2Host` declarations were produced by the `.mlua` parse/staging run?
```

Input:

```text
.mlua parse result
```

Output:

```text
HostDeclSet
```

### 7.3 `host_decl_validate`

Question:

```text
Are hosted declarations well-formed?
```

Input:

```text
HostDeclSet
```

Output:

```text
HostReport
```

Rejects include duplicate fields, ambiguous bool storage, invalid packed align,
unknown types, conflicting exposure names.

### 7.4 `host_layout_resolve`

Question:

```text
What byte layout does this struct declaration have on the target model?
```

Input:

```text
HostStructDecl + HostTargetModel + type environment
```

Output:

```text
HostTypeLayout
HostFieldLayout*
HostCdef
```

No Lua table/ffi reflection is the semantic source of truth. LuaJIT `ffi.sizeof`
and `ffi.offsetof` are validation checks against emitted facts.

### 7.5 `host_view_abi_plan`

Question:

```text
What descriptor crosses the boundary for ptr(T) or view(T)?
```

Input:

```text
HostExposeSubject + HostTypeLayout + HostTargetModel
```

Output:

```text
HostViewDescriptor for view(T)
HostTypeLayout for pointer/record subjects
```

### 7.6 `host_access_plan`

Question:

```text
How are field/index/len/data/stride/method access operations performed?
```

Input:

```text
HostAccessSubject
```

Output:

```text
HostAccessPlan
```

### 7.7 `host_lua_ffi_emit_plan`

Question:

```text
What Lua FFI cdefs/proxy families/accessors implement the access plan?
```

Input:

```text
HostFactSet filtered to Lua exposure
```

Output:

```text
HostLuaFfiPlan
```

### 7.8 `host_terra_emit_plan`

Question:

```text
What Terra declarations/accessors implement the same ABI?
```

Input:

```text
HostFactSet filtered to Terra exposure
```

Output:

```text
HostTerraPlan
```

### 7.9 `host_c_emit_plan`

Question:

```text
What C header declarations implement the same ABI?
```

Input:

```text
HostFactSet filtered to C exposure
```

Output:

```text
HostCPlan
```

### 7.10 `tree_field_resolve`

Question:

```text
What storage representation backs this source-level field access?
```

Input:

```text
ExprField / PlaceField candidate + HostTypeLayout
```

Output:

```text
FieldByOffset(field_name, offset, expose_ty, storage_rep)
```

This phase connects ordinary Moonlift field access to host layout facts.

### 7.11 `mlua_region_typecheck`

Question:

```text
What is the typed protocol of this source-level region declaration?
```

Input:

```text
region source ASDL, params, yield annotation, continuation declarations, local type env
```

Output:

```text
Moon2Open.RegionFrag
Region signature facts
TypeIssue* for invalid yield/jump/continuation use
```

### 7.12 `mlua_loop_expand`

Question:

```text
What explicit block/jump graph implements this source-level loop pattern?
```

Input:

```text
canonical block loop or counted-loop source pattern
```

Output:

```text
EntryControlBlock
ControlBlock*
StmtJump with named JumpArg values
```

No loop pattern may lower directly to backend commands. Every loop expands to the
same typed continuation/block/jump ASDL used by hand-authored blocks.

---

## 8. Moonlift field lowering

Current `FieldByOffset` only carries name/offset/type. It must become
representation-aware.

Required ASDL shape:

```asdl
FieldRef
  = FieldByName(string field_name, Moon2Type.Type ty)
  | FieldByOffset(string field_name,
                  number offset,
                  Moon2Type.Type expose_ty,
                  Moon2Host.HostFieldRep storage) unique
```

### 8.1 Load lowering

Scalar same-storage:

```text
load storage scalar
return same scalar
```

`bool32`:

```text
raw = load i32
value = raw != 0
```

`bool8`:

```text
raw = load u8
value = raw != 0
```

### 8.2 Store lowering

Scalar same-storage:

```text
store scalar
```

Boolean storage:

```text
raw = select bool_value ? 1 : 0
store storage scalar raw
```

This is not a Lua accessor rule. It is Moonlift object-code lowering.

---

## 9. Function ABI

### 9.1 Internal Moonlift ABI

Decision:

```text
Internal Moonlift view(T) ABI is always expanded as:
  data: ptr(T)
  len: index
  stride: index
```

This unifies contiguous and strided views.

Contiguous view construction sets:

```text
stride = 1
```

All lowering of `len(view)`, `view[i]`, windows, and field access uses this
three-value representation.

### 9.2 Public host ABI

Public C/Lua/Terra ABI uses descriptor pointers:

```c
int32_t count_active(MoonView_User* users);
```

Wrapper lowering:

```text
load users.data
load users.len
load users.stride
call internal count_active(data, len, stride)
```

The host ABI can also expose expanded raw form if explicitly requested:

```c
int32_t count_active_raw(User* data, intptr_t len, intptr_t stride);
```

ASDL:

```asdl
HostExportAbi
  = HostExportDescriptorPtr(Moon2Host.HostViewDescriptor descriptor)
  | HostExportExpandedScalars(Moon2Type.Type ty)
```

Default:

```text
public host ABI = descriptor pointer
internal Moonlift ABI = expanded scalars
```

### 9.3 View return ABI

Public host ABI for returning `view(T)` uses an output descriptor pointer:

```c
int32_t make_users(MoonView_User* out, ...);
```

Source sugar may allow:

```moonlift
export func make_users(...) -> view(User)
```

but lowering chooses out-descriptor ABI for host exports.

No ambiguous C struct-return ABI is used.

---

## 10. Lua FFI generated API

Given declarations:

```lua
struct User
    id: i32
    age: i32
    active: bool32
end

expose UserRef: ptr(User)

expose Users: view(User)
```

Generated Lua record API:

```lua
local user = UserRef.wrap(ptr, owner)

user.id
user.age
user.active
user:ptr()
user:pairs()
user:to_table()
```

Generated Lua view API:

```lua
local users = Users.wrap(desc, owner)

#users
users.len
users.stride
users[1].id
users[1].active
users:get_id(1)
users:get_active(1)
users:data()
users:ptr()
users:to_table()
```

### 10.1 Cost tiers

Ergonomic tier:

```lua
users[1].id
```

may create or reuse an element proxy.

Generated direct accessor tier:

```lua
users:get_id(1)
users:get_active(1)
```

performs direct pointer arithmetic and field reads.

Raw tier:

```lua
local p = users:data()
```

Native hot tier:

```lua
artifact.count_active(users)
```

passes a descriptor pointer to compiled code.

### 10.2 Mutability

Readonly exposure rejects mutation.

Mutable exposure generates explicit setters:

```lua
users:set_id(i, value)
users:set_active(i, value)
```

Decision:

```text
__newindex mutation remains disabled by default.
```

Dot assignment is only available if explicitly declared:

```lua
expose UserRef: ptr(User)
    lua proxy mutable dot_assign
end
```

Otherwise mutation must be explicit through setter methods.

---

## 11. Terra generated API

The same facts emit Terra declarations.

For `User`:

```lua
struct User {
    id: int32
    age: int32
    active: int32
}
```

For `view(User)`:

```lua
struct MoonView_User {
    data: &User
    len: intptr
    stride: intptr
}
```

Generated Terra helpers:

```lua
terra User_active(u: &User): bool
    return u.active ~= 0
end

terra Users_at(users: &MoonView_User, i: intptr): &User
    return users.data + i * users.stride
end

terra Users_get_active(users: &MoonView_User, i: intptr): bool
    return User_active(Users_at(users, i))
end
```

Terra consumes the same descriptors that Lua wraps and Moonlift exports.

No conversion.

---

## 12. C ABI emission

The same facts emit C declarations:

```c
typedef struct User {
    int32_t id;
    int32_t age;
    int32_t active;
} User;

typedef struct MoonView_User {
    User* data;
    intptr_t len;
    intptr_t stride;
} MoonView_User;
```

C ABI output is deterministic from `HostFactSet`.

Conflicts are rejects:

```text
HostRejectConflictingCdef(layout_id)
```

---

## 13. Ownership and lifetime

Descriptors do not own data.

Every Lua proxy pins an owner:

```text
source buffer
HostSession
artifact static data
external owner
borrowed generation token
```

ASDL:

```asdl
HostLifetime
  = HostLifetimeStatic
  | HostLifetimeOwned
  | HostLifetimeBorrowed(string owner_name)
  | HostLifetimeGeneration(uint64 session_id, uint32 generation)
  | HostLifetimeExternal(string name)
```

Lua runtime stores:

```lua
proxy[OWNER] = owner
```

Terra/C receive no automatic lifetime management; the caller owns that contract.

No Lua view wrapper may be created without an owner policy, even if the owner is
explicitly `HostLifetimeExternal` or `HostLifetimeStatic`.

---

## 14. JSON as one producer

JSON projection targets declared layouts.

```lua
struct User
    id: i32
    age: i32
    active: bool32
end

local projector = Json.project(User, {
    id = "$.id",
    age = "$.age",
    active = "$.active",
})
```

Generated Moonlift writes directly into:

```text
ptr(User)
```

Lua wraps:

```lua
local user = projector:decode(src)
print(user.id, user.active)
```

Anonymous current projection specs remain available, but they are defined as
sugar for an anonymous hosted struct declaration:

```text
struct JsonProjectionAnon17
    ...
end
```

Then the same layout/access/exposure pipeline is used.

This proves:

```text
JSON is a producer of declared layouts.
JSON does not own layout semantics.
```

---

## 15. Diagnostics and rejects

Diagnostics are ASDL values, not strings hidden in Lua code.

Required rejects:

```text
HostRejectAmbiguousBoolStorage(type, field)
HostRejectDuplicateField(type, field)
HostRejectDuplicateDecl(name)
HostRejectUnknownType(name)
HostRejectConflictingLayout(type)
HostRejectConflictingCdef(layout)
HostRejectUnsupportedStorage(field, storage)
HostRejectInvalidPackedAlign(type, align)
HostRejectViewOfUnsizedType(type)
HostRejectStrideUnitMismatch(subject)
HostRejectByteStrideForMoonliftView(subject)
HostRejectMutableBorrowedView(subject)
HostRejectUnpinnedLuaView(subject)
HostRejectTerraIncompatibleLayout(layout)
HostRejectCIncompatibleLayout(layout)
HostRejectBareBoolInBoundaryStruct(type, field)
HostRejectStructReturnAbi(type)
```

---

## 16. Complete end-to-end example

Hosted file:

```lua
struct User
    id: i32
    age: i32
    active: bool32
end

expose UserRef: ptr(User)

expose Users: view(User)

function User:is_adult()
    return self.age >= 18
end

func User:is_active_adult(self: ptr(User)) -> bool
    return self.active and self.age >= 18
end

module UserKernels
    export func count_active(users: view(User)) -> i32
        return block loop(i: index = 0, acc: i32 = 0) -> i32
            if i >= len(users) then yield acc end
            if users[i].active then
                jump loop(i = i + 1, acc = acc + 1)
            end
            jump loop(i = i + 1, acc = acc)
        end
    end
end
```

Generated C ABI:

```c
typedef struct User {
    int32_t id;
    int32_t age;
    int32_t active;
} User;

typedef struct MoonView_User {
    User* data;
    intptr_t len;
    intptr_t stride;
} MoonView_User;

int32_t UserKernels_count_active(MoonView_User* users);
```

Lua use:

```lua
local users = Users.wrap(desc, owner)

print(#users)
print(users[1].id)
print(users[1].active)
print(users[1]:is_adult())
print(users:get_active(1))

local n = UserKernels.count_active(users)
```

Terra use:

```lua
terra count_active_t(users: &MoonView_User)
    var acc: int32 = 0
    for i = 0, users.len do
        var u = users.data + i * users.stride
        if u.active ~= 0 then
            acc = acc + 1
        end
    end
    return acc
end
```

All paths share the same layout facts.

---

## 17. Implementation checklist

This is the checklist for the full design. Items are grouped by semantic layer,
not by convenience MVP.

### ASDL: hosted declarations

- [x] Add `HostDeclSet`
- [x] Add `HostDecl`
- [x] Add `HostStructDecl`
- [x] Add `HostRepr`
- [x] Add `HostFieldDecl`
- [x] Add `HostFieldAttr`
- [x] Add `HostStorageRep`
- [x] Add `HostAccessorDecl`
- [x] Add duplicate/invalid declaration rejects (`host_decl_validate.lua`, `test_host_decl_validate.lua`)

### ASDL: layout and target model

- [x] Add first `HostLayoutId`
- [x] Add first `HostFieldId`
- [x] Add first `HostTypeLayout`
- [x] Add first `HostFieldLayout`
- [x] Add first `HostFieldRep`
- [x] Add first `HostBoolEncoding`
- [x] Add `HostTargetModel`
- [x] Add `HostEndian`
- [x] Add `HostReprC` / `HostReprPacked`
- [x] Add layout rejects for bare bool, packed align, conflicting cdef (`test_host_target_model.lua`)

### ASDL: view ABI and exposure

- [x] Add `HostExposeSubject`
- [x] Add `HostStrideUnit`
- [x] Add `HostViewAbi`
- [x] Add `HostViewDescriptor`
- [x] Add `HostExposeTarget`
- [x] Add `HostMutability`
- [x] Add `HostBoundsPolicy`
- [x] Add first `HostExposeMode`
- [x] Extend `HostExposeMode` with mutability and bounds policy
- [x] Add `HostExposeAbi` and per-target `HostExposeFacet`
- [x] Add `HostExposeDecl`
- [x] Add `HostLifetime`

### ASDL: access plans

- [x] Add `HostAccessSubject`
- [x] Add first `HostAccessKey`
- [x] Add first `HostAccessOp`
- [x] Add first `HostAccessPlan`
- [x] Add view index/data/len/stride access ops
- [x] Add bool decode/encode access ops
- [x] Add materialization access over subjects

### ASDL: emission plans

- [x] Add first `HostCdef`
- [x] Add `HostLuaFfiPlan`
- [x] Add `HostTerraPlan`
- [x] Add `HostCPlan`
- [x] Add `HostExportAbi`
- [x] Add `HostFactLuaFfi`
- [x] Add `HostFactTerra`
- [x] Add `HostFactC`

### Moonlift semantics

- [x] Make `FieldRef.FieldByOffset` representation-aware
- [x] Lower bool-storage field loads through compare-to-zero
- [x] Lower bool-storage field stores through 0/1 encoding
- [x] Make internal `view(T)` ABI consistently `data,len,stride`
- [x] Update `type_func_abi_plan.lua` for three-value view params
- [x] Update `tree_to_back.lua` view env entries to carry stride always
- [x] Update `len(view)` lowering to use descriptor len
- [x] Update `view[i]` lowering to use element stride
- [x] Add host-export wrapper lowering from descriptor pointer to internal expanded ABI
- [x] Add out-descriptor host ABI for exported `view(T)` returns

### `.mlua` parser / source language

- [x] Parse `.mlua` as the integrated staged language, not as Lua plus source strings
- [x] Parse top-level `struct` declarations
- [x] Parse `repr(c)` and `repr(packed(N))`
- [x] Parse `bool8`, `bool32`, `bool stored T`
- [x] Reject bare `bool` in hosted boundary structs
- [x] Parse top-level name-first `expose Name: subject` / `expose Name: subject ... end` declarations
- [x] Parse Lua facet policies (`proxy`, readonly/mutable, checked/unchecked)
- [x] Parse Terra/C facet ABI policies (`descriptor`, `pointer`) separately from Lua policy
- [x] Let LuaJIT execute ordinary top-level Lua method declarations (`function Type:name(...) ... end`) and record resulting assignments as `HostAccessorLua`
- [x] Parse top-level Moonlift method declarations (`func Type:name(...) -> T ...`) as `HostAccessorMoonlift`
- [x] Parse top-level `region` declarations with typed params/yields
- [x] Parse continuation-region signatures with explicit `cont` exits
- [x] Parse top-level `module` declarations containing items/functions
- [x] Parse module-local `region` declarations inside `module` bodies
- [x] Parse top-level `func` and `export func` declarations
- [x] Parse canonical block-loop source forms
- [x] Parse counted-loop source pattern and lower it exactly to block/jump ASDL
- [x] Parse `emit Region(args...)` from functions/regions
- [ ] Allow hosted modules/functions/regions to see declared types by name
- [x] Allow antiquote/import for staged values at typed source sites
- [x] Reject splices whose ASDL kind does not match the source site
- [x] Provide Lua builder APIs that produce the same host-declaration ASDL as `.mlua` source
- [x] Route runnable `.mlua` files through the LuaJIT-first `host_quote.lua` hosted-island bridge for end-delimited `struct`, `expose`, `func Type:name`, named `module`, module-local regions, counted-loop sugar, and typed antiquote splices

### PVM phases

- [x] Implement integrated `mlua_parse`
- [x] Implement `host_decl_parse` / `host_decl_extract`
- [x] Implement `host_decl_validate`
- [x] Implement `host_layout_resolve`
- [x] Implement `host_view_abi_plan`
- [x] Implement `host_access_plan` for records/pointers/views
- [x] Implement `host_lua_ffi_emit_plan`
- [x] Implement `host_terra_emit_plan`
- [x] Implement `host_c_emit_plan`
- [x] Implement `tree_field_resolve` against `HostTypeLayout`
- [x] Implement `mlua_region_typecheck`
- [x] Implement `mlua_loop_expand`
- [x] Implement `mlua_host_pipeline`

### Lua runtime/accessors

- [x] Keep `value_proxy.lua` as generic proxy shell
- [x] Keep `buffer_view.lua` as bootstrap explicit-buffer runtime
- [ ] Make Lua accessor runtime consume `HostLuaFfiPlan` directly
- [ ] Generate record proxy families from `HostAccessPlan`
- [x] Generate view proxy families from `HostViewDescriptor` (`buffer_view.define_view_from_host_descriptor`)
- [x] Generate checked and unchecked index accessors
- [x] Generate direct `get_field(i)` accessors for views
- [ ] Generate explicit setters only for mutable exposure
- [ ] Keep `__newindex` disabled unless `dot_assign` is explicit
- [ ] Enforce owner/lifetime policy when wrapping descriptors

### Terra/C emission

- [ ] Emit Terra struct declarations from `HostTypeLayout`
- [ ] Emit Terra view descriptor declarations from `HostViewDescriptor`
- [ ] Emit Terra bool decode helpers
- [ ] Emit Terra direct view access helpers
- [ ] Emit C typedefs from `HostCPlan`
- [ ] Validate LuaJIT, Terra, and C offsets/sizes match `HostTypeLayout`

### JSON integration

- [ ] Let `Json.project(StructDecl, mapping)` target declared layouts
- [ ] Make anonymous JSON projection create anonymous hosted struct declarations
- [ ] Write projection output into `ptr(T)` using declared storage reps
- [ ] Wrap projection output through generated `ptr(T)` Lua API
- [ ] Keep current raw-buffer fast path for lowest-level benchmarks
- [ ] Keep generic JSON decode/view/table APIs removed from fast public path

### Benchmarks and validation

- [ ] Benchmark descriptor boundary pass overhead
- [ ] Benchmark `ptr(User).field` Lua FFI accessor
- [ ] Benchmark `view(User)[i].field` ergonomic path
- [ ] Benchmark `view(User):get_field(i)` direct path
- [ ] Benchmark Moonlift native loop over `view(User)`
- [ ] Benchmark Terra native loop over same `MoonView_User`
- [ ] Benchmark JSON projection into declared `User`
- [ ] Compare all against cjson selected-field extraction where relevant

---

## 18. Success criteria

The design is complete when all of these are true:

```text
1. `.mlua` parses as the integrated hosted language: Lua staging plus Moonlift
   top-level declarations/object code.
2. `.mlua` source structs, exposes, regions, loops, methods, modules, and funcs
   produce ASDL values directly.
3. Lua builder APIs produce the same ASDL values as equivalent `.mlua` source.
4. Hosted struct declarations produce ASDL layout facts.
5. Hosted exposure declarations produce Lua/Terra/C ABI/access facts.
6. Moonlift object code uses declared types as ptr(T) and view(T).
7. view(T) has one semantic model: data, len, element stride.
8. Lua wraps ptr/view descriptors without converting data.
9. Terra consumes the same descriptors without converting data.
10. JSON projection targets declared layouts as one producer among many.
11. Field loads/stores respect storage-vs-exposed representation.
12. Diagnostics are ASDL values.
13. Rust remains domain-neutral and contains no JSON/dynamic object arena.
```

In one sentence:

```text
.mlua hosted source declarations create ASDL-backed structs, views, regions,
loops, functions, and exposure facts; Moonlift code uses real Moonlift view
semantics; Lua/Terra/C accessors are generated from the same facts; crossing the
boundary passes only ptr(T) or MoonView_T descriptors.
```
