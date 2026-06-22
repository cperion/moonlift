# LLPVM Programmer Guide

LLPVM is Moonlift's low-level PVM API surface: a Lua-authored, bytecode-fed VM
substrate for typed operation languages, worlds, streams, phases, native
execution, and small C/FFI/embedded boundaries.

The public authoring rule is:

```text
Types are Lua tables.
Constructors are named fields on those type tables.
Worlds project those types into callable recording constructors.
Bytecode refs are internal encoder facts, not public API.
```

```lua
local moon = require "moonlift"
local ll = require "llpvm"
```

## Public Module

```lua
ll.vm(config)          -- create an authoring VM
ll.bytecode(program)   -- encode a Program proxy or ASDL Program
ll.bytebuffer(bytes)   -- copy a Lua string into uint8_t[] for FFI

ll.symbol(value)
ll.cache(mode)

ll.asdl, ll.T, ll.B    -- ASDL context/builders for tools and tests
```

Removed by design:

```text
ll.node
ll.ref_payload
ll.ref_arg
vm.abi
vm.world
vm.seq
ABI-level op constructors
```

Those names exposed the bytecode assembly model too early. The public API now
uses typed Lua values and world-owned constructors.

## Quick Start

```lua
local ll = require "llpvm"

local vm = ll.vm { cache_bytes = 64 * 1024 }

local Expr = vm.language "Expr"
local ExprNode = Expr "Node"

ExprNode.Int = {
    value = moon.i64,
}

ExprNode.Add = {
    left = ExprNode,
    right = ExprNode,
}

local Back = vm.language "Back"
local BackValue = Back "Value"

BackValue.ConstI64 = {
    value = moon.i64,
}

BackValue.AddI64 = {}

local expr = Expr:world()
local back = Back:world()

local one = expr.Node.Int { value = 1 }
local two = expr.Node.Int { value = 2 }
local sum = expr.Node.Add { left = one, right = two }

local input = expr:seq { one, two, sum }

local lower_machine = vm.machine "lower_expr" {
    from = expr,
    to = back,
    entry = "ll_lower_expr",
}

local lower = vm.phase "lower_expr" {
    from = expr,
    to = back,
    machine = lower_machine,
    cache = "full",
}

local lowered = lower { target = "native", opt = 3 } (input)
local program = vm.program { input, lowered }

local bytes = program:bytecode()
assert(bytes:sub(1, 4) == "LLPV")
```

## Mental Model

LLPVM has four layers:

```text
Lua authoring API
    Builds typed operation languages and bytecode images.

LLPV bytecode image
    Immutable, portable, caller-owned bytes.

Native VM runtime
    Imports/borrows the image and creates opaque handles.

C/FFI boundary
    Status-returning open/load/apply/drain/report functions.
```

The important ownership split:

```text
Authored Lua proxy != native handle
bytecode load       = handle creation boundary
```

Pass authored streams to `program:bytecode()`. Pass native stream handles to the
runtime FFI/C API. Do not mix them.

## Authoring VM

```lua
local vm = ll.vm {
    cache_bytes = 4096,
}
```

The Lua authoring VM stores:

```text
builder       direct LLPV bytecode builder
types         lowered type cache
abis          declared operation languages
worlds        declared worlds
machines      declared machines
phases        declared phases
retained      retained authoring values
generation    rebuild generation counter
```

The VM methods are:

```lua
vm.language "Name"
vm.concat { stream_a, stream_b }
vm.machine "name" { from = in_world, to = out_world, entry = "symbol" }
vm.phase "name" { from = in_world, to = out_world, machine = machine, cache = "full" }
vm.program { root_stream, other_root }
vm.retain(value)
vm.rebuild(function(vm) ... end)
```

## Languages

A language is an operation vocabulary. It corresponds to one encoded ABI, but
the public API calls it a language because programmers author types and
constructors, not ABI records.

```lua
local Expr = vm.language "Expr"
local Node = Expr "Node"

Node.Int = { value = moon.i64 }
Node.Add = { left = Node, right = Node }
```

`vm.language "Expr"` returns the live language table. `Expr "Node"` creates and
installs a named type table on that language. Constructor schemas are assigned
as fields on the type table. This is ordinary Lua: locals, captured values,
loops, conditionals, imported schema data, and generated constructor families
all work directly.

`Node` is a real Lua table with identity. Field schemas may reference it
directly. No global erased node type exists.

## Type API

LLPVM does not define a parallel type language. Constructor schemas accept
Moonlift type values. In `.mlua`, write real Moonlift declarations:

```moonlift
local Vec2 = struct Vec2
    x: f32,
    y: f32
end

Node.Move = {
    id = moon.u64,
    pos = Vec2,
    bytes = moon.view(moon.u8),
}
```

LLPVM lowers those values into compact schema ids for bytecode validation and
runtime dispatch.

Language-local types are declared by calling the language table:

```lua
local Node = Expr "Node"
```

They lower to handle types named by their full language path, such as
`Expr.Node`.

## Worlds

A world is a semantic layer using one language.

```lua
local raw = Expr:world()
local checked = Expr:world "checked"
```

`Language:world()` defaults the world name to the language name. Repeated calls
with the same name return the same world proxy.

Worlds project type tables into constructor namespaces:

```lua
local n = raw.Node.Int { value = 1 }
```

The constructor path includes the world and the type:

```text
raw.Node.Int
^   ^    ^
|   |    constructor
|   type
world
```

That visibility is intentional. It prevents hidden world defaults and erased
node handles.

## Constructors And Values

`world.Type.Op` is a cached callable constructor table:

```text
constructor.world
constructor.type
constructor.op
constructor.name
constructor.qualified_name
```

Constructors accept named payload tables only:

```lua
local a = raw.Node.Int { value = 1 }
local b = raw.Node.Int { value = 2 }
local c = raw.Node.Add { left = a, right = b }
```

They reject:

```text
missing payload fields
unknown payload fields
positional payload arrays
wrong scalar types
values from another declared type
values from another world
```

A produced value is an authoring proxy:

```text
value.vm
value.id              bytecode-local op id
value.world
value.type            declared type table
value.type_name
value.kind            constructor name, e.g. "Add"
value.qualified_kind  bytecode kind, e.g. "Node.Add"
value.payload         payload values in schema order
```

When a typed payload receives another produced value, the encoder emits an
internal payload reference to that produced value's op id. The user does not
spell that reference.

## Streams

Streams are pullable operation sequences. In the Lua authoring API they also
keep a debug list of locally authored values.

```lua
local empty = raw:empty()
local once = raw:once(a)
local seq = raw:seq { a, b, c }
local both = vm.concat { seq, raw:seq { raw.Node.Int { value = 3 } } }
```

World stream methods validate that values belong to the world.

Inspection helpers:

```lua
local ops = seq:drain()
local one = once:one()

seq:each(function(value, i)
    print(i, value.qualified_kind)
end)
```

These helpers inspect authored proxies. They do not call the native runtime.

## Machines

A machine transforms streams from one world to another.

```lua
local machine = vm.machine "lower_expr" {
    from = raw,
    to = back,
    entry = "ll_lower_expr",
}
```

Accepted aliases:

```text
from   or input
to     or output
entry  or entry_symbol
```

Machine proxies have:

```text
machine.vm
machine.id
machine.name
machine.input
machine.output
```

`entry` is the native/Moonlift symbol implementing the machine.

## Phases

A phase is a named memoization boundary over a machine.

```lua
local lower = vm.phase "lower_expr" {
    from = raw,
    to = back,
    machine = machine,
    cache = "full",
}
```

Cache policy:

```lua
cache = nil       -- no cache
cache = "full"    -- full cache
cache = "record"  -- record only
```

Phase values are callable:

```lua
local output = lower(input)
local output_with_args = lower { target = "native", opt = 3 } (input)
```

Arguments may be named or positional. If an argument is a produced LLPVM value,
the encoder emits an internal argument reference.

## Programs

```lua
local program = vm.program { input, lowered }
local bytes = program:bytecode()
local path, n = program:write("program.llpv")
```

Program proxies have:

```text
program.vm
program.root_ids
program.root_ops
```

The first root stream's values are also recorded as a root op table for hot
native drain/import paths.

## Retain And Rebuild

Retained values support incremental frontends without pretending native handles
survive authoring rebuilds.

```lua
local retained = vm:retain(input)

local rebuilt = vm:rebuild(function()
    local old_first = retained:get():drain()[1]
    local fresh = raw.Node.Int { value = 4 }
    return raw:seq { old_first, fresh }
end)
```

Semantics:

```text
vm:retain(value)       stores an authoring value and generation
retained:get()         returns the retained value
vm:rebuild(fn)         increments vm.generation and calls fn(vm)
```

Retained values are authoring-layer facts. They are not native ownership and do
not keep runtime handles alive.

## Runtime FFI

The Lua runtime wrapper is:

```lua
local Runtime = require "llpvm.runtime_ffi"
```

Build and open a native runtime:

```lua
local rt = Runtime.build {
    cleanup = true,
}

local native = rt:open {
    cache_bytes = 4096,
}
```

Load a bytecode image:

```lua
local bytes = program:bytecode()
local buf, len = ll.bytebuffer(bytes)

local status, root = native:load_program_buffer(buf, len)
assert(status.code == 0)
```

Drain a native stream:

```lua
local st, buffer = native:drain(root)
assert(st.code == 0)
```

Apply a native phase:

```lua
local st, out_stream = native:apply_phase(phase_ref, input_stream_ref, args_ref)
```

Report runtime counters:

```lua
local report = native:report()
print(report.abis, report.worlds, report.streams)
```

Close:

```lua
native:close()
rt:close()
```

Runtime calls expect native integer handles. Passing authored Lua proxies is an
error by design:

```lua
native:drain(input) -- error: authored Lua proxy is not a native stream ref
```

## C API

Generate the C blob and header:

```lua
local build = require "llpvm.native.build_c"
build.write_artifact("llpvm_amalgam.c", {
    h_path = "llpvm_amalgam.h",
})
```

Applications normally call:

```c
llpvm_status llpvm_open(const llpvm_config *config, llpvm_vm_ref *out);
llpvm_status llpvm_close(llpvm_vm_ref vm);
llpvm_status llpvm_load_program(llpvm_vm_ref vm,
                                const void *bytes,
                                size_t len,
                                llpvm_stream_ref *out_root);
llpvm_status llpvm_apply_phase(llpvm_vm_ref vm,
                               llpvm_phase_ref phase,
                               llpvm_stream_ref input,
                               llpvm_args_ref args,
                               llpvm_stream_ref *out);
llpvm_status llpvm_drain(llpvm_vm_ref vm,
                         llpvm_stream_ref stream,
                         llpvm_buffer_ref *out);
llpvm_status llpvm_report(llpvm_vm_ref vm, llpvm_vm_report *out);
```

Handles are opaque integer references. Pointers returned through reports or
buffers are runtime-owned unless an API explicitly says otherwise.

## Ownership Rules

```text
Authoring VM          Lua-owned proxy builder.
Program byte string   Lua/host-owned immutable bytes.
Native load_program   borrows bytes, does not copy by default.
Native VM handle      caller owns until llpvm_close.
Stream/buffer refs    VM-owned opaque handles.
Authored proxies      never accepted as native refs.
Reports              copied product or VM-owned borrowed facts depending API.
```

Image lifetime rule:

```text
Keep bytecode bytes alive while native streams derived from them are live.
```

If a host wants copied ownership, it should copy bytes before calling
`load_program`. LLPVM keeps the runtime API borrow-only so ownership stays
visible.

## Bytecode Image

Current image header:

```text
u8[4]   magic = "LLPV"
u32     version = 2
u32     root_stream_id
u32     root_op_count
u32     root_op_table_offset
u32[]   root_op_ids
record* tagged little-endian records
```

Record shape:

```text
u8      tag
u32     payload_bytes
u8[]    payload
```

Important record tags include:

```text
symbol
type_scalar / type_handle / type_pointer / type_view / type_struct
field
op_kind
abi
world
payload_nil / payload_bool / payload_int / payload_float / payload_string / payload_ref
arg_nil / arg_bool / arg_int / arg_float / arg_string / arg_ref
args
stream_empty / stream_once / stream_seq / stream_concat / stream_phase_map
machine_region
cache_none / cache_full / cache_record
phase
root
```

The image is not a C struct dump. It is a portable little-endian bytecode
contract.

## ASDL And Builders

LLPVM exposes its ASDL context for tools:

```lua
local sym = ll.B.LlPvm.Symbol { value = "Expr" }
```

Use ASDL literals when a tool needs structural products directly. Use the
facade when authoring bytecode images. The facade itself is intentionally
PVM-shaped: type tables and constructor calls create the bytecode IR.

## VM Stack Design Discipline

Design an LLPVM stack by writing two shapes side by side:

```text
TYPE FOREST
    Language.Type.Constructor(payload...)

CONTROL GRAPH
    World -> Machine -> World -> Phase -> Stream
```

Every layer should answer:

```text
What typed values does this world contain?
What constructors create those values?
What streams are legal in this world?
What machine consumes this world?
What world does it produce?
What cache boundary makes sense?
What bytecode image must the native VM borrow?
```

The useful sentence is:

```text
All programs are VM stacks.
Each VM consumes bytecode IR and produces bytecode IR or native handles.
```

LLPVM is the standard Moonlift substrate for authoring those stacks when a full
free-form parser is unnecessary or too slow. A Lua DSL can build typed
constructors directly, feed an LLPV image to a native blob, and keep language
specific niceties as thin layers over the same bytecode contract.
