# MoonBack LuaJIT Backend: ASDL-First Full Compiler Design

**Status:** target architecture for a hard refactor.

**Scope:** replace the current rough `lua/moonlift/back_luajit.lua` with a pure
LuaJIT code-generation backend that covers the full semantic surface currently
accepted by the Rust/Cranelift executable backend.

**Non-goals:**

- No incremental preservation of the current `back_luajit.lua` architecture.
- No compatibility shim around the current file shape.
- No tape-interpreter backend hidden behind Lua source generation.
- No artifact/getpointer compatibility veneer whose purpose is to keep old tests
  passing.
- No partial backend declared as complete. Tests are expected to be refactored to
  the new backend contract after the backend design is implemented.

The design is ASDL-first: the source of truth is `MoonBack.BackProgram` and the
MoonBack ASDL schema. The existing Rust/Cranelift backend is used to identify
current semantics and coverage, not as an API shape to emulate.

---

## 1. Goal

The LuaJIT backend is a compiler from MoonBack ASDL commands to Lua source that
LuaJIT can trace into native machine code. It should be able to execute any
well-formed MoonBack program accepted by the current Rust/Cranelift executable
backend, including scalar arithmetic, memory, stack slots, data objects, calls,
control flow, and vectors.

The generated Lua must be intentionally shaped for LuaJIT:

- one hygienically generated module closure;
- forward-declared generated functions;
- explicit local variables for IR values;
- `goto`-based control flow;
- no per-instruction dispatch loop;
- no hot-path allocation for tables or closures;
- no dynamic command interpretation after compile time;
- captured runtime helpers and FFI ctypes via `quote.lua`;
- exact representation rules for MoonBack values.

The backend substitutes the Cranelift lowering layer for execution, not the
native object-file artifact layer. Pure LuaJIT can execute generated code but it
cannot emit relocatable machine-code objects without a separate assembler/object
writer. Because this refactor explicitly rejects backwards compatibility shims,
the LuaJIT backend has its own ASDL-level output contract instead of pretending
to be the Rust artifact API.

---

## 2. Backend contract

### 2.1 Public module API

`lua/moonlift/back_luajit.lua` exposes:

```lua
local api = require("moonlift.back_luajit").Define(T, opts)
local artifact = api.compile(program, compile_opts)
```

`compile` accepts a `MoonBack.BackProgram` and returns a `LuaJITModuleArtifact`:

```lua
LuaJITModuleArtifact = {
  module = <export table>,        -- exported functions by original function id text
  functions = { [fid_text] = fn }, -- all generated functions by original id text
  source = <generated Lua source>, -- full generated source, for diagnostics
  meta = <compiler metadata>,      -- signatures, data, value layouts, etc.
}
```

The exported function table is the canonical execution interface:

```lua
artifact.module.add_i32(20, 22)
```

All keys use original MoonBack function id text. Generated Lua identifiers are
never derived directly from user ids except as sanitized hints to `quote:sym`.

### 2.2 No artifact compatibility shim

The LuaJIT backend does not expose `jit()`, `getpointer()`, `getbytes()`, object
writing, disassembly, or Rust artifact compatibility. Tests that require native
pointers are tests for the Rust/native backend and must be rewritten or split.

Reason: a LuaJIT C callback pointer is not equivalent to Cranelift machine code.
It has different lifetime, performance, reentrancy, and callback limitations.
Providing such a shim would hide backend differences and preserve the old test
shape rather than testing the new compiler honestly.

### 2.3 Semantic compatibility target

The backend must implement the current Rust/Cranelift semantic command surface:

- signatures and declarations;
- data declarations and initialization;
- function declarations, locals, exports, externs;
- block creation, block params, entry params, sealing;
- stack slots;
- aliases and addresses;
- scalar constants/unary/intrinsic/binary/compare/cast/select/fma;
- pointer offset;
- scalar load/store;
- memcpy/memset;
- vector splat/binary/compare/select/mask/load/store/insert/extract;
- direct, extern, and indirect calls;
- jump, branch, switch, return, trap;
- finalization;
- target and alias facts as metadata/no-code commands.

Where Rust/Cranelift rejects a program, LuaJIT should reject it at compile time
with a clear diagnostic. Where Rust/Cranelift defines behavior, LuaJIT should
match it.

---

## 3. ASDL-first principle

The compiler consumes `MoonBack.BackProgram` directly. It does not lower through
`BackCommandTape` text and it does not mirror Rust structs as a primary IR.

The ASDL schema determines:

- command variant names;
- field names;
- scalar and shape variants;
- id types;
- memory/address facts;
- control-flow commands;
- vector command structure.

The LuaJIT compiler creates its own internal IR from the ASDL commands. This IR
is designed for source emission and LuaJIT tracing, not for Cranelift.

### 3.1 Command normalization

During collection, each ASDL command is normalized into a backend-internal
command record with resolved ids and stable enums:

```lua
NormCmd = {
  op = "iadd" | "load" | "jump" | ...,
  src = original_cmd,
  index = program_index,
  fields = ...,
}
```

Normalization resolves:

- id objects to text;
- scalar variants to scalar descriptors;
- shape variants to scalar/vector descriptors;
- call target/result variants;
- address base variants;
- operation variants;
- visibility variants.

No code is emitted during normalization.

### 3.2 Diagnostics

Every internal record keeps `src` and `index` so diagnostics can reference the
original command and position:

```text
back_luajit: function 'foo', command #37 CmdVecSelect: float vector select is not supported by current MoonBack semantics
```

Diagnostics are generated by the LuaJIT backend itself, not inherited from the
old file.

---

## 4. Compiler pipeline

The complete pipeline is:

```text
MoonBack.BackProgram
  -> collect module declarations and bodies
  -> normalize commands
  -> build per-function CFG
  -> validate backend semantic invariants
  -> infer value shapes and representation layouts
  -> analyze liveness and component live ranges
  -> allocate Lua locals/components
  -> emit one hygienic module closure with quote.lua
  -> compile generated source
  -> return LuaJITModuleArtifact
```

Each stage has a distinct input and output. No stage reaches back into a later
stage's mutable state.

---

## 5. Internal module model

The collector produces:

```lua
ModuleIR = {
  T = T,
  Back = T.MoonBack,
  Core = T.MoonCore,

  sigs = {
    [sig_text] = {
      id = sig_text,
      params = { Scalar, ... },
      results = { Scalar, ... },
      src = cmd,
      index = i,
    },
  },

  datas = {
    [data_text] = {
      id = data_text,
      size = integer,
      align = integer,
      inits = { DataInit, ... },
      src = cmd,
      index = i,
    },
  },

  externs = {
    [extern_text] = {
      id = extern_text,
      symbol = string,
      sig = sig_text,
      src = cmd,
      index = i,
    },
  },

  funcs = {
    [func_text] = FuncIR,
  },

  func_order = { func_text, ... },
  exported = { [func_text] = true },
  finalize_seen = boolean,
}
```

A function is:

```lua
FuncIR = {
  id = func_text,
  sig = sig_text,
  visibility = "export" | "local",
  params = { Scalar, ... },
  results = { Scalar, ... },

  body_cmds = { NormCmd, ... },

  blocks = {
    [block_text] = BlockIR,
  },
  block_order = { block_text, ... },
  entry_block = block_text,
  entry_params = { value_text, ... },

  values = {
    [value_text] = ValueInfo,
  },

  stack_slots = {
    [slot_text] = { id = slot_text, size = integer, align = integer },
  },

  cfg = {
    preds = { [block_text] = { pred_block_text, ... } },
    succs = { [block_text] = { succ_block_text, ... } },
  },

  analysis = {},
  emit = {},
}
```

A block is:

```lua
BlockIR = {
  id = block_text,
  label = nil, -- filled during emission with quote:sym
  params = {
    { value = value_text, shape = Shape, index = command_index },
  },
  cmds = { NormCmd, ... },
  term = NormCmd,
  sealed = boolean,
  src_create_index = i,
}
```

A value is:

```lua
ValueInfo = {
  id = value_text,
  shape = Shape,
  def = { kind = "cmd" | "entry_param" | "block_param", index = i, block = block_text },
  uses = { { index = i, block = block_text, role = string }, ... },
  repr = Repr,
  components = { ComponentInfo, ... },
}
```

---

## 6. Validation responsibilities

The LuaJIT backend is not a replacement for `back_validate.lua`, but it must
still protect itself against malformed programs and backend-specific semantic
mismatches.

It validates:

- one declaration per signature/data/function/extern id, or identical compatible
  redeclarations if MoonBack permits them;
- no nested functions;
- every function body has a matching function declaration;
- every command appears in a valid top-level/function/block context;
- block ids are unique per function;
- values are defined before use in the ASDL program model where required;
- values are not multiply defined except `CmdAlias` coalescing rules are applied
  explicitly;
- block arg count matches destination block param count;
- entry param count matches function signature param count;
- calls use the declared callee signature;
- indirect calls use an existing signature;
- return arity matches function signature;
- vector lane count is power-of-two and at least two, matching Rust semantics;
- float-vector `CmdVecSelect` is rejected, matching current Rust semantics;
- memory modes match load/store intent when required;
- stack slot alignment is positive power-of-two;
- data init writes remain inside data object bounds;
- switch cases parse according to switch scalar and are unique.

Validation errors abort compilation before source emission.

---

## 7. Representation system

LuaJIT has Lua numbers, booleans, strings, tables, functions, and FFI cdata.
MoonBack has typed machine values. The backend therefore defines an explicit
representation system. This is not optional; it is the core of correctness.

A representation describes how a MoonBack value is stored in generated Lua
locals and how operations consume/produce it.

```lua
Repr = {
  kind = "bool8" | "u8" | "i8" | "u16" | "i16" | "u32" | "i32" |
         "u64pair" | "i64pair" | "f32" | "f64" | "ptr" | "index" |
         "vec",
  scalar = Scalar?,
  vec = Vec?,
  components = { ComponentKind, ... },
}
```

All representations are exact by construction. Fast forms are selected only
when analysis proves they preserve semantics for the operation being emitted.

### 7.1 Bool

MoonBack `Bool` is represented as numeric `0` or `1`, matching the Rust backend
which lowers bool values to `i8` and uses `icmp_imm != 0` for conditions.

Rules:

- false is `0`;
- true is `1`;
- conditions emit `cond ~= 0`;
- Lua truthiness is never used for MoonBack bool;
- `CmdBoolNot` emits `dst = src == 0 and 1 or 0`;
- comparisons produce `0` or `1`.

### 7.2 8/16/32-bit integers

Integers up to 32 bits are represented as Lua numbers carrying the raw unsigned
bit pattern:

```text
I8/U8     0 .. 255
I16/U16   0 .. 65535
I32/U32   0 .. 4294967295
```

The signedness lives in the operation, not in the stored bits.

Normalization helpers:

```lua
u8(x)  = x mod 2^8
u16(x) = x mod 2^16
u32(x) = x mod 2^32
s8(x)  = x >= 2^7  and x - 2^8  or x
s16(x) = x >= 2^15 and x - 2^16 or x
s32(x) = x >= 2^31 and x - 2^32 or x
```

Rules:

- integer arithmetic wraps to the destination width;
- signed compare reinterprets through `sN`;
- unsigned compare compares raw normalized values;
- bit ops operate on raw bits and normalize;
- shifts mask/count according to backend semantics for the scalar width;
- division and remainder check divide-by-zero and match Cranelift signed vs
  unsigned behavior;
- signed division truncates toward zero, not floor toward negative infinity.

LuaJIT `bit.*` is used where it is semantically correct. Because LuaJIT bit ops
are 32-bit signed internally, every use is surrounded by representation-specific
normalization where required.

### 7.3 64-bit integers

`I64` and `U64` are represented as two 32-bit raw components:

```text
lo = low 32 bits,  0 .. 4294967295
hi = high 32 bits, 0 .. 4294967295
```

This pair representation is exact, portable across LuaJIT builds, and avoids
hot-path allocation of `int64_t` cdata values for every operation.

Runtime helpers implement 64-bit operations:

```lua
rt.u64_norm(lo, hi)
rt.i64_add(alo, ahi, blo, bhi) -> rlo, rhi
rt.i64_sub(...)
rt.i64_mul(...)
rt.u64_div(...)
rt.s64_div(...)
rt.u64_rem(...)
rt.s64_rem(...)
rt.u64_band(...)
rt.u64_bor(...)
rt.u64_bxor(...)
rt.u64_bnot(...)
rt.u64_shl(...)
rt.u64_shr(...)
rt.i64_shr(...)
rt.u64_rotl(...)
rt.u64_rotr(...)
rt.u64_popcnt(...)
rt.u64_clz(...)
rt.u64_ctz(...)
rt.u64_bswap(...)
rt.u64_cmp(...)
rt.i64_cmp(...)
rt.sext_to_64(width, value)
rt.uext_to_64(width, value)
rt.ireduce_from_64(width, lo, hi)
```

Public exported functions accepting/returning 64-bit values use LuaJIT cdata or
explicit pair policy selected by `compile_opts.abi64`:

```lua
abi64 = "cdata" -- default: int64_t/uint64_t cdata at public boundary
abi64 = "pair"  -- public boundary exposes lo,hi for tests/tools that need it
```

This is not a compatibility shim. It is the backend's documented ABI choice for
machine-width values. Internal generated functions always use pairs.

### 7.4 Index

`BackIndex` is pointer-width unsigned integer. Representation is:

- on 64-bit LuaJIT targets: same component layout as `U64`;
- on 32-bit LuaJIT targets: same as `U32`.

Pointer arithmetic uses exact helpers when an index is represented as a pair:

```lua
rt.ptr_offset(base_ptr, index_lo, index_hi, elem_size, const_offset)
```

The helper casts the pointer through `uintptr_t` and performs exact unsigned
pointer-width arithmetic using FFI cdata where needed, returning a `uint8_t*`.

Fast emitted pointer arithmetic is allowed only when analysis proves the offset
component fits exactly in a Lua number and the target pointer width permits the
operation:

```lua
cast_u8p(base) + (index * elem_size + const_offset)
```

### 7.5 Floating point

`F64` is represented as a Lua number.

`F32` is represented as a Lua number that is rounded to IEEE-754 single
precision after every F32-producing operation:

```lua
f32(x) = tonumber(ffi.cast("float", x))
```

Rules:

- F32 constants are parsed as F32 then converted to Lua number;
- F32 arithmetic emits `f32(a + b)`, `f32(a * b)`, etc.;
- F64 arithmetic emits raw Lua numeric operations;
- `floor`, `ceil`, `trunc`, `round`, `sqrt`, `abs`, `fma` use captured math/ffi
  helpers and normalize according to destination scalar;
- `Round` matches Cranelift `nearest`, not ad-hoc `floor(x + 0.5)`.

### 7.6 Pointers

`BackPtr` is represented as FFI pointer cdata. Null is a typed zero pointer:

```lua
ffi.cast("void*", 0)
```

Never use `nil` as a pointer value. `nil` has Lua table/function semantics and
cannot represent a machine null pointer reliably in generated code.

Generated code casts pointers through captured ctypes:

```lua
local u8p_t = ffi.typeof("uint8_t*")
ptr = cast(u8p_t, base) + offset
```

### 7.7 Vectors

Vectors are represented as expanded lane components, never Lua tables.

For `Vec<I32x4>`:

```text
v.0, v.1, v.2, v.3
```

For `Vec<I64x2>`:

```text
v.0.lo, v.0.hi, v.1.lo, v.1.hi
```

Rules:

- vector loads/stores are contiguous lane load/store sequences;
- vector binary ops lower lane-wise;
- vector compares produce integer mask lanes, not bool lanes;
- a true mask is all bits set for the lane width;
- vector mask ops are bitwise lane ops;
- vector select is bitwise `(mask & then) | (~mask & else)` and is rejected for
  float vectors, matching current Rust semantics;
- lane insert/extract map to component assignment/access;
- vectors are passed through internal function calls as expanded components.

---

## 8. ABI model

There are two ABIs: internal generated-function ABI and exported Lua API ABI.

### 8.1 Internal ABI

Internal calls between generated functions pass representation components
without boxing.

Examples:

```text
I32        -> one argument/result
F64        -> one argument/result
Ptr        -> one argument/result
I64        -> lo, hi
Vec<I32x4> -> lane0, lane1, lane2, lane3
Vec<I64x2> -> lane0_lo, lane0_hi, lane1_lo, lane1_hi
```

A function with signature:

```text
(I64, Vec<I32x4>) -> I64
```

emits internally as:

```lua
fn = function(a_lo, a_hi, v0, v1, v2, v3)
  ...
  return r_lo, r_hi
end
```

### 8.2 Exported Lua API ABI

Exported functions are module table entries. They convert public Lua inputs to
internal components and pack internal results back to public values.

Public scalar defaults:

| MoonBack scalar | Public Lua value |
|---|---|
| Bool | `false/true` or `0/1`, normalized to bool8 internally |
| I8/I16/I32 | Lua number |
| U8/U16/U32 | Lua number |
| I64 | `int64_t` cdata by default |
| U64/Index | `uint64_t` cdata by default on 64-bit |
| F32/F64 | Lua number |
| Ptr | FFI pointer cdata |

For vector exported params/results, the API uses explicit flat component lists
or cdata vector values according to `compile_opts.vector_abi`. The default is
flat components because it is transparent and exactly matches internal layout.

```lua
vector_abi = "flat"  -- default
vector_abi = "cdata" -- optional documented ABI using generated struct types
```

The exported ABI is part of the LuaJIT backend contract. It does not attempt to
match Cranelift native function pointers.

---

## 9. Control flow and SSA lowering

MoonBack uses block parameters. Lua uses mutable locals and `goto`. The backend
must preserve SSA edge semantics exactly.

### 9.1 Block labels

Each block receives a hygienic label:

```lua
block.emit.label = q:sym("block_" .. block.id)
```

Emission shape:

```lua
::label_entry::
  ... block commands ...
  ... terminator ...
```

All locals used across gotos are declared at function top to avoid Lua `goto`
scope restrictions.

### 9.2 Block parameters

Block parameters are represented by normal value locals. Incoming edges assign
arguments to destination parameter locals before `goto`.

A terminator edge carries:

```lua
EdgeCopy = {
  dst_values = destination block param values,
  src_values = terminator args,
}
```

### 9.3 Parallel copy

Block argument assignment is parallel, never sequential.

For an edge:

```text
B(a, b) <- jump B(b, a)
```

emission must be equivalent to:

```lua
tmp = a
a = b
b = tmp
```

The copy resolver works on components, not just values. A vector or i64 value
becomes multiple component copies. The algorithm:

1. Expand value copies to component copies.
2. Remove `dst == src` copies.
3. While an acyclic copy exists where `dst` is not used as any remaining `src`,
   emit it and remove it.
4. For each remaining cycle, pick one copy, save its source in a hygienic temp,
   break the cycle, and continue.
5. Temps are declared at function top or drawn from the allocator's scratch pool.

This resolver is shared by jumps, branches, switches if needed, and tail-call
self-loop optimization.

### 9.4 Branches

`CmdBrIf` emits:

```lua
if cond ~= 0 then
  <parallel copy to then block params>
  goto then_label
else
  <parallel copy to else block params>
  goto else_label
end
```

### 9.5 Switch

`CmdSwitchInt` uses scalar-specific case parsing. Cases are checked for
uniqueness during validation.

Emission strategy is deterministic:

- for small case counts, emit an `if/elseif/else` chain;
- for large case counts, emit a constant dispatch table captured or declared at
  module initialization;
- branch targets still go through edge copy logic if future MoonBack switch args
  are added. Current `CmdSwitchInt` has no per-case args.

Because Lua labels cannot be first-class values, dispatch tables map case values
to small numeric tags, followed by an if-chain over tags.

---

## 10. Memory model

### 10.1 Runtime allocation

Data objects and stack slots use aligned runtime allocation:

```lua
owner, ptr = rt.alloc_aligned(size, align)
```

`owner` is the raw FFI array kept alive. `ptr` is an aligned `uint8_t*`.

Implementation requirements:

- `align >= 1` and power-of-two;
- allocate `size + align - 1` bytes, with at least one byte for zero-size edge
  handling if needed;
- compute aligned address using `uintptr_t`;
- return both owner and pointer;
- never allow owner to be garbage-collected while pointer is reachable.

### 10.2 Data declarations

Module-level data objects are allocated once in the generated module closure.

Data initialization is performed before function definitions are returned.
Initialization writes exact little-endian bytes, matching the current Rust data
writer:

- `CmdDataInitZero`: fill byte range with zero;
- integer scalar: parse signed/unsigned according to scalar and write little
  endian bytes;
- float scalar: parse F32/F64 and write IEEE bits little endian;
- bool: write one byte `0` or `1`;
- null: write zero bytes for scalar size.

### 10.3 Stack slots

Stack slots are per function invocation. At function entry, generated code
allocates each slot declared in the function:

```lua
local slot_owner_1, slot_ptr_1 = alloc_aligned(size, align)
```

`CmdStackAddr` assigns the pointer to the destination value representation.

### 10.4 Addresses

MoonBack `BackAddress` is normalized to an address-producing expression.

Address bases:

| Base | Lowering |
|---|---|
| `BackAddrValue(value)` | use pointer value representation |
| `BackAddrStack(slot)` | use slot pointer |
| `BackAddrData(data)` | use data pointer |

`byte_offset` is a MoonBack value. For 32-bit offsets, direct pointer addition is
used after normalization. For 64-bit/index offsets, use `rt.ptr_add_bytes`.

### 10.5 Loads/stores

Loads and stores use captured FFI pointer ctypes, not string casts in hot code.

Module captures:

```lua
cast   = q:val(ffi.cast, "cast")
u8p_t  = q:val(ffi.typeof("uint8_t*"), "u8p_t")
i32p_t = q:val(ffi.typeof("int32_t*"), "i32p_t")
u32p_t = q:val(ffi.typeof("uint32_t*"), "u32p_t")
f32p_t = q:val(ffi.typeof("float*"), "f32p_t")
```

Scalar loads normalize to internal representation. Scalar stores convert from
internal representation to memory representation.

Vector loads/stores emit lane-wise scalar loads/stores from contiguous memory.

### 10.6 Memcpy/memset

`CmdMemcpy` emits:

```lua
ffi.copy(dst, src, len)
```

`CmdMemset` emits correct LuaJIT order:

```lua
ffi.fill(dst, len, byte)
```

The byte value is reduced to `uint8_t` before emission.

### 10.7 Memory facts

Memory info is used for validation and optimization metadata:

- alignment may select faster typed loads or assertions;
- dereference/trap information may allow omission of explicit nil/trap checks;
- motion/alias facts are not required for correctness of source emission;
- `CmdAliasFact` is recorded in metadata for future scheduling but emits no
  runtime code.

This backend does not reorder memory operations unless an explicit optimization
pass proves legality from memory facts. The base design preserves command order.

---

## 11. Calls and symbols

### 11.1 Direct calls

All generated functions are forward-declared in one module closure:

```lua
local fn_a, fn_b, fn_c
fn_a = function(...) ... fn_b(...) ... end
fn_b = function(...) ... fn_a(...) ... end
```

This supports forward calls and mutual recursion.

Direct calls pass internal ABI components and receive internal ABI components.

### 11.2 Tail self-calls

A direct self-call in tail position may be lowered to a loop:

```lua
<parallel copy args to entry params>
goto entry_label
```

This is not a trampoline and does not allocate a stack table. It is simply CFG
rewriting at emission time. Non-tail recursion uses normal Lua calls.

### 11.3 Extern calls

Extern declarations record symbol and signature. Generated code resolves extern
functions at module initialization:

```lua
local ext = ffi.C[symbol]
```

The backend requires the appropriate `ffi.cdef` declarations to already exist.
This mirrors normal LuaJIT FFI usage and keeps C declaration ownership outside
MoonBack codegen.

Arguments/results are converted between internal representation and extern ABI:

- 32-bit integers are converted to Lua numbers/cdata as needed;
- 64-bit integers are packed to `int64_t`/`uint64_t` cdata;
- pointers remain pointer cdata;
- vectors passed to externs use the documented vector ABI. If the platform C ABI
  cannot represent a vector form chosen by `vector_abi`, compilation fails with
  a clear diagnostic.

### 11.4 Function addresses

Because the backend has no native machine-code function pointer, function
addresses are represented internally as function tokens unless they cross an
extern boundary.

Internal representation:

```lua
FuncToken = integer
func_token_table[token] = generated_internal_function
func_sig_table[token] = sig_id
```

`CmdFuncAddr(dst, func)` assigns a token value with pointer-like representation
inside MoonBack. `CmdCallIndirect` recognizes token callees and dispatches
through `func_token_table` after signature validation.

If a function address is stored to memory, returned, or passed to an extern,
compilation fails unless `compile_opts.allow_lua_callbacks == true`. This is not
a compatibility shim; it is an explicit semantic mode because exporting Lua
closures as C callbacks has real runtime constraints.

When callback mode is enabled, the compiler creates FFI callbacks for function
addresses that escape to C and keeps them alive in module metadata. The default
is to reject escaping internal function addresses rather than silently changing
semantics.

### 11.5 Extern addresses

`CmdExternAddr(dst, extern)` produces an FFI C function pointer using the
signature-derived function pointer ctype:

```lua
cast(sig_funcptr_t, ffi.C[symbol])
```

Indirect calls through extern addresses use FFI function-pointer calls.

### 11.6 Indirect calls

`CmdCallIndirect` handles two callee classes:

1. internal function token: dispatch to generated function table;
2. FFI C function pointer: cast to signature ctype and call.

Result normalization follows the call result scalar.

---

## 12. Operation lowering

### 12.1 Constants

- `BackLitInt`: parse according to destination scalar. Reject int literal for
  float/bool as Rust does.
- `BackLitFloat`: parse only for F32/F64. F32 is rounded.
- `BackLitBool`: produce bool8 `0/1`.
- `BackLitNull`: produce typed null pointer or zero bits for scalar contexts
  where null is accepted.

### 12.2 Unary

- `Ineg`: two's-complement negation at scalar width.
- `Fneg`: numeric negation with F32/F64 normalization.
- `Bnot`: bitwise not at scalar width.
- `BoolNot`: `src == 0 and 1 or 0`.

### 12.3 Intrinsics

Implemented for scalar shapes only, matching current Rust tape conversion:

- `Popcount`
- `Clz`
- `Ctz`
- `Bswap`
- `Sqrt`
- `Abs`
- `Floor`
- `Ceil`
- `TruncFloat`
- `Round`

Integer intrinsics dispatch by width. Float intrinsics dispatch by F32/F64.
Unsupported vector intrinsic shapes are rejected.

### 12.4 Integer binary

- `BackIntAdd`: wrap addition.
- `BackIntSub`: wrap subtraction.
- `BackIntMul`: wrap multiplication.
- `BackIntSDiv`: signed division, trap/error on zero and overflow case where
  Cranelift would trap.
- `BackIntUDiv`: unsigned division, trap/error on zero.
- `BackIntSRem`: signed remainder.
- `BackIntURem`: unsigned remainder.

`BackIntSemantics` flags are recorded and may enable optimization, but the base
lowering preserves wrapping/exact machine semantics.

### 12.5 Bit binary, shifts, rotates

- bit ops are raw-bit operations at scalar width;
- shift right signed vs unsigned is explicit;
- rotate count is reduced modulo width;
- 64-bit shifts/rotates use pair helpers.

### 12.6 Float binary and FMA

- F32 operations round to F32;
- F64 operations use Lua number;
- strict vs fast-math is recorded. The base emitter preserves source order and
  does not reassociate unless fast-math explicitly permits and an optimization
  pass applies it.

### 12.7 Compare

Integer compare produces bool8 `0/1`:

- equality compares raw normalized values;
- signed compare uses signed interpretation;
- unsigned compare uses raw interpretation.

Float compare produces bool8 `0/1` and follows Lua/IEEE comparison behavior for
NaN where it matches Cranelift condition codes. Any discovered NaN condition-code
mismatch must be handled in runtime helpers, not ignored.

### 12.8 Casts

- `Bitcast`: reinterpret bits. For scalar classes where Lua representation is not
  bit-identical, use memory/cdata helper.
- `Ireduce`: truncate to destination width.
- `Sextend`: sign extend from source known width to destination width.
- `Uextend`: zero extend.
- `Fpromote`: F32 to F64.
- `Fdemote`: F64 to F32.
- `SToF`: signed integer to float.
- `UToF`: unsigned integer to float.
- `FToS`: float to signed integer, matching Cranelift conversion behavior.
- `FToU`: float to unsigned integer.

Source width for extend/reduce is recovered from value type analysis.

### 12.9 Select

Scalar select emits explicit conditional assignment and never uses Lua's
`cond and a or b` idiom:

```lua
if cond ~= 0 then
  dst = then_value
else
  dst = else_value
end
```

For multi-component values, every component is assigned in both arms.

---

## 13. Vector lowering

The vector subsystem is a first-class part of the compiler, not an add-on.

### 13.1 Vector type descriptor

```lua
Vec = {
  elem = Scalar,
  lanes = integer,
  elem_width = bits,
  lane_repr = Repr,
  components_per_lane = integer,
  total_components = lanes * components_per_lane,
}
```

### 13.2 Lane component naming

The allocator maps each vector component to a physical Lua local. Component
identity is structural:

```lua
{ value = "v", lane = 3, part = "lo" }
```

### 13.3 Vector compare masks

True mask values:

| Elem width | True mask |
|---|---|
| 8 | `0xff` |
| 16 | `0xffff` |
| 32 | `0xffffffff` |
| 64 | `lo=0xffffffff, hi=0xffffffff` |

False mask is zero bits.

### 13.4 Vector command coverage

| Command | Lowering |
|---|---|
| `CmdVecSplat` | copy scalar components into every lane |
| `CmdVecBinary` | lane-wise integer/bit operation |
| `CmdVecCompare` | lane-wise compare to mask lane |
| `CmdVecSelect` | bitwise select, reject float element vectors |
| `CmdVecMask` | lane-wise not/and/or |
| `CmdVecInsertLane` | copy source vector then replace selected lane |
| `CmdVecExtractLane` | copy selected lane components to scalar value |
| vector `CmdLoadInfo` | lane-wise contiguous scalar loads |
| vector `CmdStoreInfo` | lane-wise contiguous scalar stores |

---

## 14. Local allocation and liveness

Generated Lua must avoid excessive locals and long live ranges. LuaJIT has trace
and local-slot limits; a backend that declares every value in a large function as
one permanent local is not acceptable.

### 14.1 Component graph

Every value expands to components. Liveness is computed on components, not just
values. Examples:

```text
I32        -> one component
I64        -> lo, hi
Vec<I32x4> -> lane0, lane1, lane2, lane3
```

### 14.2 Liveness analysis

For each function:

1. Compute per-block `use` and `def` component sets.
2. Include terminator edge uses from jump/branch args.
3. Iterate CFG to fixed point:

```text
live_out[B] = union live_in[S] over successors S, adjusted for edge args
live_in[B]  = use[B] union (live_out[B] - def[B])
```

Block params are defined at block entry. Edge arguments are uses in the
predecessor terminator.

### 14.3 Allocation

Use a linear-scan allocator over component live intervals in command order with
CFG-aware block boundary liveness.

Allocation classes:

- numeric raw bits (`num`);
- float (`float`);
- pointer cdata (`ptr`);
- function token (`token`);
- scratch temps for parallel copy.

Lua itself does not require type-specific locals, but classes help debugging,
coalescing, and future optimization.

### 14.4 Coalescing

The allocator coalesces:

- `CmdAlias` values;
- block params with incoming args when a single predecessor permits it;
- move-only scalar temps;
- vector lane copies where safe.

Coalescing is an optimization. Correctness never depends on it.

### 14.5 Function top declarations

All physical locals are declared at function top:

```lua
local r1, r2, r3, r4, ...
```

This is required because Lua `goto` cannot jump into the scope of a local
declared after the label. Component names are hygienic `quote:sym` names.

---

## 15. Emission architecture

### 15.1 Quote usage

`quote.lua` is mandatory for generated source hygiene.

Use:

- `q:sym` for all generated identifiers and labels;
- `q:val` for runtime helpers, FFI functions, ctypes, constant tables, and
  extern function references;
- `q:compile` for source compilation.

Never concatenate arbitrary id text as a Lua identifier.

### 15.2 Module emission skeleton

```lua
local q = quote()
local rt = q:val(runtime, "rt")
local ffi = q:val(require("ffi"), "ffi")
local cast = q:val(ffi.cast, "cast")

-- captured ctypes and helpers

-- data objects

-- forward declarations
q("local %s", table.concat(fn_symbols, ", "))

-- function definitions
for _, func in ipairs(module.func_order) do
  emit_function(q, module, func)
end

-- export table
q("local module = {}")
for _, fid in ipairs(module.func_order) do
  if module.exported[fid] then
    q("module[%q] = %s", fid, export_wrapper_symbol[fid])
  end
end
q("return { module = module, functions = %s, meta = %s }", functions_table, meta_table)
```

The actual returned artifact table is assembled around the compiled closure so
that `source` is retained outside the generated source.

### 15.3 Function emission skeleton

```lua
fn_sym = function(<internal params>)
  local <physical locals>
  local <stack owners and ptrs>

  -- bind incoming params to allocated value components if needed

  ::entry_label::
    ...

  ::other_label::
    ...
end
```

### 15.4 Runtime captures

At module emit time capture:

- `ffi.cast`, `ffi.copy`, `ffi.fill`, `ffi.typeof`, `ffi.new` if used directly;
- `bit.band`, `bit.bor`, `bit.bxor`, `bit.bnot`, `bit.lshift`, `bit.rshift`,
  `bit.arshift`, `bit.rol`, `bit.ror` where available;
- math functions;
- runtime helper table;
- ctype objects;
- data init byte strings/tables;
- extern function objects.

Generated functions should not call `require`.

---

## 16. Runtime helper module

Create `lua/moonlift/back_luajit_runtime.lua`.

Required helper groups:

### 16.1 Numeric normalization

```lua
rt.u8, rt.u16, rt.u32
rt.s8, rt.s16, rt.s32
rt.trunc_toward_zero
rt.f32
rt.round_nearest_even_or_cranelift_equivalent
```

### 16.2 64-bit pairs

All helpers listed in section 7.3, plus packing/unpacking:

```lua
rt.unpack_i64_cdata(x) -> lo, hi
rt.unpack_u64_cdata(x) -> lo, hi
rt.pack_i64_cdata(lo, hi) -> int64_t cdata
rt.pack_u64_cdata(lo, hi) -> uint64_t cdata
```

### 16.3 Pointer helpers

```lua
rt.null_ptr()
rt.alloc_aligned(size, align) -> owner, ptr
rt.ptr_add_bytes(ptr, off_repr)
rt.ptr_offset(ptr, index_repr, elem_size, const_offset)
rt.ptr_to_uint(ptr) -> index repr
```

### 16.4 Memory helpers

```lua
rt.load_scalar(ptr, scalar_descriptor)
rt.store_scalar(ptr, scalar_descriptor, components...)
rt.load_u64(ptr) -> lo, hi
rt.store_u64(ptr, lo, hi)
rt.write_data_init(ptr, offset, scalar, literal_kind, literal_value)
```

Hot common scalar loads/stores may be emitted inline. Helpers remain the
canonical correctness implementation.

### 16.5 Call helpers

```lua
rt.make_extern(symbol, sig_descriptor)
rt.call_indirect_c(sig_descriptor, callee, components...)
rt.prepare_extern_args(sig_descriptor, components...)
rt.normalize_extern_result(sig_descriptor, result)
```

The emitter may inline simple call conversions.

---

## 17. Data structures for source emission

During emission, attach an `EmitInfo` to module/function/value records:

```lua
ModuleEmit = {
  q = quote,
  runtime_sym = string,
  helper_syms = { ... },
  ctype_syms = { ... },
  data_syms = { [data_id] = { owner = sym, ptr = sym } },
  fn_syms = { [func_id] = sym },
  export_syms = { [func_id] = sym },
}
```

```lua
FuncEmit = {
  label = { [block_id] = sym },
  local_for_component = { [component_id] = sym },
  scratch = { sym, ... },
  stack = { [slot_id] = { owner = sym, ptr = sym } },
  param_components = { ... },
  return_components = { ... },
}
```

---

## 18. Command coverage matrix

| ASDL command | Required backend action |
|---|---|
| `CmdTargetModel` | record metadata; optionally validate host pointer bits/features |
| `CmdCreateSig` | collect signature descriptor |
| `CmdDeclareData` | collect data object; allocate in module closure |
| `CmdDataInitZero` | append zero init; execute during module init |
| `CmdDataInit` | append typed init; execute during module init |
| `CmdDataAddr` | assign data pointer value |
| `CmdFuncAddr` | assign function token or callback pointer in explicit callback mode |
| `CmdExternAddr` | assign FFI extern function pointer |
| `CmdDeclareFunc` | collect function declaration and visibility |
| `CmdDeclareExtern` | collect extern symbol and signature |
| `CmdBeginFunc` | begin function body collection |
| `CmdCreateBlock` | create block in current function |
| `CmdSwitchToBlock` | set current block during CFG construction; emit label later |
| `CmdSealBlock` | mark block sealed/validate |
| `CmdBindEntryParams` | bind function params to entry block params |
| `CmdAppendBlockParam` | add scalar/vector block param value |
| `CmdCreateStackSlot` | declare per-call stack slot |
| `CmdAlias` | coalesce or copy value components |
| `CmdStackAddr` | assign stack slot pointer |
| `CmdConst` | emit scalar constant normalization |
| `CmdUnary` | emit scalar unary op |
| `CmdIntrinsic` | emit scalar intrinsic op; reject vector intrinsic shape |
| `CmdCompare` | emit bool8 compare |
| `CmdCast` | emit representation-aware cast |
| `CmdPtrOffset` | emit pointer offset helper or inline pointer arithmetic |
| `CmdLoadInfo` scalar | emit scalar load |
| `CmdLoadInfo` vector | emit lane-wise vector load |
| `CmdStoreInfo` scalar | emit scalar store |
| `CmdStoreInfo` vector | emit lane-wise vector store |
| `CmdIntBinary` | emit integer op |
| `CmdBitBinary` | emit bit op |
| `CmdBitNot` | emit bit not |
| `CmdShift` | emit shift |
| `CmdRotate` | emit rotate |
| `CmdFloatBinary` | emit float op |
| `CmdAliasFact` | record metadata; no code |
| `CmdMemcpy` | emit `ffi.copy` |
| `CmdMemset` | emit `ffi.fill(dst,len,byte)` |
| `CmdSelect` | emit explicit conditional component assignments |
| `CmdFma` | emit FMA helper/op |
| `CmdVecSplat` | emit lane expansion |
| `CmdVecBinary` | emit lane-wise vector op |
| `CmdVecCompare` | emit lane-wise mask compare |
| `CmdVecSelect` | emit integer bitwise select; reject float vec select |
| `CmdVecMask` | emit lane-wise mask op |
| `CmdVecInsertLane` | emit vector copy plus lane replacement |
| `CmdVecExtractLane` | emit selected lane copy |
| `CmdCall` direct | emit internal direct call |
| `CmdCall` extern | emit extern call conversion |
| `CmdCall` indirect | emit token or FFI function pointer indirect call |
| `CmdJump` | emit edge parallel copy and goto |
| `CmdBrIf` | emit conditional branches with edge copies |
| `CmdSwitchInt` | emit switch dispatch |
| `CmdReturnVoid` | emit return |
| `CmdReturnValue` | emit return components |
| `CmdTrap` | emit `error("trap")` or runtime trap helper |
| `CmdFinishFunc` | end function collection/validate |
| `CmdFinalizeModule` | finish module emission |

---

## 19. Performance rules

The backend is designed for LuaJIT tracing. Required rules:

1. No command dispatch in generated hot code.
2. No table allocation in generated hot loops.
3. No `require` inside generated functions.
4. No string `ffi.cast` inside hot code; use captured ctypes.
5. No Lua truthiness for MoonBack bools.
6. No sequential block-param copies.
7. No global lookups for bit/math/ffi helpers in hot code.
8. No storing vectors as tables.
9. No storing i64 values as heap objects in internal code.
10. No source identifiers derived unsafely from MoonBack ids.

Optimization passes are allowed only after the exact lowering path is defined.
The optimizer must preserve representation invariants.

---

## 20. Source layout after refactor

Replace the current rough file with a small orchestrator and focused modules:

```text
lua/moonlift/back_luajit.lua
lua/moonlift/back_luajit_collect.lua
lua/moonlift/back_luajit_normalize.lua
lua/moonlift/back_luajit_validate.lua
lua/moonlift/back_luajit_cfg.lua
lua/moonlift/back_luajit_repr.lua
lua/moonlift/back_luajit_liveness.lua
lua/moonlift/back_luajit_alloc.lua
lua/moonlift/back_luajit_emit.lua
lua/moonlift/back_luajit_runtime.lua
```

The orchestrator:

```lua
function M.Define(T, opts)
  return {
    compile = function(program, compile_opts)
      local mod = collect(T, program)
      normalize(T, mod)
      build_cfg(T, mod)
      validate(T, mod)
      assign_repr(T, mod)
      analyze_liveness(T, mod)
      allocate_locals(T, mod)
      local fn, src, meta = emit(T, mod, opts, compile_opts)
      local artifact_payload = fn()
      return {
        module = artifact_payload.module,
        functions = artifact_payload.functions,
        meta = meta,
        source = src,
      }
    end,
  }
end
```

No old helper functions or partial trampoline code are retained.

---

# Implementation plan and checklist

This plan describes the complete implementation. Work may be committed in
steps, but the backend is not considered complete until every checklist item is
satisfied.

## A. Remove old backend shape

- [ ] Delete the existing monolithic emitter implementation in
      `lua/moonlift/back_luajit.lua`.
- [ ] Replace it with the orchestrator described in section 20.
- [ ] Ensure no self-call trampoline code remains.
- [ ] Ensure no per-function independent `quote:compile` remains.
- [ ] Ensure no global `vals`, `slots`, or `blocks` maps remain.
- [ ] Ensure no generated function calls `require` at runtime.

## B. ASDL normalization

- [ ] Implement scalar descriptor creation from `BackScalar` variants.
- [ ] Implement shape descriptor creation for scalar/vector shapes.
- [ ] Implement id text extraction with diagnostics for malformed ids.
- [ ] Normalize all top-level commands.
- [ ] Normalize all function-body commands.
- [ ] Normalize all address base variants.
- [ ] Normalize all literal variants.
- [ ] Normalize all operation enum variants.
- [ ] Normalize call result and call target variants.
- [ ] Attach original command and program index to every normalized command.

## C. Module collection

- [ ] Collect signatures.
- [ ] Collect data declarations and init commands.
- [ ] Collect extern declarations.
- [ ] Collect function declarations and visibility.
- [ ] Collect function bodies between `CmdBeginFunc` and `CmdFinishFunc`.
- [ ] Preserve function order from the ASDL program.
- [ ] Record `CmdFinalizeModule` and reject commands after finalization if the
      schema/backend policy requires it.
- [ ] Reject nested functions.
- [ ] Reject body commands outside functions.
- [ ] Reject invalid top-level commands.

## D. CFG construction

- [ ] Build per-function block table.
- [ ] Preserve block order.
- [ ] Assign commands to blocks based on `CmdSwitchToBlock`.
- [ ] Identify terminators.
- [ ] Reject blocks with no terminator.
- [ ] Reject commands after terminator before next block switch.
- [ ] Record block params.
- [ ] Record entry block and entry params.
- [ ] Build predecessor/successor sets for jumps, branches, and switches.
- [ ] Record sealed blocks.

## E. Backend validation

- [ ] Validate duplicate signature/data/func/extern rules.
- [ ] Validate function body has declaration.
- [ ] Validate call signatures.
- [ ] Validate indirect call signatures exist.
- [ ] Validate extern symbols and signatures.
- [ ] Validate block references.
- [ ] Validate block arg counts.
- [ ] Validate entry param counts against function signature.
- [ ] Validate return arity and type.
- [ ] Validate stack slot alignments.
- [ ] Validate data init bounds and literal scalar compatibility.
- [ ] Validate vector lane counts.
- [ ] Validate vector operation element compatibility.
- [ ] Reject float vector select.
- [ ] Validate switch scalar and case parsing.
- [ ] Validate no unknown value uses remain after value inference.

## F. Value shape inference

- [ ] Assign shapes to entry params from function signature.
- [ ] Assign shapes to block params from `CmdAppendBlockParam`.
- [ ] Assign shapes to constants from command scalar.
- [ ] Assign shapes to unary/intrinsic/compare/cast/binary/select/fma results.
- [ ] Assign pointer shape to `CmdDataAddr`, `CmdFuncAddr`, `CmdExternAddr`,
      `CmdStackAddr`, `CmdPtrOffset`.
- [ ] Assign scalar/vector shape to loads.
- [ ] Assign call result shape from `BackCallValue`.
- [ ] Assign vector result shapes to all vector commands.
- [ ] Record every value use with command index, block, and role.

## G. Representation assignment

- [ ] Implement scalar representation table.
- [ ] Implement vector representation expansion.
- [ ] Assign representation to every value.
- [ ] Expand every value to components.
- [ ] Implement public ABI descriptors for exported params/results.
- [ ] Implement internal ABI descriptors for generated functions.
- [ ] Implement extern ABI descriptors.
- [ ] Implement function-token representation for internal function addresses.

## H. Runtime helpers

- [ ] Create `back_luajit_runtime.lua`.
- [ ] Implement 8/16/32-bit normalization and signed reinterpret helpers.
- [ ] Implement F32 rounding helper.
- [ ] Implement Cranelift-equivalent float rounding helper.
- [ ] Implement 64-bit pair packing/unpacking.
- [ ] Implement all 64-bit arithmetic, bit, shift, rotate, compare helpers.
- [ ] Implement aligned allocation.
- [ ] Implement pointer arithmetic helpers.
- [ ] Implement scalar memory load/store helpers.
- [ ] Implement data init writer helpers.
- [ ] Implement extern conversion helpers.
- [ ] Add runtime self-tests for helper semantics.

## I. Liveness and allocation

- [ ] Build component ids for all value components.
- [ ] Compute per-block component use/def.
- [ ] Include terminator edge args as uses.
- [ ] Compute live-in/live-out fixed point.
- [ ] Build live intervals.
- [ ] Implement linear-scan allocator.
- [ ] Implement scratch temp pool.
- [ ] Implement coalescing for aliases.
- [ ] Implement coalescing for safe block param edges.
- [ ] Declare all physical locals at function top.
- [ ] Add debug metadata mapping values/components to locals.

## J. Parallel copy resolver

- [ ] Implement component-copy expansion.
- [ ] Implement no-op removal.
- [ ] Implement acyclic copy emission.
- [ ] Implement cycle breaking with scratch temps.
- [ ] Support multi-component values.
- [ ] Use resolver for `CmdJump`.
- [ ] Use resolver for both arms of `CmdBrIf`.
- [ ] Use resolver for tail self-call lowering.
- [ ] Add tests for swaps, cycles, vectors, and i64 copies.

## K. Hygienic emitter

- [ ] Create module-level `quote()`.
- [ ] Capture runtime helper table.
- [ ] Capture FFI functions and ctypes.
- [ ] Capture bit and math functions.
- [ ] Generate data object declarations.
- [ ] Generate function forward declarations.
- [ ] Generate internal function definitions.
- [ ] Generate exported wrappers.
- [ ] Generate final artifact payload table.
- [ ] Return compiled closure and source.
- [ ] Ensure generated source compiles with no globals except intentional Lua
      builtins already captured or lexical.

## L. Scalar command emitters

- [ ] Emit constants.
- [ ] Emit unary ops.
- [ ] Emit intrinsics.
- [ ] Emit compares.
- [ ] Emit casts.
- [ ] Emit integer binary ops.
- [ ] Emit bit binary ops.
- [ ] Emit bit not.
- [ ] Emit shifts.
- [ ] Emit rotates.
- [ ] Emit float binary ops.
- [ ] Emit scalar select with explicit conditional assignment.
- [ ] Emit FMA.
- [ ] Verify bool is always `0/1`.
- [ ] Verify F32 normalization after every F32-producing op.
- [ ] Verify signed division truncates toward zero.

## M. Memory/data emitters

- [ ] Emit module data allocation.
- [ ] Emit module data initialization.
- [ ] Emit stack slot allocation at function entry.
- [ ] Emit stack addresses.
- [ ] Emit data addresses.
- [ ] Emit address formation for all base variants.
- [ ] Emit pointer offset.
- [ ] Emit scalar loads/stores.
- [ ] Emit vector loads/stores.
- [ ] Emit memcpy.
- [ ] Emit memset with correct argument order.

## N. Vector emitters

- [ ] Emit vector splat.
- [ ] Emit vector integer binary ops.
- [ ] Emit vector bit binary ops.
- [ ] Emit vector compares to mask lanes.
- [ ] Emit vector mask not/and/or.
- [ ] Emit vector integer select.
- [ ] Reject vector float select.
- [ ] Emit insert lane.
- [ ] Emit extract lane.
- [ ] Verify lane-wise memory layout.

## O. Call emitters

- [ ] Emit direct calls using internal ABI.
- [ ] Emit direct statement calls.
- [ ] Emit extern calls with ABI conversion.
- [ ] Emit extern statement calls.
- [ ] Emit function address tokens.
- [ ] Emit extern address function pointers.
- [ ] Emit indirect calls through internal tokens.
- [ ] Emit indirect calls through FFI function pointers.
- [ ] Implement explicit callback mode for escaping internal function addresses,
      disabled by default.
- [ ] Validate result normalization for every call result scalar.

## P. Control emitters

- [ ] Emit block labels.
- [ ] Emit jumps.
- [ ] Emit branches.
- [ ] Emit switches.
- [ ] Emit returns.
- [ ] Emit traps.
- [ ] Emit tail self-call loop lowering when tail position is proven.
- [ ] Ensure no command falls through accidentally after terminators.

## Q. Export wrappers

- [ ] Generate wrapper for every exported function.
- [ ] Convert public scalar args to internal components.
- [ ] Convert public vector args according to `vector_abi`.
- [ ] Pack internal scalar results to public values.
- [ ] Pack internal vector results according to `vector_abi`.
- [ ] Store all generated internal functions in artifact `functions` table by
      original id text.
- [ ] Store exported wrappers in artifact `module` table by original id text.

## R. Debugging and diagnostics

- [ ] Include full generated source in artifact.
- [ ] On `loadstring` error, include generated source with line numbers.
- [ ] Add compile option to dump source.
- [ ] Add compile option to dump ModuleIR.
- [ ] Add compile option to dump liveness/allocation.
- [ ] Ensure diagnostics include function id, block id where relevant, command
      index, and command kind.

## S. Test refactor checklist

Tests are refactored after backend implementation because there is no backward
compatibility requirement.

- [ ] Add LuaJIT backend tests for scalar add/sub/mul/div/rem.
- [ ] Add bool condition/select tests with false then-values.
- [ ] Add signed/unsigned compare tests across boundary values.
- [ ] Add I8/I16/I32 wrap tests.
- [ ] Add I64/U64 arithmetic tests.
- [ ] Add F32 rounding tests.
- [ ] Add F64 math tests.
- [ ] Add branch/block-param swap tests.
- [ ] Add loop with block params tests.
- [ ] Add switch tests.
- [ ] Add data init/load tests.
- [ ] Add stack slot roundtrip tests.
- [ ] Add scalar load/store tests for every scalar.
- [ ] Add memcpy/memset tests.
- [ ] Add direct call tests including forward and mutual recursion.
- [ ] Add extern call tests.
- [ ] Add indirect internal token call tests.
- [ ] Add extern address indirect call tests.
- [ ] Add vector splat/binary/compare/mask/select tests.
- [ ] Add vector load/store tests.
- [ ] Add vector insert/extract tests.
- [ ] Add trap tests.
- [ ] Add generated-source smoke tests under LuaJIT.

## T. Acceptance criteria

The refactor is complete only when:

- [ ] The old `back_luajit.lua` architecture is gone.
- [ ] The backend compiles one hygienic module closure per BackProgram.
- [ ] Every current Rust/Cranelift-supported MoonBack command has an explicit
      LuaJIT lowering or matching compile-time rejection.
- [ ] Bool, integer, float, pointer, index, and vector representations are exact
      according to this document.
- [ ] Block params use parallel copy on every edge.
- [ ] I64/U64 are exact internally.
- [ ] Vector values are lane-expanded, not table boxed.
- [ ] Function/data/extern addresses are handled according to the documented
      token/FFI model.
- [ ] Generated hot code contains no command dispatch loop.
- [ ] Generated hot code contains no avoidable table allocation.
- [ ] All tests refactored for the new LuaJIT backend API pass.

---

## 21. Rationale summary

The previous rough backend was structured as a string-emitting command walk with
global value maps and an incorrect recursion trampoline. That shape cannot grow
into a Cranelift substitute because correctness requires whole-module knowledge,
CFG construction, representation decisions, liveness, and hygienic source
emission.

The new backend treats LuaJIT as a machine-code target reached through generated
Lua source. That requires making machine values explicit: bools are `0/1`, small
integers are normalized raw bits, 64-bit integers are exact pairs, pointers are
FFI cdata, and vectors are lane-expanded components. Once representations are
explicit, every MoonBack command can lower deterministically to source that
LuaJIT can trace.

This is a hard refactor. The source of truth is the ASDL program and the target
semantics, not old tests, old API shape, or the current draft implementation.
