# Authoring with Moonlift

A pattern-oriented guide to the standard ways of building software with
Moonlift.

## 1. Philosophy

Moonlift has one coherent rule for metaprogramming:

```text
Lua builds Moonlift values.
@{x} splices one value.
@{xs...} spreads a Lua array of values.
Moonlift receives one monomorphic, typed program.
```

Lua is the metaprogramming language. Moonlift is the monomorphic target.
There is no separate macro language, no preprocessing stage, and no
source-level generics. **The builder API constructs typed ASDL nodes directly.**
When you want a function parameterized by type, you write a Lua function that
returns a Moonlift function specialized to that type.

### 1.1 The two roles of Lua

| Role | What it does |
|---|---|
| **Code generator** | Loops, conditionals, tables → monomorphic Moonlift programs |
| **Module system** | `require`, `dofile`, table returns → cross-file composition |
| **Configuration** | `os.getenv`, `arg`, config files → select what to compile |
| **Compilation driver** | `moon.loadstring`, `moon.bundle`, `moon.emit_object` → control compilation |

### 1.2 The basic workflow

```lua
-- 1. Load moonlift
local moon = require("moonlift")

-- 2. Build types and functions using the quoting API
local Vec3 = moon.struct[[ x: f32; y: f32; z: f32 end ]]
local add = moon.func[[ add(a: i32, b: i32) -> i32 return a + b end ]]

-- 3. Compile and call (or return for later use)
print(add(3, 4))  -- 7, compiles on first call
add:free()
```

---

## 2. The Quoting API

Every entry point follows the same shape: `moon.XXX` where `XXX` is `func`,
`region`, `struct`, `union`, `extern`, `expr`, `stmts`, or `type`.

### 2.1 Pure quote — no bindings

```lua
moon.func[[ add(a: i32, b: i32) -> i32 return a + b end ]]
moon.struct[[ Point x: f32; y: f32 end ]]
moon.extern[[ write(fd: i32, buf: ptr(u8), count: index) -> index ]]
moon.region[[ scan(p: ptr(u8), n: i32; hit: cont(pos: i32)) ... end ]]
```

The `[[ src ]]` syntax is Lua's long string literal. The source is parsed by the
Moonlift parser and returned as a typed ASDL value.

### 2.2 Bindings — `{values}[[src]]`

When the source contains `@{}` splices, bindings must be provided:

```lua
-- Type bindings for generic functions
moon.func{ T = moon.i32 }[[ add(a: @{T}, b: @{T}) -> @{T} ]]

-- Value bindings for cross-function references
moon.func{ helper = my_helper }[[
main(x: i32) -> i32
    return @{helper}(x)
end
]]
```

The `{values}` table maps binding names to Moonlift values (types, functions,
expressions). The `@{}` syntax in the source references these bindings by name.

### 2.3 Table builders — `moon.XXX{array}`

For programmatic construction of lists:

```lua
local params = moon.params {
    { name = "a", type = moon.i32 },
    { name = "b", type = moon.i32 },
}
local fields = moon.fields {
    { name = "x", type = moon.f32 },
    { name = "y", type = moon.f32 },
}
```

Table builders return plain ASDL values that can be stored, spliced, or
used in further construction.

---

## 3. The Signature Closure

**The fundamental metaprogramming primitive.** A Moonlift function or region
signature — without a body — is a first-class Lua value.

### 3.1 Creating a signature closure

```lua
-- A function signature, no body. Returns a closure.
local add = moon.func[[ add(a: i32, b: i32) -> i32 ]]
-- add is a Lua value carrying a typed ASDL signature
-- No code is compiled. No body exists. Just a contract.

-- A region protocol, no body.
local scan = moon.region[[ scan(p: ptr(u8), n: i32;
                                  hit: cont(pos: i32),
                                  miss: cont(pos: i32)) ]]
-- scan carries the protocol: params + continuations, no implementation.

-- Externs are always bodyless (the body is in a C library)
local write = moon.extern[[ write(fd: i32, buf: ptr(u8), count: index) -> index ]]
```

### 3.2 Five things a closure can do

```lua
local h = moon.func[[ add(a: i32, b: i32) -> i32 ]]

-- 1. STORE — put it in a table, return it from a module, pass it to a function
local module = { add = h }

-- 2. COMPILE — provide a body, get a callable native function
local f = h[[ return a + b end ]]
print(f(3, 4))  -- 7

-- 3. SPECIALIZE — override type bindings before compiling
local h2 = moon.func{ T = moon.i32 }[[ add(a: @{T}, b: @{T}) -> @{T} ]]
local f_f64 = h2{ T = moon.f64 }[[ return a + b end ]]  -- compiles as f64

-- 4. COMPOSE — pass as a dependency to another function
local user = moon.func{ dep = h }[[
    main(x: i32) -> i32
        return @{dep}(x, x)
    end
]]

-- 5. IGNORE — never compile, no error, no code produced
-- h just sits there as a Lua value
```

### 3.3 One-shot compilation

When you want both signature and body at once:

```lua
-- Curried call: sig then body
local f = moon.func[[ sub(a: i32, b: i32) -> i32 ]][[ return a - b end ]]
print(f(10, 3))  -- 7

-- Traditional: sig + body in one string
local g = moon.func[[ mul(a: i32, b: i32) -> i32 return a * b end ]]
print(g(6, 7))  -- 42
```

The curried form is syntactic sugar for the closure pattern. Internally,
`moon.func[[ sig ]][[ body ]]` is equivalent to creating the closure then
immediately providing the body.

---

## 4. The Header/Implementation Pattern

The signature closure enables a complete separation between **what** a module
provides (its interface) and **how** it is implemented (its bodies).

### 4.1 Header module (types.lua)

A header module returns ONLY signatures — products (structs, unions) and
protocols (function signatures, region protocols). No bodies.

```lua
-- types.lua
local moon = require("moonlift")
return {
    -- Products (always declaration-only)
    Vec3 = moon.struct[[ x: f32; y: f32; z: f32 end ]],
    Color = moon.struct[[ r: u8; g: u8; b: u8; a: u8 end ]],
    Mesh = moon.struct[[ verts: ptr(Vec3); colors: ptr(Color); count: i32 end ]],

    -- Protocols (function signatures without bodies)
    load_mesh = moon.func[[ load_mesh(path: ptr(u8)) -> ptr(Mesh) ]],
    free_mesh = moon.func[[ free_mesh(m: ptr(Mesh)) ]],
    render_mesh = moon.func{ T = moon.f32 }[[ render_mesh(m: ptr(Mesh), t: @{T}) ]],
}
```

This module IS the architecture. Every product and every protocol is visible
in one place. The implementations are separate concerns.

### 4.2 Implementation (app.mlua)

```lua
local types = require("types")

-- Provide bodies for each declared function
local load = types.load_mesh[[ return load_obj_file(path) end ]]
local free = types.free_mesh[[ free_obj_mesh(m) end ]]
local render = types.render_mesh{ T = moon.f32 }[[
    gl_bind_vertex_array(m.verts, m.count)
    gl_draw_elements(m.count)
end
]]
```

Each function is compiled independently. The typechecker verifies that the
implementation's signature matches the header declaration.

### 4.3 Multiple implementations

The same header can have multiple implementation files:

```lua
-- opengl_backend.mlua
local types = require("types")
return { render = types.render_mesh{ T = moon.f32 }[[ glDraw(...) end ]] }

-- vulkan_backend.mlua
local types = require("types")
return { render = types.render_mesh{ T = moon.f64 }[[ vkCmdDraw(...) end ]] }
```

Both backends are checked against the SAME header. If a backend provides a
body that doesn't match the declared signature, the compiler rejects it at
compile time.

### 4.4 Functions declared but never implemented

A function declared in the header that is never given a body simply produces
no code. There is no error, no warning, no undefined symbol. It exists as a
Lua closure — a contract that hasn't been fulfilled. Error occurs only at
link time if something tries to call it.

---

## 5. Generics Without Generators

Moonlift has no source-level generics. The bindings table IS the type parameter.
Lua functions generate specialized concrete Moonlift.

### 5.1 Type binding

```lua
-- Parameterize by type through the bindings table
local make_add = function(T)
    return moon.func{ T = T }[[ add(a: @{T}, b: @{T}) -> @{T} ]]
end

local add_i32 = make_add(moon.i32)[[ return a + b end ]]
local add_f64 = make_add(moon.f64)[[ return a + b end ]]

print(add_i32(3, 4))    -- 7
print(add_f64(3.5, 2.5)) -- 6.0
```

### 5.2 Parametric data structures

```lua
local Stack = {
    new  = moon.func{ T = moon.i32 }[[ new(capacity: i32) -> ptr(@{T}) ]],
    push = moon.func{ T = moon.i32 }[[ push(s: ptr(ptr(@{T})), v: @{T}) ]],
    pop  = moon.func{ T = moon.i32 }[[ pop(s: ptr(ptr(@{T}))) -> @{T} ]],
}

-- Specialize for f64
local pop_f64 = Stack.pop{ T = moon.f64 }[[
    local sp: ptr(f64) = s[0] - 1
    s[0] = sp
    return sp[0]
end
]]
```

No monomorphization pass. No type erasure. Each specialization is a separate
Lua closure call that produces a distinct native function.

### 5.3 Specialization with override

The header declares defaults. Implementations override to specialize:

```lua
-- Generic transform (default: f32)
local transform = moon.func{ T = moon.f32 }[[
    transform(v: ptr(Vec3), mat: @{T}) -> ptr(Vec3)
]]

-- Default (f32) implementation
local tf_f32 = transform{}[[ return apply_f32(v, mat) end ]]

-- Double-precision override
local tf_f64 = transform{ T = moon.f64 }[[ return apply_f64(v, mat) end ]]
```

Override follows Lua's shadowing rule: new bindings override old ones with the
same key. The header provides defaults. The implementation overrides what it
needs.

---

## 6. Module Assembly

Moonlift modules are ordinary Lua tables returned from `.mlua` files.
Composition uses standard Lua module patterns: `require`, `dofile`, and
table manipulation.

### 6.1 Bundle compilation

For multi-function artifacts that must be compiled together:

```lua
local b = moon.bundle("json_decoder")
b:add_func(parse_string)
b:add_func(parse_number)
b:add_func(parse_value)
b:add_func(decode)
b:add_region(skip_ws)
local compiled = b:compile()
local decode = compiled:get("decode")
print(decode(source_buffer))
```

### 6.2 Cross-function dependencies

When a function calls another function by name, declare it in the values table:

```lua
local helper = moon.func[[ helper(x: i32) -> i32 return x + 1 end ]]
local main = moon.func{ helper = helper }[[
    main(x: i32) -> i32
        return @{helper}(x)
    end
]]
print(main(5))  -- 6
```

The `@{helper}(x)` syntax makes the dependency explicit. The typechecker
resolves the name against the values table's entries.

### 6.3 Object and shared library emission

```lua
-- Emit a standalone .o file
local bytes = moon.emit_object([[
    func main() -> i32 return 42 end
]], "out.o", "my_program")

-- Emit a shared library
moon.emit_shared([[
    func compute(x: i32) -> i32 return x * x end
]], "lib.so", "libmath")
```

---

## 7. Region Composition

Regions are typed control fragments. They declare runtime parameters and a
protocol of named exits. Bodies are provided later — or inline.

### 7.1 Declaring a region protocol

```lua
-- Protocol only, no body (signature closure)
local scanner = moon.region[[
    scan(p: ptr(u8), n: i32, target: i32;
         hit: cont(pos: i32),
         miss: cont(pos: i32))
]]
-- scanner is a closure carrying the protocol
```

### 7.2 Providing the body

```lua
local scan_impl = scanner[[
scan(p: ptr(u8), n: i32, target: i32;
     hit: cont(pos: i32),
     miss: cont(pos: i32))
entry loop(i: i32 = 0)
    if i >= n then jump miss(pos = i) end
    if as(i32, p[i]) == target then jump hit(pos = i) end
    jump loop(i = i + 1)
end
end
]]
```

### 7.3 Composing regions with emit

```moonlift
return region -> i32
entry start()
    emit scanner(p, n, 65; hit = found, miss = notfound)
end
block found(pos: i32)
    yield pos
end
block notfound(pos: i32)
    yield -1
end
end
```

`emit` is a compile-time CFG splicing operation — zero-cost, not a function call.

---

## 8. Control Flow

Moonlift control is **jump-first**: no `for`, `while`, `break`, or `continue`.
All loops are expressed as typed blocks with explicit `jump` transitions.

### 8.1 The loop pattern

```moonlift
block loop(i: index = 0, acc: i32 = 0)
    if i >= n then yield acc end
    jump loop(i = i + 1, acc = acc + xs[i])
end
```

### 8.2 Switch dispatch

```moonlift
switch op do
case 1 then jump handle_add(a, b) end
case 2 then jump handle_sub(a, b) end
default then jump unknown_op() end
end
```

No fallthrough. Each case is an independent branch. Default arm is required.

### 8.3 Generating switch arms from Lua

```lua
local arms = {}
for i, name in ipairs(op_names) do
    arms[i] = { raw_key = tostring(i), body = moon.stmts[[ jump @{name}(a, b) end ]] }
end
```

```moonlift
switch opcode do
@{arms...}
default then jump unknown_op() end
end
```

---

## 9. Expressions and Types

### 9.1 Scalar types

`i8`, `i16`, `i32`, `i64`  — signed integers
`u8`, `u16`, `u32`, `u64`  — unsigned integers
`f32`, `f64`              — IEEE 754 floats
`bool`                     — 1-byte, values 0/1
`index`                    — pointer-sized integer
`void`                     — zero-size, return type only

### 9.2 Compound types

```moonlift
ptr(T)       -- pointer to one T
view(T)      -- typed memory sequence descriptor (data, len, stride)
[T; N]       -- fixed-length array
```

### 9.3 Type conversion

Only one form: `as(T, value)`. The compiler chooses the correct machine operation:

```moonlift
as(i32, byte_val)    -- unsigned byte → signed i32
as(f64, int_val)     -- integer → float
as(u8, wide_val)     -- truncation
```

### 9.4 Expressions in Lua

```lua
-- Quote form (parse any expression from string)
moon.expr [[x + 1]]
moon.expr [[select(x < 0, 0, x)]]
moon.expr [[as(i32, val)]]

-- Literal constructors (programmatic)
moon.int(42)
moon.bool_lit(true)
moon.string_lit("hello")
moon.float(3.14)

-- Arithmetic on expression values
e:add(other)  e:sub(other)  e:mul(other)  e:div(other)
e:neg()

-- Bitwise
e:band(other)  e:bor(other)  e:bxor(other)
e:shl(other)   e:ashr(other)  e:lshr(other)
```

---

## 10. Extern Functions

Externs declare C-ABI functions available at link time:

```lua
-- Simple extern
local strlen = moon.extern[[ strlen(s: ptr(u8)) -> index ]]

-- With explicit symbol name
local add7 = moon.extern[[ add7_impl(x: i32) -> i32 as "host_add7" ]]
```

Externs are always bodyless — the implementation lives in a C library.
They can be stored, passed, and composed like function headers.

For JIT compilation, register symbol addresses before compilation:

```lua
local jit = require("moonlift.back_jit").Define(T).jit()
jit:symbol("host_add7", ffi.cast("void*", c_func_ptr))
```

---

## 11. Splice Syntax

Splices inject Lua values into Moonlift source at parse time.

### 11.1 Value splice (`@{x}`)

Injects one value by name from the bindings table:

```lua
moon.func{ T = moon.i32 }[[ id(x: @{T}) -> @{T} return x end ]]
moon.stmts{ n = 10 }[[ let x: i32 = @{n} ]]
```

Valid in: type position, expression position, fragment position, name position.

### 11.2 Spread splice (`@{xs...}`)

Spreads a Lua array into a syntactic list:

```lua
local params = moon.params { { name = "x", type = moon.i32 }, { name = "y", type = moon.i32 } }
local fn = moon.func[[ add(@{params...}) -> i32 return x + y end ]]
```

```lua
local cases = {}
for i = 1, 5 do cases[i] = { raw_key = tostring(i), body = moon.stmts[[ jump handler_@{i}() end ]] } end
local dispatch = moon.stmts[[
    switch opcode do
    @{cases...}
    default then jump unknown() end
    end
]]
```

### 11.3 Splice fill errors

When a splice slot is used in a pure quote (no bindings table), the quoting
API produces an error:

```lua
moon.func[[ add(a: @{T}, b: @{T}) -> @{T} ]]
-- Error: moon.XXX[[]] does not evaluate @{}; use moon.XXX{values}[[src]] instead
```

---

## 12. Statements in Lua

Statements can be generated programmatically with `moon.stmts`:

```lua
local body = moon.stmts[[
    let x: i32 = a + b
    return x
]]
```

Statement lists compose naturally with functions and regions:

```lua
local fn = moon.func[[ do_work(n: i32) -> i32 ]]
fn.body = moon.stmts[[
    block loop(i: index = 0, acc: i32 = 0)
        if i >= n then return acc end
        jump loop(i = i + 1, acc = acc + i)
    end
]]
```

---

## 13. Error Messages

Errors are typed, structured, and span-resolved. Every error condition produces
a stable `E0xxx` code through a domain-specific explainer function.

### 13.1 Error code ranges

| Range | Domain | Examples |
|---|---|---|
| E0101–E0103 | Parse | Unexpected token, unterminated construct |
| E0201–E0203 | Name resolution | Unresolved name, duplicate name |
| E0301–E0305 | Type checking | Type mismatch, invalid operator |
| E0401–E0407 | Control flow | Unterminated block, yield outside region |
| E0501–E0506 | Host declarations | Duplicate field, boundary bool |
| E0601–E0603 | Backend validation | Missing function, duplicate definition |
| E0701–E0703 | Splices | Splice type mismatch, eval error |
| E0801–E0804 | Fragment expansion | Unfilled slot |
| E0901–E0905 | Link planning | Missing input, tool unavailable |
| E1001–E1005 | Vectorization | Loop not vectorized |
| E1101–E1105 | Source text apply | Edit range error |

### 13.2 Terminal output

```
ERROR[E0301]: type mismatch
  ┌─ file.mlua:2:9
   1 │ func main() -> i32
   2 │     let x: i32 = "hello"
     │         ^
   3 │     return x
   4 │ end

  = note: the initializer has type `ptr(u8)`, but the variable is declared as `i32`
```

Underlines use `^^^` for the primary error location. Notes explain WHY.
Suggestions (`= help:`) show HOW to fix.

### 13.3 Cascade suppression

When an unresolved name causes downstream type errors, only the root cause is
shown. The user sees `"unresolved name 'foo'"`, not 47 cascading type mismatches.

---

## 14. Memory and FFI

### 14.1 LuaJIT FFI integration

```lua
local ffi = require("ffi")
ffi.cdef[[
    typedef struct lua_State lua_State;
    void lua_pushnumber(lua_State* L, double n);
]]

local moon = require("moonlift")
local api = moon.extern[[ lua_pushnumber(L: ptr(u8), n: f64) ]]

-- Compile with symbol
local b = moon.bundle("lua_api")
b:add_func(api:implement[[ ... body ... ]])
local jit = b:jit()
jit:symbol("lua_pushnumber", ffi.C.lua_pushnumber)
```

### 14.2 Memory operations

```moonlift
let p: ptr(u8) = alloc(count)       -- allocate
*p = value                           -- store through pointer
let v: i32 = *p                      -- load through pointer
&value                               -- take address
p + offset                           -- pointer arithmetic with element offset
free(p)                              -- deallocate
```

---

## 15. Host Declarations

### 15.1 Structs

```lua
-- Quote form
local Point = moon.struct[[ x: f32; y: f32 end ]]

-- Inline assignment (name inferred)
local Point = struct x: f32; y: f32 end

-- Table builder
local fields = moon.fields { { name = "x", type = moon.f32 }, { name = "y", type = moon.f32 } }
local Point = moon.struct("Point", fields)
```

### 15.2 Unions

```lua
local Result = moon.union[[ ok(i32) | err(i32) end ]]
local Order = moon.union[[ asc | desc | none end ]]
```

### 15.3 Custom types from Lua

```lua
local ptr_i32 = moon.ptr(moon.i32)
local view_u8 = moon.view(moon.u8)
local func_type = moon.func_type({ moon.i32, moon.i32 }, moon.i32)
```

---

## 16. The Full Example

A complete header/implementation example showing products, protocols, and
two backends:

```lua
-- ==================== types.lua ====================
local moon = require("moonlift")
return {
    Vec3  = moon.struct[[ x: f32; y: f32; z: f32 end ]],
    Color = moon.struct[[ r: u8; g: u8; b: u8; a: u8 end ]],
    Mesh  = moon.struct[[ verts: ptr(Vec3); colors: ptr(Color); count: i32 end ]],

    load   = moon.func[[ load(path: ptr(u8)) -> ptr(Mesh) ]],
    free   = moon.func[[ free(m: ptr(Mesh)) ]],
    render = moon.func{ T = moon.f32 }[[ render(m: ptr(Mesh), t: @{T}) ]],
}
```

```lua
-- ==================== opengl.mlua ====================
local types = require("types")
local moon  = require("moonlift")

return {
    load   = types.load[[ return load_obj(path) end ]],
    free   = types.free[[ free_mesh(m) end ]],
    render = types.render{ T = moon.f32 }[[
        glBindVertexArray(m.verts)
        glDrawElements(m.count)
    end
    ]],
}
```

```lua
-- ==================== vulkan.mlua ====================
local types = require("types")
return {
    load   = types.load[[ return load_vk(path) end ]],
    free   = types.free[[ free_vk(m) end ]],
    render = types.render{ T = moon.f64 }[[ vkCmdDraw(m.verts, m.count) end ]],
}
```

Both backends implement the same protocol. Both are type-checked independently.
A third backend can be added without changing the header — just implement
against the same `types` module.

---

## 17. Design Method

The methodology paper describes Moonlift design as products and protocols:

> **Products** are data that exists together. Structs, views, pointers.
> **Protocols** are choices consumed by control. Region continuations.
> **Regions** relate products to protocols. Signatures as contracts.

### 17.1 The design procedure

1. **List the products.** All structs, enums, views, pointers. What data exists.
2. **List the protocols.** Every meaningful dispatch. Where control branches.
3. **Declare as headers.** Put products and protocols in a Lua module. Return only signatures.
4. **Provide implementations.** Fill bodies in separate modules. One per implementation strategy.
5. **Compile and use.** Pick implementations at load time. Swap for testing.

### 17.2 The header IS the architecture

A types.lua module is the design document — executable, type-checked, and
version-controlled. It tells you what data exists and how control flows.
The implementations are separate concerns.

---

## 18. Quick Reference

| Task | API |
|---|---|
| Parse function from source | `moon.func[[ src ]]` |
| Function signature only (header) | `moon.func[[ sig ]]` |
| Provide body to header | `header[[ body ]]` |
| Override type binding | `header{ T = new_T }[[ body ]]` |
| Parse struct/union | `moon.struct[[ ... ]]`, `moon.union[[ ... ]]` |
| Parse extern | `moon.extern[[ ... ]]` |
| Parse region | `moon.region[[ ... ]]` |
| Parse expression | `moon.expr[[ ... ]]` |
| Parse statements | `moon.stmts[[ ... ]]` |
| Value splice | `@{name}` in source, `{ name = value }` binding |
| Spread splice | `@{list...}` in source, `{ list = array }` binding |
| Compile multi-function | `moon.bundle("name")` then `:pack()` then `:jit()` |
| Emit .o file | `moon.emit_object(src, path, name)` |
| Emit .so/.dylib | `moon.emit_shared(src, path, name)` |
| Session (separate namespace) | `moon.new_session({ prefix = "name" })` |
| Access scalar type | `moon.i32`, `moon.f64`, `moon.u8`, etc. |
| Compound type | `moon.ptr(T)`, `moon.view(T)`, `moon.named(module, name)` |

---

## 19. Non-Obvious Patterns

### 19.1 Test mocks

```lua
local header = require("db_header")
local impl = os.getenv("TEST") and mock_impl or prod_impl
local query = header.query{ db = impl }[[ return @{db}.query(sql) end ]]
```

### 19.2 Conditional compilation

```lua
local features = { sse42 = true, avx2 = false }
local impl = features.avx2 and avx2_impl or sse_impl
```

### 19.3 Generated dispatch tables

```lua
local handlers = {}
for i, name in ipairs(op_names) do
    handlers[name] = moon.func[[ @{name}(a: i32, b: i32) -> i32 return @{i} end ]]
end
```

### 19.4 Platform-specific backends

```lua
local backend = ffi.os == "Windows" and win_backend or posix_backend
local open = backend.open[[ return open_impl(path) end ]]
```

---

## 20. Anti-patterns

- **Storing unions where protocols belong.** If a value carries a tag that some
  later code dispatches on, the dispatch logic should be a region protocol.
  Store encoded facts; dispatch with regions.
- **Returning result objects where continuations belong.** A function that
  returns `ok(value) | err(code)` should be a region with `ok(value)` and
  `err(code)` continuations at the composition site.
- **Status codes in product returns.** Boolean `try_recv() -> bool` should be
  `region recv(...; got: cont(...), empty: cont(), closed: cont())`.
- **Strings where sums belong.** Variant tags that are compared as strings.
  Use sum types (unions) or encoded facts consumed by a region.
