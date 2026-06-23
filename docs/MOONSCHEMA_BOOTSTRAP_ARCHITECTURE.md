# MoonSchema Bootstrap Architecture

MoonSchema is the schema and compiler-package architecture for Moonlift
bootstrap.

It replaces text `.asdl` as the source of truth. It is not an adapter over the
old schema text grammar. It is an LLB-authored, Moonlift-typed schema language whose
values project to runtime classes, LLPVM packages, Moonlift data declarations,
C ABI surfaces, documentation, diagnostics, and tooling.

The design goal is direct:

```text
Moonlift schema and compiler phases are authored as structured Lua/Moonlift
values, packaged as LLPVM executable phase machines, and projected to native/C
runtime boundaries without a separate textual schema language.
```

## Doctrine

```text
Schema is authored as values.
Fields use Moonlift types.
LLB owns authoring.
MoonSchema owns structure, identity, diagnostics, and projection.
LLPVM owns executable compiler-phase packaging.
Moonlift implements phase machines.
C consumes sealed ABI projections.
Cranelift consumes final backend programs.
```

No `.asdl` text is part of the architecture. The active schema directory contains Lua/MoonSchema modules only.

No duplicate schema type system exists.

No phase wrapper layer is the design.

## Layer map

```text
LLB
  Parserless language-construction substrate.

Moonlift types
  Field type language used by schemas.

MoonSchema
  Product/sum/identity/diagnostic/projection language.

Runtime projection
  Generated MoonAsdl-backed classes, builders, interning, and structural update.

LLPVM projection
  Executable worlds, streams, phases, bytecode images, and process events.

Moonlift projection
  Native data declarations and phase-machine implementations.

C projection
  Stable sealed ABI for embedding, tools, diagnostics, and phase execution.

Cranelift backend
  Final native code generator for MoonBack programs.
```

## Compiler ABI boundary

The hosted compiler has one explicit shared code boundary:

```text
MoonTree.Module
  -> MoonTree.TypeModuleResult
  -> MoonCompiler.CodeResult
  -> MoonBack.Program
  -> MoonCompiler.FlatlineImage
  -> MoonCompiler.NativeArtifact

MoonTree.Module
  -> MoonTree.TypeModuleResult
  -> MoonCompiler.CodeResult
  -> MoonC.CBackendUnit
  -> C artifact
```

`MoonCompiler.CodeResult` is not a helper tuple. It is the persisted compiler
ABI between semantic MoonTree and backend projections. It contains:

```text
module      : MoonCode.CodeModule
contracts   : MoonCode.CodeFuncContractFact[]
layout_env  : MoonSem.LayoutEnv
```

Back and C projection machines validate this value before consuming it. That
means a future bootstrap runner can materialize, cache, inspect, serialize, or
replay `CodeResult` without re-entering the source DSL or the typechecker.

The native execution boundary is also explicit:

```text
MoonCompiler.FlatlineImage
  -> MoonCompiler.NativeArtifact
```

`FlatlineImage` is deterministic and cacheable. `NativeArtifact` is a typed
descriptor for a host-runtime resource. The actual Cranelift artifact pointer is
not serialized into ASDL; it lives in the native runtime registry.

The public roots are therefore:

```text
compile:
  MoonTree.Module -> MoonCompiler.FlatlineImage

jit:
  MoonTree.Module -> MoonCompiler.NativeArtifact

emit_object:
  MoonTree.Module -> MoonCompiler.ObjectArtifact

emit_c:
  MoonTree.Module -> MoonC.CBackendUnit
```

## Back wire format as LLPVM ABI

The current Cranelift back wire format is already an LLPVM-shaped ABI in
practice:

```text
MoonBack.Program
  -> MoonCompiler.FlatlineImage
  -> native consumer
  -> executable machine code
```

It is a borrowed, sectioned, flat command stream with explicit tags and scalar
slots. That is the same architectural pattern as LLPVM bytecode images: a
typed record language projected into a compact ABI consumed by a native engine.

The bootstrap direction is therefore not to invent a separate Cranelift bridge.
The correct split is:

```text
MoonCompiler.CodeResult
  -> MoonBack.Program
  -> MoonCompiler.FlatlineImage
  -> MoonCompiler.NativeArtifact
```

Flatline is the concrete native ABI for backend records. LLPVM is the general
machine substrate pattern for images, validation, inspection, and execution.

## Canonical schema source

Schema files are Lua modules, not text grammar files.

```text
lua/moonlift/schema/core.lua
lua/moonlift/schema/type.lua
lua/moonlift/schema/tree.lua
lua/moonlift/schema/code.lua
lua/moonlift/schema/back.lua
lua/moonlift/schema/phase.lua
```

Each module returns a MoonSchema value.

```lua
local moon = require("moonlift")
local S = require("moonlift.schema.dsl")

moon.use()
S.use()

return schema. MoonTree {
  use. MoonCore,
  use. MoonType,
  use. MoonSource,

  product. Module {
    interned,
    identity. ModuleId,

    header [ModuleHeader],
    items [many [Item]],
  },

  sum. Item {
    Func   { func [Func] },
    Extern { func [ExternFunc] },
    Type   { decl [TypeDecl] },
  },
}
```

This is the schema source of truth.

## Field type model

MoonSchema does not define its own scalar/type language.

Fields use real Moonlift type values and schema type references.

```lua
name [str]
count [i64]
ok [bool]
index [index]
bytes [view [u8]]
ty [ty. MoonType.Type]
expr [ty. MoonTree.Expr]
origin [optional [ty. MoonSource.Range]]
items [many [ty. Item]]
owner [ref [ty. Module]]
binding_id [id [ty. MoonBind.Binding]]
by_name [map [str] [ty. Binding]]
```

Schema-specific type wrappers are minimal and semantic:

```lua
many [T]
optional [T]
ref [T]
id [T]
map [K] [V]
```

Everything inside a wrapper is still a Moonlift/schema type value.

Meaning:

```text
T
  Embedded value.

many[T]
  Ordered sequence of values.

optional[T]
  Optional value.

ref[T]
  Reference to an existing schema value.

id[T]
  Durable typed identity for T.

map[K][V]
  Associative projection keyed by K.
```

## Schema heads

Canonical top-level heads:

```lua
schema. Name { ... }
product. Name { ... }
sum. Name { ... }
alias. Name [T]
diagnostics { ... }
world. name [T]
phase. name { ... }
project. target { ... }
```

Canonical diagnostic heads:

```lua
error. Code { ... }
warning. Code { ... }
info. Code { ... }
```

Canonical phase heads:

```lua
from. world
to. world
diagnostics. world
cache. policy
machine. implementation
deterministic true
```

## Products

A product is a named record value.

```lua
product. Param {
  interned,
  name [str],
  ty [MoonType.Type],
}
```

A product body contains attributes and fields.

Field syntax is always:

```lua
field_name [Type]
```

Field-local attributes are allowed but not required:

```lua
origin [optional [MoonSource.Range]] { transient }
```

## Sums

A sum is a named set of variants.

```lua
sum. Expr {
  interned,
  identity. ExprId,

  Lit {
    ty [MoonType.Type],
    value [MoonCore.Literal],
  },

  Binary {
    ty [MoonType.Type],
    op [MoonCore.BinaryOp],
    lhs [ref [Expr]],
    rhs [ref [Expr]],
  },

  Block {
    stmts [many [Stmt]],
    result [optional [Expr]],
  },
}
```

Empty variants are bare names.

```lua
sum. Scalar {
  Void,
  Bool,
  I32,
  I64,
}
```

Variant payloads are product-shaped.

## Aliases

Aliases name semantic type expressions.

```lua
alias. ParamList [many [Param]]
alias. MaybeExpr [optional [Expr]]
alias. BindingMap [map [str] [Binding]]
```

Aliases are not textual macros. They are schema declarations and can project
differently per backend.

## Imports

Imports are explicit.

```lua
schema. MoonTree {
  use. MoonCore,
  use. MoonType,
  use. MoonBind,
}
```

Name resolution order:

```text
local declarations
explicit imports
Moonlift builtins
```

Qualified names are always valid:

```lua
ty [MoonType.Type]
path [MoonCore.Path]
```

Implicit cross-module guessing is not part of the design.

## Attributes

Attributes are schema values.

Canonical declaration attributes:

```text
interned
identity. NameId
doc "..."
transient
derived
indexed
opaque
packed
stable
external
```

Meaning:

```text
interned
  Structural canonicalization and sharing.

identity. NameId
  Stable typed identity/id value generated for this declaration.

doc
  Documentation projection text.

transient
  Excluded from identity/serialization by default.

derived
  Computed field, not authored storage.

indexed
  Generate index support for lookup/projection.

opaque
  Backend-owned value with sealed projection.

packed
  C/native projection layout hint.

stable
  ABI/serialization stability contract.

external
  Declared elsewhere, referenced here.
```

## Identity and interning

Identity and interning are separate.

```lua
product. Binding {
  interned,
  identity. BindingId,

  name [str],
  ty [MoonType.Type],
}
```

`interned` controls structural sharing.

`identity. BindingId` creates durable typed identity usable by LLPVM, C, binary
encoders, caches, references, arenas, and debug tooling.

This replaces any design where structural uniqueness is overloaded as semantic
identity.

## Diagnostics

Diagnostics are schema-defined.

```lua
diagnostics {
  error. DuplicateDecl {
    name [str],
    first [MoonSource.Range],
    second [MoonSource.Range],
  },

  error. TypeMismatch {
    expected [MoonType.Type],
    actual [MoonType.Type],
    site [str],
  },
}
```

Diagnostic schemas project to:

```text
LLB diagnostics
LLPVM diagnostic worlds
LSP diagnostics
terminal reports
C ABI diagnostic records
documentation
```

Ad-hoc diagnostic classes scattered through subsystems are not the final model.

## Projection blocks

Projection policy is explicit and separate from semantic fields.

```lua
product. Module {
  identity. ModuleId,
  header [ModuleHeader],
  items [many [Item]],

  project. c {
    layout. opaque,
  },

  project. llpvm {
    representation. arena_ref,
  },
}
```

Canonical projection namespaces:

```text
runtime
llpvm
moonlift
c
binary
docs
lsp
```

Projection blocks do not change the semantic declaration. They control how the
same declaration is represented at a boundary.

## Runtime projection

Runtime projection generates ASDL-style Lua classes from MoonSchema values.

```text
MoonSchema package
  -> runtime projection
  -> T.MoonTree.Module / T.MoonTree.Item / T.MoonCode.CodeModule / ...
```

Runtime projection owns:

```text
constructors
class objects
sum membership
field metadata
structural update
interning
fast builders
raw getters
identity/id support
```

The runtime projection replaces text-ASDL parsing. The runtime may keep the same
kind of class objects and constructor behavior, but it is generated from
MoonSchema values.

## Current ASDL runtime plug point

The current ASDL runtime shape remains useful as a generated runtime projection.
It is not a source language.

The architectural plug point is:

```text
MoonSchema package
  -> runtime projection
  -> current ASDL context/class generation machinery
  -> compiler modules receive T.MoonTree, T.MoonCode, T.MoonBack, ...
```

The current ASDL lexer/parser/text loader is not part of the final design.

The runtime class generator can be refactored to consume MoonSchema directly:

```text
MoonSchema.Module/Product/Sum/Field
  -> class plans
  -> constructors/builders/interner
```

Current compiler code still wants `T.Moon*` classes. The runtime projection
provides those classes from MoonSchema.

## LLPVM projection

Every schema package can project to LLPVM language objects.

```text
MoonSchema module
  -> LLPVM language
  -> worlds for values/arenas/diagnostics
  -> op heads for products and variants
  -> bytecode image schema
```

Projection rules:

```text
product
  LLPVM op constructor with product payload.

sum variant
  LLPVM op constructor/tagged alternative.

many[T]
  Stream/range/list representation.

optional[T]
  Option sum representation.

ref[T]
  Typed value reference.

id[T]
  Durable typed id.

map[K][V]
  Associative projection.

diagnostics
  Diagnostic world and diagnostic op vocabulary.
```

Example generated usage:

```lua
local MoonTreePvm = Schema.project.llpvm(pkg, {
  module = "MoonTree",
})

MoonTreePvm.use()

return MoonTreePvm {
  values. tree {
    Module. root {
      header = ModuleSurface,
      items = items,
    },
  },

  root { root },
}
```

## Compiler package schema

Compiler phases are data.

```lua
package "moonlift.compiler" {
  world. tree [MoonTree.Module]
  world. checked [MoonTree.TypeModuleResult]
  world. back_code [MoonCompiler.CodeResult]
  world. back [MoonBack.Program]
  world. flatline [MoonCompiler.FlatlineImage]
  world. native [MoonCompiler.NativeArtifact]
  world. object [MoonCompiler.ObjectArtifact]
  world. diag [MoonDiag.Report]

  phase. typecheck {
    from. tree,
    to. checked,
    diagnostics. diag,
    cache. identity,
    deterministic true,
    machine. moon_typecheck,
  },

  phase. checked_to_back_code {
    from. checked,
    to. back_code,
    diagnostics. diag,
    cache. identity,
    deterministic true,
    machine. hosted_checked_to_back_code,
  },

  phase. back_code_to_back {
    from. back_code,
    to. back,
    diagnostics. diag,
    cache. identity,
    deterministic true,
    machine. hosted_back_code_to_back,
  },

  phase. back_to_flatline {
    from. back,
    to. flatline,
    diagnostics. diag,
    cache. identity,
    deterministic true,
    machine. hosted_back_to_flatline,
  },

  phase. flatline_to_native {
    from. flatline,
    to. native,
    diagnostics. diag,
    cache. none,
    deterministic false,
    machine. hosted_flatline_to_native,
  },

  phase. flatline_to_object {
    from. flatline,
    to. object,
    diagnostics. diag,
    cache. none,
    deterministic false,
    machine. hosted_flatline_to_object,
  },

  root. compile {
    from. tree,
    to. flatline,
  },

  root. jit {
    from. tree,
    to. native,
  },

  root. emit_object {
    from. tree,
    to. object,
  },
}
```

A phase has:

```text
name
input world
output world
diagnostic world
cache policy
determinism contract
machine binding
process event contract
```

A root has:

```text
name
input world
requested output world
```

The package is a graph of reusable phase capabilities. A root is not a hidden
ordered script; it is a named request for a transformation from one typed world
to another. Planning selects exactly one simple path through the phase graph.
No path and multiple paths are both diagnostics.

The planner returns schema data, not an ad-hoc Lua table:

```text
Plan {
  root: RootId,
  input: WorldId,
  output: WorldId,
  steps: PlanStep[],
}

PlanStep {
  index
  phase
  machine
  input
  output
  diagnostics
  cache
  deterministic
  abi
  impl
  capabilities
}
```

Execution consumes `Plan` through a registry-backed runtime boundary. Lua and
Moonlift-hosted bindings may resolve through `require(module)[function]`; C,
Cranelift, and external bindings are explicit registry entries. The call
boundary is one input world value to one output world value per step.

A phase run emits an `LlPvm.TaskRun`. Events are typed LLPVM task events,
not compiler-private trace rows:

```text
TaskRun {
  process
  status
  events: [
    phase_start
    cache_hit | cache_miss
    diagnostic*
    output
    phase_done
  ]
  steps: TaskStepRun[]
}
```

## LLPVM compiler image

The compiler package projects to an LLPVM image.

```text
MoonSchema compiler package
  -> LLPVM worlds/phases/machines
  -> moonlift_compiler.llpv
```

A compiler image contains:

```text
schema descriptors
world descriptors
phase graph
machine ABI table
diagnostic schema
root phases
cache policy
```

Host startup becomes:

```text
load compiler image
bind machine implementations
run requested root phase
consume diagnostics/process events
```

## Machine implementations

The compiler graph sees sealed machine implementations.

Implementation kinds:

```text
Moonlift native machine
  Preferred compiler implementation form.

Lua hosted machine
  Host scripting/tooling implementation form.

C ABI machine
  Embedding/runtime boundary.

Cranelift backend machine
  Final native backend boundary.
```

The phase graph does not change when implementation kind changes.

It depends only on:

```text
machine id
input world
output world
diagnostic world
ABI contract
```

## Moonlift projection

MoonSchema can project declarations to Moonlift native data declarations and
phase-machine support code.

```text
MoonSchema products/sums
  -> Moonlift structs/unions/handles/views

MoonSchema phase package
  -> Moonlift region/function signatures
  -> machine ABI shims
  -> native compiler phase implementations
```

This is how Moonlift implements its own compiler phases.

## C projection

C projection is generated from MoonSchema and LLPVM package boundaries.

```lua
Schema.project.c(pkg, {
  prefix = "moon",
  header = "moon_schema.h",
})
```

C sees sealed handles, byte slices, status codes, diagnostics, and phase calls.

Representative ABI shape:

```c
typedef struct moon_context moon_context;
typedef struct { uint32_t index; } moon_tree_ExprId;
typedef struct { const uint8_t *data; size_t len; } moon_bytes;

moon_status moon_load_schema(moon_context *ctx, moon_bytes image);
moon_status moon_validate(moon_context *ctx, moon_diag_sink *sink);
moon_status moon_run_phase(
    moon_context *ctx,
    moon_phase_id phase,
    moon_value_ref input,
    moon_value_ref *output,
    moon_diag_sink *diagnostics
);
```

C does not author schemas. C does not author phases. C consumes sealed
projections.

## Bootstrap loop

The final bootstrap loop is:

```text
MoonSchema Lua files
  -> MoonSchema package

MoonSchema package
  -> runtime projection
  -> T.Moon* classes/builders

MoonSchema package
  -> LLPVM projection
  -> compiler phase image

Moonlift phase implementations
  -> native machine implementations

LLPVM compiler image + native machines
  -> Moonlift compiler running on Moonlift

MoonBack program
  -> Cranelift
  -> native code
```

This gives Moonlift-on-Moonlift without preserving a text ASDL language.

## File organization

Canonical files:

```text
lua/moonlift/schema/dsl.lua
lua/moonlift/schema/package.lua
lua/moonlift/schema/check.lua
lua/moonlift/schema/project_runtime.lua
lua/moonlift/schema/project_llpvm.lua
lua/moonlift/schema/project_moonlift.lua
lua/moonlift/schema/project_c.lua
lua/moonlift/schema/project_docs.lua
lua/moonlift/schema/project_lsp.lua

lua/moonlift/schema/core.lua
lua/moonlift/schema/type.lua
lua/moonlift/schema/tree.lua
lua/moonlift/schema/code.lua
lua/moonlift/schema/back.lua
lua/moonlift/schema/phase.lua
```

Files not in the architecture:

```text
lua/moonlift/schema/*.asdl
lua/moonlift/asdl_lexer.lua
lua/moonlift/asdl_parser.lua
lua/moonlift/asdl_text.lua
```

`schema_context.lua` is replaced or refactored into runtime projection machinery.
It is not fed by text ASDL.

## Non-negotiables

```text
No .asdl text as semantic source.
No duplicate schema type language.
Fields use Moonlift types.
Imports are explicit.
Identity and interning are separate.
Diagnostics are schema-defined.
Projection policy is explicit.
Compiler phases are data.
LLPVM is the executable phase/package projection.
Current ASDL runtime shape is only a generated runtime projection.
C consumes sealed ABI projections only.
```

## Final architecture sentence

```text
MoonSchema is the typed value-level schema language that lets Moonlift define
its own compiler data, package its compiler phases as LLPVM machines, project
those packages to native/C boundaries, and bootstrap without a separate ASDL
text language.
```

## LLPV image shape

LLB does not own bytecode. LLB produces structured language values. MoonSchema
and LLPVM projections lower those values to an LLPV image.

The image is a typed record image:

```text
LLPV image
  header
  symbol records
  schema records
  type records
  LLPVM execution records
  machine records
  diagnostic records
  source/tooling records
  root table
```

The physical encoding can remain compact tagged records. The architectural rule
is stronger than the physical layout:

```text
Every record is a typed fact declared by MoonSchema/LLPVM schema.
No record is an arbitrary Lua table dump.
No semantic fact is hidden in a string payload.
```

### Header

The image header identifies the image and the root table.

```text
magic
version
feature flags
root stream id
root op count
root op table offset
section/record metadata as required by the binary format
```

The current compact header shape is compatible with this model:

```text
u8[4]   magic = "LLPV"
u32     version
u32     root_stream_id
u32     root_op_count
u32     root_op_table_offset
u32[]   root_op_ids
record* tagged records
```

Record shape:

```text
u8      tag
u32     payload_bytes
u8[]    payload
```

The final logical model is sectioned even if the physical encoder stores
section membership as record tags.

### Symbol records

Symbols intern all names used by later records.

```text
symbol "MoonTree"
symbol "Module"
symbol "ModuleId"
symbol "header"
symbol "items"
symbol "typecheck"
symbol "moon_typecheck"
```

Later records reference symbol ids. They do not duplicate strings as semantic
payloads except for explicitly string-valued fields.

### Schema records

Schema records describe MoonSchema modules and declarations.

Record categories:

```text
schema_module
schema_import
schema_product
schema_sum
schema_variant
schema_field
schema_alias
schema_attr
schema_identity
schema_projection
schema_diagnostic_namespace
schema_diagnostic_kind
schema_diagnostic_field
```

Example source:

```lua
schema. MoonTree {
  use. MoonCore,
  use. MoonType,

  product. Module {
    interned,
    identity. ModuleId,
    header [ModuleHeader],
    items [many [Item]],
  },
}
```

Corresponding facts:

```text
symbol MoonTree
symbol MoonCore
symbol MoonType
symbol Module
symbol ModuleId
symbol header
symbol items
symbol ModuleHeader
symbol Item

schema_module MoonTree
schema_import MoonTree -> MoonCore
schema_import MoonTree -> MoonType
schema_product MoonTree.Module
schema_attr MoonTree.Module interned
schema_identity MoonTree.Module ModuleId
schema_field MoonTree.Module.header type=MoonTree.ModuleHeader
schema_field MoonTree.Module.items type=many(MoonTree.Item)
```

A sum:

```lua
sum. Item {
  Func { func [Func] },
  Type { decl [TypeDecl] },
}
```

Corresponding facts:

```text
schema_sum MoonTree.Item
schema_variant MoonTree.Item.Func
schema_field MoonTree.Item.Func.func type=MoonTree.Func
schema_variant MoonTree.Item.Type
schema_field MoonTree.Item.Type.decl type=MoonTree.TypeDecl
```

### Type records

Type records encode Moonlift field types and schema wrappers.

Categories:

```text
type_moonlift_scalar
type_moonlift_named
type_moonlift_ptr
type_moonlift_view
type_schema_many
type_schema_optional
type_schema_ref
type_schema_id
type_schema_map
```

Examples:

```text
str
bool
i64
index
view[u8]
MoonType.Type
many[MoonTree.Item]
optional[MoonSource.Range]
ref[MoonTree.Expr]
id[MoonBind.Binding]
map[str, MoonBind.Binding]
```

The key invariant:

```text
MoonSchema does not invent a scalar type language.
Type records encode Moonlift type values and schema wrappers around them.
```

### LLPVM execution records

Execution records describe the generated LLPVM language object and program
values.

Categories:

```text
llpvm_language
llpvm_world
llpvm_op_kind
llpvm_field
llpvm_stream
llpvm_value
llpvm_payload
llpvm_phase
llpvm_machine
llpvm_cache
llpvm_root
```

For a schema product:

```lua
product. Module {
  header [ModuleHeader],
  items [many [Item]],
}
```

The LLPVM projection creates an operation kind:

```text
llpvm_language MoonTree
llpvm_op_kind MoonTree.Module fields=[header, items]
llpvm_field Module.header type=MoonTree.ModuleHeader
llpvm_field Module.items type=many(MoonTree.Item)
```

For an authored value:

```lua
Module. root {
  header = ModuleSurface,
  items = item_list,
}
```

The image contains:

```text
llpvm_value root kind=MoonTree.Module payload=[header_ref, item_list_ref]
```

For a stream:

```lua
values. tree {
  Module. root { ... },
}
```

The image contains:

```text
llpvm_stream tree world=values ops=[root]
```

### Machine records

Machine records describe executable phase-machine bindings.

Categories:

```text
machine_decl
machine_input_world
machine_output_world
machine_diagnostic_world
machine_abi
machine_impl_binding
machine_capability
```

Example source:

```lua
phase. typecheck {
  from. tree,
  to. checked,
  diagnostics. diag,
  cache. identity,
  deterministic true,
  machine. moon_typecheck,
}
```

Corresponding facts:

```text
world tree type=MoonTree.Module
world checked type=MoonTree.TypecheckResult
world diag type=MoonDiag.Report

machine moon_typecheck
machine_input_world moon_typecheck tree
machine_output_world moon_typecheck checked
machine_diagnostic_world moon_typecheck diag
machine_abi moon_typecheck status_returning

phase typecheck
phase_from typecheck tree
phase_to typecheck checked
phase_diagnostics typecheck diag
phase_cache typecheck identity
phase_machine typecheck moon_typecheck
phase_deterministic typecheck true

root compile
root_input_world compile tree
root_output_world compile back
```

The phase graph consumes machine ids and world ids. It does not depend on
whether the implementation is Lua-hosted, Moonlift-native, C ABI, or Cranelift
backend code.

### Diagnostic records

Diagnostic records come from schema-defined diagnostics.

Source:

```lua
diagnostics {
  error. TypeMismatch {
    expected [MoonType.Type],
    actual [MoonType.Type],
    site [str],
  },
}
```

Facts:

```text
diagnostic_namespace MoonTree
diagnostic_kind MoonTree.TypeMismatch severity=error
diagnostic_field TypeMismatch.expected type=MoonType.Type
diagnostic_field TypeMismatch.actual type=MoonType.Type
diagnostic_field TypeMismatch.site type=str
```

Runtime diagnostic events reference these kinds by id.

```text
diagnostic_event kind=MoonTree.TypeMismatch payload=[expected, actual, site]
```

This lets terminal rendering, LSP, C ABI diagnostics, and process streams share
one typed diagnostic vocabulary.

### Source and tooling records

Source/tooling records are optional but typed.

Categories:

```text
source_file
source_origin
source_span
doc_string
format_hint
lsp_symbol_hint
lsp_hover_hint
projection_note
```

They are not semantic execution data, but they are still typed records. They
must not become unstructured side tables.

### Root table

Roots declare the values/streams/phases retained by the image.

Categories:

```text
root_stream
root_value
root_phase
root_compiler_entry
```

Examples:

```lua
root { root_module }
root { typecheck(input_tree) }
```

Facts:

```text
root_value root_module
root_phase typecheck input=input_tree
```

The compact root op table used by the current bytecode format is a valid
physical representation for hot native imports. Architecturally, roots are typed
references to retained entry points.

## Validation invariants

A valid MoonSchema/LLPVM image must satisfy:

```text
all symbols referenced by records exist
all schema imports resolve
all field types resolve
all identity declarations are unique in their module
all interned declarations have valid identity/structural policies
all sum variant names are unique per sum
all product field names are unique per product
all diagnostic kinds are unique per diagnostic namespace
all diagnostic payload fields resolve
all LLPVM worlds reference valid languages/types
all op payload fields match declared schema fields
all values belong to exactly one world
all streams belong to exactly one world
all phase input/output/diagnostic worlds resolve
all machine bindings match phase signatures
all root references resolve
all projection-specific required facts are present
```

Validation itself is process-shaped and can be summarized as an
`LlPvm.TaskRun`:

```text
TaskRun {
  task = validate
  status
  events = [
    validate_start
    record*
    diagnostic*
    validate_done
  ]
}
```

## Bytecode ownership rule

LLB owns authoring values.

MoonSchema owns schema semantics.

LLPVM owns bytecode format and execution package layout.

Therefore:

```text
LLB does not emit bytecode directly.
MoonSchema/LLPVM projections emit LLPV images from LLB-authored values.
```

This separation keeps LLB generic while making every generated language capable
of producing a compact, typed, portable executable image.
