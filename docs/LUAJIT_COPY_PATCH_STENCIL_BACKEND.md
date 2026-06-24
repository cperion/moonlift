# LuaJIT Copy-and-Patch Stencil Backend Specification

This document specifies the Moonlift LuaJIT copy-and-patch backend as it exists architecturally: semantic stencil selection happens before this backend, and this backend realizes already-selected stencil artifacts into executable LuaJIT-callable native code.

The backend is not a second lowering path and not a second selector.

```text
Moonlift DSL / Lua metaprogramming
  -> MoonSyntax / MoonTree
  -> typecheck / ownership / region checks
  -> MoonCode
  -> flow / value / memory / effect facts
  -> MoonKernel semantic bodies
  -> MoonStencil schedules and artifacts
  -> BinaryStencilBank extraction
  -> embedded LuaJIT source artifact
  -> copy + patch + executable FFI pointers
```

The design rule is strict:

```text
MoonStencil decides what code shape is needed.
LuaJIT copy-and-patch decides how that selected shape becomes executable.
```

No LuaJIT copy-and-patch component may reinterpret MoonCode loops, rediscover vector reductions, duplicate Llisle rules, or silently fall back to another execution model.

## Public API

The public user-facing artifact API is:

```lua
local moon = require("moonlift")
moon.use { scope = "env" }

local decl = fn. sum_i32 { xs [ptr [i32]], n [i32] } [i32] {
  requires { bounds(xs, n), readonly(xs) },

  entry. start {} { jump. loop { i = 0, acc = 0 }, },

  block. loop { i [i32], acc [i32] } {
    when (i :lt (n)) {
      jump. body { i = i, acc = acc },
    },

    jump. done { acc = acc },
  },

  block. body { i [i32], acc [i32] } {
    jump. loop { i = i + 1, acc = acc + xs[i] },
  },

  block. done { acc [i32] } {
    ret(acc),
  },
}

local artifact = moon.emit_luajit_artifact(decl, {
  path = "target/artifacts/sum_i32.lua",
  name = "CopyPatchDemo",
  stem = "sum_i32",
})
```

`moon.emit_luajit_artifact` performs the full source artifact build:

```text
DSL value
  -> module ASDL
  -> typecheck
  -> MoonCode
  -> LuaJIT backend lowering
  -> selected MoonStencil artifacts
  -> binary bank extraction
  -> embedded Lua artifact source
```

The returned value is a `LuaJITSourceArtifact` table:

```lua
{
  kind = "LuaJITSourceArtifact",
  source = lua_source_text,
  path = optional_written_path,
  unit = module_ast,
  checked = checked_frontend_result,
  code_result = codegen_result,
  lj_module = luajit_module_asdl,
  facts = lowering_facts,
  stencil_plan = MoonStencil.StencilModulePlan,
  luajit_stencil_machines = MoonLuaJIT.LJStencilMachineModulePlan,
  exec_plan = MoonExec.ExecModulePlan,
  artifacts = selected_stencil_artifacts,
  rejects = stencil_rejects,
  bank = binary_stencil_bank,
}
```

The artifact also has:

```lua
artifact:write(path)
```

The lower-level backend API remains available to compiler code:

```lua
local Backend = require("moonlift.luajit_backend")(T)

local lj_module, facts, artifacts, rejects = Backend.lower_module(code_module, opts)
local stencil_plan = facts.stencil_plan
local luajit_stencil_machines = facts.luajit_stencil_machines
local exec_plan = facts.exec_plan
local bank = Backend.build_binary_bank(artifacts, opts)
local source = Backend.emit_lua_artifact(lj_module, artifacts, { bank = bank })
local compiled = Backend.compile_lj_module(lj_module, artifacts, { bank = bank })
```

The copy-patch provider deliberately requires an explicit `BinaryStencilBank`
for realization. This keeps the internal seam honest: selected C artifacts are
not executable until a target-specific bank has been built or supplied.

The same LuaJIT module path can also realize selected stencil artifacts through
the descriptor-level LuaTrace provider:

```lua
local compiled = Backend.compile_module(code_module, {
  stencil_provider = "lua_trace",
})
```

That path installs Lua functions in the same
`__moonlift_luajit_stencil_symbols` table used by copy-patch FFI functions.
The wrapper ASDL does not change; only the stencil provider changes.

LuaTrace is also a standalone source artifact provider:

```lua
local artifact = Backend.emit_module_artifact(code_module, {
  stencil_provider = "lua_trace",
})
```

The emitted artifact contains named LuaJIT stencil loops, not native binary
stencil bytes. LuaTrace has its own provider-local trace plan. It consumes
`StencilScheduleAutoVector`, `StencilScheduleUnrolled`, and
`StencilScheduleVector` as LuaJIT trace shaping: facts, `factor`, `lanes`,
`unroll`, and `interleave` change grouping and branch shape in the emitted Lua
loop, but this is not SIMD. Real SIMD vector semantics belong to the C/copy-patch
provider, where the selected stencil is compiled by the host C compiler and
installed as executable code.

```lua
local function ml_stencil_reduce_array_i32_add_to_i32_s1(xs, start, stop, init)
  local acc = init
  for i = start, stop - 1, 1 do
    acc = __ml_tobit(((acc) + (xs[i])))
  end
  return acc
end

__moonlift_luajit_stencil_symbols["ml_stencil_reduce_array_i32_add_to_i32_s1"] =
  ml_stencil_reduce_array_i32_add_to_i32_s1
```

## Executable plan seam

The backend publishes inspectable plans before artifact realization:

```text
MoonStencil.StencilModulePlan:
  module
  kernel
  selections = StencilPlanEntry[]

MoonStencil.StencilPlanEntry:
  kernel: KernelId
  selection: StencilSelection

MoonExec.ExecModulePlan:
  module
  stencil
  entries = ExecPlanEntry[]
  funcs = ExecFuncPlan[]

MoonExec.ExecPlanEntry:
  kernel: KernelId
  decision: ExecMaterializeStencil | ExecSkipStencil

MoonLuaJIT.LJStencilMachineModulePlan:
  module
  stencil
  machines = LJStencilMachinePlan[]

MoonLuaJIT.LJStencilMachinePlan:
  func
  kernel
  machine
  artifact
```

`StencilPlanEntry` is keyed by `KernelId`; selection order is not semantic. This is required because rejected kernels, function-level kernels, and loop kernels do not form a stable positional table.

`MoonExec` is the target-neutral executable-fragment view. It records an
inspectable per-kernel exec decision for each stencil selection, then groups
materialized stencil artifacts and scalar Code block fragments per function
before any C, LuaJIT, Cranelift, or object-code projection. Skipped stencil
entries stay visible as `ExecSkipStencil` decisions instead of disappearing
into Lua control flow.

`LJStencilMachineModulePlan` is the LuaJIT-specific projection plan. It is built
after semantic stencil selection and scheduling, before LuaJIT wrapper lowering.
LuaJIT function lowering consumes those planned machines; it does not call
artifact providers while walking Code blocks.

```text
MoonCode
  -> facts
  -> MoonKernel
  -> MoonStencil.StencilModulePlan
  -> MoonExec.ExecModulePlan
  -> MoonLuaJIT.LJStencilMachineModulePlan
  -> target projection
```

The LuaJIT backend still emits `MoonLuaJIT` wrapper ASDL, but selected stencil,
scheduled artifact, and planned machine facts are no longer hidden as callback
side effects.

## MoonStencil contract

`MoonStencil` is the semantic stencil layer. It owns:

```text
compiler policy
optimization level
machine target
vectorization facts
scalar schedules
auto-vector schedules
unrolled schedules
stencil descriptors
stencil instances
stencil artifacts
```

The important split is:

```text
StencilDescriptor:
  semantic operation identity
  vocabulary
  domain
  accesses
  operator / reducer
  memory behavior

StencilInstance:
  descriptor
  concrete schedule
  selected policy and target facts

StencilArtifact:
  instance
  symbol
  C signature
  emitted source shape
```

The schedule belongs to the instance because scheduling is a concrete selected machine-facing choice. The descriptor stays semantic so equivalent operations can be reasoned about before a concrete schedule is chosen.

Reduction is not a special LuaJIT machine anymore. Reductions are ordinary scheduled stencil artifacts. Vector reduction, scalar reduction, unrolled reduction, and mapped reduction all pass through the same `MoonStencil` artifact path.

Retired concepts:

```text
LJMachineVectorReduceArray
vector_reduce direct LuaJIT lowering
vreduce emitter support
LuaJIT-side vector reduction selection
```

Those names must not appear in the active compiler path.

## BinaryStencilBank

A `BinaryStencilBank` is the target-specific realization of selected stencil artifacts.

```lua
MoonLuaJIT.LJBinaryStencilBank {
  id = LJBinaryBankId("ljbank:sum_i32"),
  target = LJBinaryTarget("x64", "Linux", "c", 64, "little"),
  entries = LJBinaryStencilEntry[],
  preamble = ffi_cdef_text,
}
```

A bank is not portable source. It contains native code bytes and must only be loaded on a matching target.

The generated Lua artifact embeds a target guard before installing any machine code:

```text
ffi.os
ffi.arch
pointer width
endianness
```

If the runtime target does not match the bank target, the artifact fails before copying or executing native bytes.

## Binary stencil entry

A binary stencil entry is the executable unit copied into runtime memory.

```lua
MoonLuaJIT.LJBinaryStencilEntry {
  symbol = "ml_stencil_reduce_array_i32_add_s1",
  section = ".text.ml_stencil_reduce_array_i32_add_s1",
  binary = native_code_bytes,
  c_signature = "int32_t (*)(const int32_t *, int32_t, int32_t)",
  patches = LJBinaryPatchRecord[],
  artifact = StencilArtifact,
}
```

The entry key is the artifact symbol. The semantic identity is still carried through `artifact`; the executable lookup is by stable symbol because the selected artifact already embodies descriptor, schedule, target, and policy decisions.

The bank carries an installation policy:

```lua
MoonLuaJIT.LJBinaryInstallPolicy {
  address = LJInstallAnyAddress | LJInstallLow32Address,
  protection = LJInstallWriteThenExec | LJInstallReadWriteExec,
}
```

`LJInstallAnyAddress` is the normal W^X path. `LJInstallLow32Address` is selected only when the object contains local absolute 32-bit relocations, such as GCC switch/jump-table references emitted as `R_X86_64_32S`. On Linux/x64 the installer uses `MAP_32BIT` and then verifies the installed blob fits the signed 32-bit address range. Other targets reject this policy loudly.

## Patch records

Patch records describe holes in copied machine code.

```lua
MoonLuaJIT.LJBinaryPatchRecord {
  offset = byte_offset,
  kind = LJPatchAbs32 | LJPatchAbs64 | LJPatchSymbol32
       | LJPatchSymbol64 | LJPatchPc32 | LJPatchRel32
       | LJPatchLocalAbs32 | LJPatchLocalAbs64,
  ordinal = optional_patch_ordinal,
  symbol = optional_symbol_name,
  addend = optional_addend,
  reloc_type = optional_native_relocation_name,
}
```

Patch semantics:

```text
abs32 / symbol32:
  add a 32-bit patch value into a 32-bit slot

abs64 / symbol64:
  write a 64-bit patch value plus addend into a 64-bit slot

pc32:
  adjust an existing PC-relative value by subtracting the installed base

rel32:
  write a direct 32-bit relative branch/call displacement

local_abs32:
  write installed_base + blob_local_addend into a 32-bit slot;
  R_X86_64_32S additionally requires the target to fit signed 32-bit

local_abs64:
  write installed_base + blob_local_addend into a 64-bit slot
```

Patch values may be supplied by ordinal, by symbol name, or by built-in runtime symbol resolution for known C runtime calls such as `memmove`, `memcpy`, and `memset`.

## Automatic extraction

The bank builder extracts binary stencils from generated C stencil artifacts.

```text
selected StencilArtifact[]
  -> StencilC.source(artifacts)
  -> C compiler relocatable object with -ffunction-sections
  -> readelf relocation scan
  -> objcopy section extraction for .text.<symbol>
  -> LJBinaryStencilEntry[]
  -> LJBinaryStencilBank
```

`StencilC` is source generation infrastructure. It is not a runtime execution backend for LuaJIT. The LuaJIT backend consumes binary banks.

Current ELF x86-64 relocation mapping:

```text
R_X86_64_64:
  symbol64
  local_abs64 when the target is a materialized local section or local text symbol

R_X86_64_32 / R_X86_64_32S:
  symbol32
  local_abs32 when the target is a materialized local section or local text symbol;
  local_abs32 promotes the bank address policy to LJInstallLow32Address

R_X86_64_PC32 / R_X86_64_PLT32:
  rel32 when the relocation targets a symbol
  pc32 when the relocation only needs installed-base adjustment
```

Local `rel32` relocations are resolved while building the blob because they are independent of the eventual `mmap` base. Local absolute relocations are left as runtime patches because they need the installed base address. This lets GCC-generated constant pools and switch/jump tables use the same copy-patch artifact model.

The extraction contract is intentionally narrow: compiler-generated stencil C is the input, not arbitrary C object files.

## Generated artifact shape

A generated artifact is a self-contained Lua source file.

```text
-- Generated Moonlift LuaJIT copy-and-patch artifact.
-- Native stencil bytes are embedded below as data and installed before the runtime module loads.

local ffi = require("ffi")
local bit = require("bit")

ffi.cdef(...)
check_target_guard()
install_embedded_binary_stencils()

local function sum_i32(...)
  return __moonlift_luajit_stencil_symbols.ml_stencil_reduce_array_i32_add_s1(...)
end

return {
  sum_i32 = sum_i32,
}
```

The artifact is source-first by design. It can be inspected, versioned, loaded with ordinary Lua mechanisms, and shipped as a single `.lua` file containing both LuaJIT runtime code and native machine-code byte strings.

The artifact does not reference the build-time bank by path. It copies bytes from embedded strings and installs them into executable memory at load time.

## Runtime installation

Runtime installation is semantics-blind:

```text
for each entry:
  mmap writable memory according to the bank install policy
  ffi.copy entry.binary
  apply scalar patches
  mprotect read+execute
  ffi.cast c_signature to function pointer
  store in __moonlift_luajit_stencil_symbols[symbol]
```

The runtime does not select stencils, lower loops, inspect MoonCode, or run fallback code. All semantic decisions have already been made by Moonlift and MoonStencil.

The installed pointer table is the only native-code dependency of the LuaJIT runtime module:

```lua
__moonlift_luajit_stencil_symbols[artifact.symbol.text]
```

This keeps the generated Lua wrapper traceable: hot Lua code performs stable table/local accesses and calls fixed FFI function pointers.

## Validation surfaces

The canonical real-DSL artifact generator is:

```sh
luajit experiments/generate_luajit_artifact_from_moonlift.lua \
  target/artifacts/sum_i32_from_moonlift.source.lua \
  target/artifacts/sum_i32_from_moonlift.lua
```

The regression test for the public facade is:

```sh
luajit tests/code_ir/test_luajit_artifact_from_dsl.lua
```

The broader suite validates the compiler and schema boundaries:

```sh
luajit tests/run.lua code_ir
luajit tests/run.lua schema
luajit tests/run.lua
cargo check -q
```

## Architectural invariants

The backend is complete only when these invariants hold:

```text
No direct vector/reduce LuaJIT machine remains.
No runtime C compiler path is used by LuaJIT realization.
No copy-and-patch component duplicates stencil selection.
Every executable stencil comes from a selected StencilArtifact.
Every StencilInstance owns its schedule.
Every LuaJIT stencil machine comes from LJStencilMachineModulePlan.
Every embedded bank has a target guard.
Every generated artifact is self-contained Lua source.
Every native pointer visible to luajit_emit comes from BinaryStencilBank realization.
Missing stencil entries are hard errors.
Missing patch values are hard errors.
Target mismatch is a hard error.
```

The final shape is:

```text
Moonlift semantics
  -> MoonStencil schedule/artifact
  -> BinaryStencilBank
  -> embedded LuaJIT source artifact
  -> copy-and-patch executable pointers
```
