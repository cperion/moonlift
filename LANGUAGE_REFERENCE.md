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

Moonlift is not Lua with strings, and it is not a generic source language. Lua is
where genericity, templates, code generation, specialization, and dispatch-table
construction live. Moonlift object code is the generated/authorable monomorphic
language whose semantics are explicit in ASDL.

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

Lua genericity is real genericity. Moonlift source genericity does not exist.

### 1.2 Hosted declaration layer

Inside `.mlua`, Moonlift recognizes top-level hosted islands:

- `struct ... end`
- `expose Name: subject` or `expose Name: subject ... end`
- `func ... end`
- `module ... end`
- `region ... entry ... end ... end`
- `expr ... -> T ... end`

These islands construct ASDL values and host facts. They are not source strings
at runtime.

### 1.3 Moonlift object-code layer

Moonlift object code is the compiled low-level language:

```text
typed values
typed memory views
functions
regions
blocks
switches
emits
jumps
yields
returns
```

The central control model is:

```text
region = typed control fragment / machine boundary
cont   = typed output protocol
block  = typed continuation / state point
jump   = typed state transition
emit   = typed region or expression fragment use
switch = explicit dispatch
```

This is the low-level PVM idea. No extra micro-framework is required.

---

## 2. Non-negotiable language rules

### 2.1 No Moonlift source generics

Moonlift source has no type parameters and no source-level generic
instantiation.

Wrong language direction:

```text
id<T>(x: T)
foo<i32>(x)
```

Correct pattern:

```lua
local function make_id(T)
    return expr id_for_@{T}(x: @{T}) -> @{T}
        x
    end
end
```

Lua is the metaprogramming language. Moonlift receives the monomorphic result.

### 2.2 No angle-bracket type argument syntax

Moonlift source does not use angle brackets for type arguments or casts.

The single source-level conversion form is:

```moonlift
as(T, value)
```

Examples:

```moonlift
let x: i32 = as(i32, byte_value)
let y: f64 = as(f64, int_value)
```

`as(T, value)` is semantic conversion. The compiler chooses the concrete machine
operation from source and target types.

### 2.3 Explicit ASDL meaning

If a distinction matters to compilation, it must be represented as ASDL or as a
Lua-hosted value that constructs ASDL. Meaning must not hide in strings,
callbacks, mutable side tables, or ad hoc runtime tags.

### 2.4 Monomorphic object code

Every Moonlift function, region, block, continuation, and value has concrete
types when it reaches typecheck/lowering.

---

## 3. Files and execution surfaces

### 3.1 `.mlua`

A `.mlua` file is LuaJIT Lua with Moonlift hosted islands. It can be loaded by:

```lua
local Host = require("moonlift.host_quote")
local chunk = Host.loadfile("file.mlua")
local result = chunk()
```

or from the repo runner:

```bash
luajit run_mlua.lua file.mlua
```

### 3.2 Moonlift source strings

Moonlift modules/functions/regions can also be built from source strings through
`host_quote` or parsed directly through `moonlift.parse` / `moonlift.mlua_parse`.

### 3.3 Lua builder API

The raw source-node constructor API lives under:

```lua
local ast = require("moonlift.ast")
```

`moonlift.ast` returns plain `Moon2Core` / `Moon2Type` / `Moon2Tree` ASDL values
and carries LuaLS documentation for each exposed node constructor and table
field.  This is the field-by-field hosted form of the language reference.

The higher-level hosted value API lives under:

```lua
local moon = require("moonlift.host")
```

Both builder APIs construct ASDL values consumed by the same PVM phases. They are
not a second compiler IR.

---

## 4. Lexical rules

### 4.1 Whitespace

Whitespace separates tokens. Newlines separate statements in the newline/end
form. Hosted Moonlift islands are keyword/end-delimited; braces are not accepted
as alternate declaration or function delimiters.

### 4.2 Comments

Line comments:

```lua
-- comment
```

Lua long comments are skipped by the host island scanner.

### 4.3 Identifiers

```text
ident ::= [A-Za-z_][A-Za-z0-9_]*
path  ::= ident { "." ident }
```

### 4.4 Literals

```text
int_lit   ::= decimal or hexadecimal integer spelling
float_lit ::= decimal float spelling
bool_lit  ::= true | false
nil_lit   ::= nil
```

Numeric spellings are preserved first and interpreted by typed phases.

### 4.5 Reserved words

Core object-language reserved words:

```text
export extern func const static import type
struct union enum view ptr slice
noalias readonly writeonly requires bounds window_bounds disjoint same_len len
let var if then else switch case default do end
block control region entry jump yield return emit expr
true false nil and or not as select
```

Scalar type names are reserved in type position:

```text
void bool
i8 i16 i32 i64
u8 u16 u32 u64
f32 f64
index
```

Hosted boundary aliases:

```text
bool8 bool32
bool stored <scalar>
```

---

## 5. Type system

### 5.1 Scalar types

```text
void
bool
i8 i16 i32 i64
u8 u16 u32 u64
f32 f64
index
```

`index` is the canonical machine-sized indexing integer.

### 5.2 Pointers

Object code pointer type:

```moonlift
ptr(T)
```

Examples:

```moonlift
ptr(u8)
ptr(User)
```

`ptr(T)` means a pointer to one `T` value.

### 5.3 Views

Object code view type:

```moonlift
view(T)
```

A view is a typed memory sequence, not a single record.

Executable view ABI:

```text
data: ptr(T)
len: index
stride: index   -- stride in elements
```

Contiguous views use `stride = 1`.

### 5.4 Named types

Named types refer to declared structs/unions/enums or imported type paths.

```moonlift
User
Packet
```

### 5.5 Hosted boundary storage types

Hosted structs use exposed types plus storage facts.

```moonlift
active: bool8
active: bool32
active: bool stored i32
```

Bare hosted boundary `bool` storage is intentionally ambiguous and should be
rejected in host boundary structs.

### 5.6 Source-level genericity

There is none.

Use Lua to generate specialized concrete types/functions/fragments.

---

## 6. Modules and items

### 6.1 Module syntax

End-form object syntax:

```moonlift
module ::= item*
```

Hosted named module syntax:

```moonlift
module Name
    item*
end
```

A module contains functions, externs, consts, statics, type declarations, and
module-local regions/fragments in hosted syntax.

### 6.2 Functions

End-form:

```moonlift
[export] func name(param_list?) [-> type]
    requires_clause*
    stmt*
end
```

Function bodies are always end-delimited. The older hosted braced function form is rejected.

If the result type is omitted, the result is `void`.

Examples:

```moonlift
export func add(a: i32, b: i32) -> i32
    return a + b
end
```

### 6.3 Parameters

```text
param ::= modifier* name ":" type
modifier ::= noalias | readonly | writeonly
```

Parameter modifiers become source contracts.

Example:

```moonlift
export func sum(readonly xs: ptr(i32), n: i32) -> i32
    ...
end
```

### 6.4 Extern functions

```moonlift
extern func puts(x: ptr(u8)) -> i32
```

The local name is the default external symbol name unless an ABI phase provides a
more specific symbol policy.

### 6.5 Constants and statics

```moonlift
const answer: i32 = 42
static seed: i32 = answer
```

Constants are compile-time values in the supported const subset. Statics are
module-level storage/value declarations.

### 6.6 Type declarations

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
```

Hosted `.mlua` usually uses the top-level `struct` declaration form instead.

---

## 7. Hosted declarations

Hosted declarations are `.mlua` top-level islands that create `Moon2Host` facts
plus corresponding object-language ASDL where appropriate.

### 7.1 Structs

```moonlift
struct User
    id: i32
    age: i32
    active: bool32
end
```

Explicit representation:

```moonlift
struct Packet repr(packed(1))
    tag: u8
    len: u32
end
```

Default representation is `repr(c)`.

Struct facts include:

```text
HostStructDecl
HostFieldDecl
HostTypeLayout
HostFieldLayout
Moon2Tree.TypeDeclStruct
```

### 7.2 Field attributes

Field type attributes are suffixes:

```moonlift
field: i32 readonly
field: ptr(u8) noalias
field: view(i32) mutable
```

### 7.3 Expose declarations

```moonlift
expose UserRef: ptr(User)
expose Users: view(User)

expose MutableUserRef: ptr(User)
    lua mutable
end

expose LuaOnlyUsers: view(User)
    lua
end
```

An expose declaration names the public host surface first, then the semantic
subject. A one-line declaration means the default Lua + Terra + C facets. If an
end-delimited body is present, each line names a target followed by optional
policy override words. A bare target line means that target's default facet.

Expose targets:

```text
lua
terra
c
moonlift
```

Facet policy words:

```text
proxy | typed_record | buffer_view
descriptor | pointer | data_len_stride | expanded_scalars
readonly | mutable | interior_mutable
checked | unchecked
eager_table | full_copy | borrowed_view
```

Defaults:

```text
Lua view/ptr facets: proxy readonly checked
C/Terra ptr facets: pointer readonly unchecked
C/Terra view facets: descriptor readonly unchecked
Internal Moonlift view ABI: data,len,stride
```

### 7.4 Lua-hosted methods

Ordinary Lua method syntax attaches host-side proxy methods:

```lua
function User:is_adult()
    return self.age >= 18
end
```

These are Lua closures over generated proxy accessors and are recorded as host
accessor facts.

### 7.5 Moonlift-native methods

Moonlift-native methods use `func Type:name`:

```moonlift
func User:is_active(self: ptr(User)) -> bool
    return self.active
end
```

They compile as ordinary Moonlift object functions with stable generated symbols
and are recorded as native host accessor facts.

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
       | expr_stmt
```

### 8.2 Let and var

```moonlift
let name: T = expr
var name: T = expr
```

`let` creates an immutable value binding. `var` creates a mutable cell binding.

### 8.3 Assignment

```moonlift
place = expr
```

Places include refs, index places, and field places where supported by the typed
phases.

### 8.4 If statement

```moonlift
if cond then
    stmt*
else
    stmt*
end
```

Single-line hosted island examples often normalize forms such as:

```moonlift
if cond then jump done(v = x) end
```

### 8.5 Switch statement

```moonlift
switch value do
case key then
    stmt*
default then
    stmt*
end
```

Switch has no fallthrough. Cases are explicit control branches.

In direct builders, the equivalent is:

```lua
block:switch_(value, {
    { key = 0, body = function(case) ... end },
}, function(default) ... end)
```

### 8.6 Emit statement

Region fragment emit:

```moonlift
emit fragment(arg1, arg2; exit1 = block1, exit2 = block2)
```

`emit` splices/installs the fragment control graph into the surrounding region.
It is not a runtime callback.

Continuation fills can target local blocks or enclosing continuation slots.

### 8.7 Jump statement

```moonlift
jump label(name = expr, ...)
```

Jump arguments are named, not positional. A jump terminates the current path.

### 8.8 Yield statement

```moonlift
yield
yield expr
```

`yield` exits the nearest control region. Value-yielding control regions require
`yield expr` of the declared region result type. Void statement regions require
bare `yield`.

### 8.9 Return statement

```moonlift
return
return expr
```

`return` exits the enclosing function, not merely the local control region.

### 8.10 Expression statement

An expression can appear as a statement, mainly for calls or void intrinsics.

---

## 9. Expressions

### 9.1 Expression categories

```text
expr ::= literal
       | name
       | call
       | field
       | index
       | unary
       | binary
       | comparison
       | logic
       | as_expr
       | select_expr
       | len_expr
       | view_expr
       | emit_expr
       | control_expr
```

### 9.2 Conversion

```moonlift
as(type, expr)
```

This is the only source-level conversion form. It is semantic and monomorphic.

Examples:

```moonlift
let c: i32 = as(i32, p[i])
let x: f64 = as(f64, count)
```

### 9.3 Select

```moonlift
select(cond, then_expr, else_expr)
```

`select` is dataflow choice, distinct from control-flow `if`.

### 9.4 Len

```moonlift
len(view_expr)
```

Returns `index`.

### 9.5 View construction

```moonlift
view(data, len)
view(data, len, stride)
view_window(base, start, len)
```

`stride` is in elements.

### 9.6 Calls

```moonlift
callee(arg1, arg2)
```

Call target resolution is a semantic phase. Calls can resolve to direct,
extern, indirect, closure, or unresolved targets.

### 9.7 Emit expression

Expression fragment emit:

```moonlift
emit fragment(arg1, arg2)
```

Expression fragments return a typed expression result and lower through
`ExprUseExprFrag`.

### 9.8 Field and index

```moonlift
base.field
base[index]
```

Dotted syntax is preserved first and resolved later. It can mean field access or
qualified binding path depending on context.

### 9.9 Unary operators

```text
-     numeric negation
not   boolean not
~     bitwise not
```

Pointer/address unary forms exist at the ASDL/builder level where supported by
place typing and lowering.

### 9.10 Binary operators

Precedence, low to high:

```text
or
and
== ~= < <= > >=
|
~
&
+ -
* / %
unary
call / field / index
```

Operators are typed by later phases.

---

## 10. Control regions

Control regions are the heart of Moonlift.

### 10.1 Single-block control statement

```moonlift
block loop(i: index = 0)
    if i >= n then
        yield
    end
    jump loop(i = i + 1)
end
```

A void `yield` exits the control statement and continues after it.

### 10.2 Single-block control expression

```moonlift
let total: i32 = block loop(i: index = 0, acc: i32 = 0) -> i32
    if i >= n then
        yield acc
    end
    jump loop(i = i + 1, acc = acc + xs[i])
end
```

### 10.3 Multi-block control expression

```moonlift
return control -> i32
entry start()
    jump loop(i = 0, acc = 0)
end
block loop(i: index, acc: i32)
    if i >= n then yield acc end
    jump loop(i = i + 1, acc = acc + xs[i])
end
end
```

Some examples use `block` instead of `entry` for the first block; the first block
is the entry block.

### 10.4 Block parameters

Entry block parameters have initializers:

```moonlift
block loop(i: index = 0, acc: i32 = 0)
```

Non-entry block parameters are target signatures:

```moonlift
block done(value: i32)
```

### 10.5 Termination

Every control-block path must terminate with one of:

- `jump ...`
- `yield ...`
- `return ...`
- a terminating intrinsic/fact such as trap
- an `if`/`switch` whose all paths terminate

There is no implicit fallthrough between control blocks.

### 10.6 Validation facts

Control validation produces explicit facts/rejects:

- labels
- params
- jump edges
- jump args
- yields
- returns
- backedges
- duplicate/missing labels
- missing/extra/duplicate jump args
- type mismatches
- unterminated blocks

Optimization consumes facts and decisions, not parser guesses.

---

## 11. Region fragments and continuation protocols

### 11.1 Region fragment declaration

```moonlift
region scan_until(p: ptr(u8), n: i32, target: i32;
                  hit: cont(pos: i32),
                  miss: cont(pos: i32))
entry loop(i: i32 = 0)
    if i >= n then jump miss(pos = i) end
    if as(i32, p[i]) == target then jump hit(pos = i) end
    jump loop(i = i + 1)
end
end
```

A region fragment is a typed control component. Its continuation list is its
output protocol.

### 11.2 Emit use

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

The caller decides what each exit means.

### 11.3 Continuation forwarding

A fragment can emit another fragment and forward exits to its own continuation
slots:

```moonlift
region wrapper(p: ptr(u8), n: i32; out: cont(pos: i32))
entry start()
    emit inner(p, n; hit = out)
end
end
```

Forwarding is represented as `SlotValueContSlot` and expands to ordinary jumps.

---

## 12. Expression fragments

Expression fragments are staged scalar/dataflow components.

```moonlift
expr clamp_nonneg(x: i32) -> i32
    select(x < 0, 0, x)
end
```

Use:

```moonlift
let score: i32 = emit clamp_nonneg(v)
```

Lua can generate expression fragment families:

```lua
local function positive_after(tag, pivot)
    return expr positive_after_@{tag}(x: i32) -> i32
        select(x > @{pivot}, x - @{pivot}, 0)
    end
end
```

---

## 13. Contracts

Function parameters and `requires` clauses produce binding-backed contract facts.

### 13.1 Parameter modifiers

```moonlift
func f(noalias readonly xs: ptr(i32), n: i32) -> i32
    ...
end
```

### 13.2 Requires clauses

```moonlift
requires bounds(ptr, len)
requires window_bounds(base, base_len, start, len)
requires disjoint(a, b)
requires same_len(a, b)
requires noalias(x)
requires readonly(x)
requires writeonly(x)
```

Contracts are consumed by vector safety and alias/proof decisions.

---

## 14. Lua splicing and antiquote

Inside hosted source islands, Lua values are spliced with:

```moonlift
@{lua_expr}
```

The splice expected kind is determined by source position:

- type position expects a type value
- expression position expects an expression/literal value
- `emit @{fragment}` expects a region or expression fragment
- declaration/module sites expect declaration/module values where supported

Examples:

```lua
local T = moon.i32
local inc = expr inc(x: @{T}) -> @{T}
    x + 1
end
```

```lua
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
```

Splicing inserts typed ASDL values, never raw source text.

---

## 15. Lua builder API reference

The builder API mirrors source constructs. Names below are representative public
surface, not a separate semantic model.

### 15.1 Sessions

```lua
local moon = require("moonlift.host")
local session = moon.new_session({ prefix = "demo" })
local api = session:api()
```

The default `moon` object is itself a hosted API.

### 15.2 Types

```lua
moon.void
moon.bool
moon.i8;  moon.i16;  moon.i32;  moon.i64
moon.u8;  moon.u16;  moon.u32;  moon.u64
moon.f32; moon.f64
moon.index
moon.ptr(T)
moon.view(T)
moon.named(module, name)
moon.path_named(name)
```

### 15.3 Expressions

```lua
moon.int(42)
moon.float("1.5")
moon.bool_lit(true)
expr:as(T)
expr:eq(other)
expr:lt(other)
expr:field("name", T)
expr:index(i)
moon.select(cond, a, b)
moon.load(addr, T)
moon.addr_of(place)
```

### 15.4 Parameters and functions

```lua
moon.param("x", moon.i32)

local M = moon.module("Demo")
M:export_func("add", {
    moon.param("a", moon.i32),
    moon.param("b", moon.i32),
}, moon.i32, function(fn)
    fn:return_(fn.a + fn.b)
end)
```

### 15.5 Regions

```lua
local frag = moon.region_frag("route", {
    moon.param("x", moon.i32),
}, {
    out = moon.cont({ moon.param("v", moon.i32) }),
}, function(r)
    r:entry("start", {}, function(start)
        start:jump(r.out, { v = r.x })
    end)
end)
```

Block builder methods:

```lua
block:jump(target, named_args)
block:yield_(expr?)
block:return_(expr?)
block:emit(fragment, runtime_args, fills)
block:if_(cond, then_fn, else_fn?)
block:switch_(value, arms, default_fn?)
```

### 15.6 Fragments

Expression fragments:

```lua
moon.expr_frag("inc", { moon.param("x", moon.i32) }, moon.i32, function(e)
    return e.x + 1
end)

moon.emit_expr(fragment, { arg })
```

Templates are ordinary Lua functions returning concrete fragments.

### 15.7 Modules and JIT

```lua
local compiled = M:compile()
local add = compiled:get("add")
print(add(1, 2))
compiled:free()
```

---

## 16. View and host ABI semantics

### 16.1 Canonical view descriptor

```c
typedef struct MoonView_T {
    T* data;
    intptr_t len;
    intptr_t stride;
} MoonView_T;
```

Stride is in elements.

### 16.2 Indexing

```text
addr(i) = data + i * stride * sizeof(T)
```

### 16.3 Windowing

```text
data'   = data + start * stride * sizeof(T)
len'    = requested_len
stride' = stride
```

### 16.4 Lua proxy semantics

For `ptr(User)`:

```lua
user.id
```

For `view(User)`:

```lua
users[1].id
#users
users:get_id(1)
```

Lua proxies are exposure/access facets of Moonlift views, not a separate view
model.

---

## 17. Vectorization and facts

Moonlift vectorization consumes explicit facts:

- counted-loop facts derived from block params and backedges
- memory base/access/store facts
- alias/dependence facts
- bounds obligations and decisions
- target feature facts
- vector kernel plans
- explicit rejects for unsupported shapes

Source syntax does not secretly promise vectorization. It supplies typed control
and contracts; phases decide.

Canonical counted shape:

```moonlift
block loop(i: index = 0, acc: i32 = 0)
    if i >= n then yield acc end
    jump loop(i = i + 1, acc = acc + xs[i])
end
```

---

## 18. Error and diagnostic model

Moonlift diagnostics are ASDL values:

- parse issues
- host declaration rejects
- open slot/fill issues
- type issues
- control rejects
- vector rejects
- backend validation issues

Tools and LSP features should consume these facts. They should not rediscover
language semantics from raw text.

---

## 19. Complete examples

### 19.1 Typed dispatch over bytes

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

### 19.2 Switch + emit dispatch

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

### 19.3 Lua-generated monomorphic fragments

```lua
local function expect_byte(tag, byte, err_code)
    return region expect_@{tag}(p: ptr(u8), n: i32, pos: i32;
        ok: cont(next: i32), err: cont(pos: i32, code: i32))
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
```

### 19.4 Host declaration + native method

```lua
struct User
    id: i32
    active: bool32
end

expose Users: view(User)

func User:is_active(self: ptr(User)) -> bool
    return self.active
end
```

---

## 20. Implementation/layer map

Important implementation homes:

```text
lua/moonlift/parse.lua                  object source parser
lua/moonlift/mlua_parse.lua             .mlua hosted island parser
lua/moonlift/host_quote.lua             LuaJIT hosted island bridge
lua/moonlift/host_*_values.lua          Lua builder values
lua/moonlift/open_expand.lua            slot/fill/fragment expansion
lua/moonlift/tree_typecheck.lua         typecheck/name resolution
lua/moonlift/tree_control_facts.lua     control validation facts
lua/moonlift/tree_control_to_back.lua   region/control lowering
lua/moonlift/tree_to_back.lua           tree -> flat backend commands
lua/moonlift/vec_*                      vector facts/decisions/lowering
lua/moonlift/host_*_plan.lua            host layout/view/access/emission
```

---

## 21. Summary doctrine

Moonlift source is small on purpose:

```text
monomorphic typed data
+ typed regions
+ explicit continuation exits
+ switch/emit/jump composition
+ semantic as(T, value) conversion
```

Lua supplies all genericity.

The backend consumes flat facts/commands.

No hidden generic source layer is needed because Moonlift's control language is
already the low-level composition model.
