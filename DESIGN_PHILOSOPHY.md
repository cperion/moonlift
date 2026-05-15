# The Moonlift Design Philosophy

## Programming is co-authoring two typed structures

Every program is two things:

1. **A type forest** — what data exists, what shapes it takes, what invariants hold
2. **A control graph** — what happens, in what order, under what conditions

For sixty years, programming languages gave us a type system for the first one
and nothing for the second one. We typed our data (`int`, `struct`, `List<T>`)
and left our control flow untyped (`goto`, `break`, `return`, exceptions,
callbacks). Then we spent decades building crutches — monads, effect systems,
async/await, generators — to get the missing type safety back.

Moonlift gives both structures a type system.

---

## Part 1: The type forest (data types)

The first typing layer is about values. What data exists, what shapes it takes,
what invariants hold. This is the familiar part.

```
Types:   void, bool, i8..i64, u8..u64, f32, f64, index
         ptr(T), view(T)
         structs, tagged unions, enums
```

A `view(i32)` is a typed memory sequence — pointer, length, stride — with
bounds-checked indexing. A `struct User { id: i32, age: i32 }` has known
layout. A `tagged union Result = ok(i32) | err(i32)` has a discriminant
and payload.

Type checking ensures:
- Values flow through compatible types
- Memory accesses are bounds-checked
- Struct fields exist at compile time
- Tagged unions are exhaustively matched

This is table stakes. Every typed language does this.

---

## Part 2: The control graph (continuation types)

The second typing layer is about control flow. Where does execution go?
What state does it carry? What exits are possible?

Moonlift's primitive for this is the **region** — a typed control-flow
fragment that declares a continuation protocol:

```
region scan_until(p: ptr(u8), n: i32, target: i32;
                  hit: cont(pos: i32),
                  miss: cont(pos: i32))
```

The semicolon divides two things:
- **Before the `;`** — runtime parameters (data flowing in)
- **After the `;`** — continuation slots (control flowing out)

Each continuation is typed: `hit: cont(pos: i32)` means "this region can
exit via `hit`, carrying an `i32` position." `miss: cont(pos: i32)` means
"this region can exit via `miss`, carrying an `i32` position."

The control graph has its own type system:

- **Continuation declarations** are the control graph's field types.
  Just as a struct declares `id: i32, age: i32`, a region declares
  `hit: cont(pos: i32), miss: cont(pos: i32)`.

- **Continuation fills** are the control graph's value bindings.
  Just as a struct literal sets `{ id = 42, age = 30 }`, an emit site
  maps exits to blocks: `emit scan(..., p, n; hit = found, miss = missing)`.

- **Continuation forwarding** is the control graph's type composition.
  `emit inner(p, n; hit = out)` means "inner's `hit` exit maps to my `out`
  continuation." The types must match. The compiler checks this.

- **Blocks** are the control graph's named states. A block label with
  typed parameters IS a state declaration: `block found(pos: i32)` means
  "I am in the `found` state, carrying a position."

The compiler type-checks the control graph:
- Every continuation declared by a region must be filled at every emit site
- Every fill must match the continuation's parameter types
- Every block label referenced by a jump must exist
- Every jump must provide arguments matching the target block's parameter types
- Every path through a control region must terminate explicitly (no fallthrough)

---

## Part 3: Regions are the bridge

A region links the two typing systems. Its runtime parameters are data
types. Its continuations are control types. The body contains both — data
operations (arithmetic, loads, stores, explicit atomics) and control operations
(jumps, emits).

```
region my_region(
    data_in: i32,              ← data type
    data_in2: ptr(u8);         ← data type
    ok: cont(result: i32),     ← control type
    err: cont(code: i32)       ← control type
)
```

This is the fundamental unit of composition. Not a function. Not a class.
Not a module. A typed control fragment with named exits.

---

## Part 4: Composition without overhead

Regions compose via `emit`:

```
emit scan(args; hit = handle_hit, miss = handle_miss)
```

`emit` does not call. It splices. The callee's blocks are merged into the
caller's control-flow graph. No stack frame. No return address. No call
overhead. The compiler sees one merged CFG.

This means composition is zero-cost. You can nest regions ten levels deep
and the compiled output is one flat function with internal branches.

Functions still exist (`func f(x: i32) -> i32`). They are the right primitive
when the control flow is settled — the exits are known, the interface is
stable, the memory layout is final. Functions seal a region into a callable
unit with one entry and one return.

The design principle: **compose with regions, seal with functions.**

---

## Part 5: The PVM bridges intent to execution

The type forest and control graph are authored intent. The machine needs
a flat command array. The PVM bridges the gap.

Each PVM phase is a fact-gathering iterator over ASDL nodes:

```
parse → typecheck → lower → validate → emit
  ↓        ↓         ↓        ↓        ↓
ASDL     typed     MoonBack  facts    BackCmd
Tree     Tree      program   report   tape
```

Phases are memoized. When one subtree changes, only that subtree recompiles.
The rest is served from cache. This is what makes the IDE live — diagnostics,
completion, hover — all query the phase cache.

The final output is a BackCmd tape — a flat, verifiable array of typed
operations. A VM (Cranelift, or the Moonlift VM after bootstrap) executes it.
Atomics follow the same rule: they are typed commands with explicit memory facts
and ordering, not magic annotations on variables. The loop is the only thing
that runs.

---

## Part 6: The co-authoring model

When you design software in Moonlift, you are co-authoring two structures:

**The type forest** — what data exists:
```
struct User { id: i32, age: i32 }
type Result = ok(i32) | err(i32)
expose Users: view(User)
```

**The control graph** — what happens:
```
region process_user(u: ptr(User);
    valid: cont(), invalid: cont(code: i32))
entry start()
    if u.age < 0 then jump invalid(code = 1) end
    jump valid()
end
end
```

The two structures are linked: every jump carries typed values, every
region declares typed exits, every block declares typed parameters.
The compiler checks the consistency of both structures simultaneously.

This is not MVC. This is not OOP. This is not FP. This is something
else — a model where the types and the control flow are equally first-class,
equally typed, equally checkable.

---

## Part 7: The metaprogramming layer — region factories

Moonlift source has no generics. No type parameters, no angle brackets,
no template instantiation. Instead, genericity lives in Lua.

A **region factory** is a Lua function that returns a Moonlift region:

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
```

`expect_A` and `expect_B` are distinct, monomorphic, differently-named
regions. The Lua function is the factory. The output is concrete typed
control-flow fragments. No generics exist in the compiled code.

This separation is deliberate:

- **Lua**: abstraction, iteration, code generation, specialization.
  The meta-layer. Fast (LuaJIT JIT). Flexible (full language).

- **Moonlift**: monomorphic execution. Typed blocks. Typed jumps.
  Zero-overhead composition. The target layer.

The splice `@{lua_expr}` inserts typed ASDL values — types, constants,
fragment names — at compile time. No string templating. No textual
substitution. The parser sees a complete, monomorphic Moonlift program
with all types resolved.

Region factories are the natural generalization of:
- **Generic functions** → Lua function returning a Moonlift function
- **Generic types** → Lua function returning a Moonlift struct
- **Parser combinators** → Lua function returning a Moonlift region
- **Code generators** → Lua script producing a Moonlift module

Metaprogramming IS eating boilerplate. And Lua is the boilerplate-eating
machine. Moonlift receives only the result.

## Part 8: Why this matters

**Without continuation types**, every control-flow decision becomes a
function return value. You encode "what happens next" as data (`Result<T,E>`,
`Option<T>`, exceptions, callbacks) and check it at every call site. The
type system grows monads and effect handlers to patch the gap. The runtime
pays for heap allocations, virtual dispatch, and branch misprediction.

**With continuation types**, control flow is just control flow. A region
declares its exits. An emit site fills them. The compiler checks the wiring.
The runtime executes jumps. No encoding. No decoding. No overhead.

The planet pays the electricity bill for sixty years of "functions are the
only way to organize code." Every monadic bind, every async state machine
boxed on the heap, every virtual dispatch through an effect handler — that's
real silicon spending real watts. Continuation types eliminate an entire
class of runtime overhead.

---

## Summary

| Concern | Traditional | Moonlift |
|---------|------------|----------|
| Data types | Structs, enums, generics | Structs, tagged unions, views |
| Control types | None (functions only) | Continuation protocols on regions |
| Composition | Function calls (overhead) | Emit (zero-cost CFG splicing) |
| State | Mutable variables | Block labels with typed params |
| Type checking | Data only | Data + control graph |
| Metaprogramming | Templates, macros, reflection | Lua region factories + ASDL values |
| Incrementality | Manual cache invalidation | PVM phases (auto-cached) |
| Bootstrapping | External toolchain | vm.mlua (500 lines, one Cranelift call) |

The design is not "a language with regions." The design is a system where
the control graph has a type system, and the data types and control types
are co-authored, co-checked, and co-compiled. Moonlift is the surface
syntax for that system.
