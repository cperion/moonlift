# Lalin Architecture

Lalin is a LuaJIT-hosted dialect of the LLBL language.

LLBL is the central engineering artifact: the extensible language workbench and the
bootstrap language used to define member dialects. It gives Lua values dialect
meaning through heads, roles, fragments, namespaces, origins, diagnostics,
formatting, indexing, regions, protocols, processes, and language composition.
Lalin is the compiled dialect in that language. It consumes LLBL regions and typed
values, checks native semantics, and lowers the resulting program into LuaJIT
artifacts.

The main path is intentionally small:

## Current Compiler Architecture

The compiler is split into four ownership layers:

- `lalin.asdl` is the minimal runtime for schema contexts, class lookup,
  immutable structural updates, required-method checks, and triplet helpers. It is
  not a phase/cache runtime and does not expose `phase`.
- ASDL classes own typed semantic behavior through ordinary Lua methods assigned
  directly to schema class tables. Missing required methods are compiler bugs
  reported with the source class and operation name.
- A semantic method is not a selector. It must implement the operation for that
  concrete class and return the operation's real result. Methods that only
  return `kind`, handler keys, relation names, or other dispatch tokens preserve
  the old rule-table architecture and are not allowed.
- Semantic methods do not take a generic `ctx` bag by convention. They take only
  the typed, well-named semantic products they actually need, and take no extra
  argument when none is needed. State changes are represented by returned typed
  products, not by mutating a catch-all context.
- Compiler drivers and compiler-process modules sequence stages, allocate
  context, collect diagnostics, and pass typed products between stages. They do
  not own per-class semantics.
- Backends operate on explicit ASDL facts, plans, and IR. Backend artifact
  selection is represented in typed plans/results, not hidden fallback control
  flow.

Semantic methods are plain Lua methods on schema-generated classes:

```lua
local T = require("lalin.asdl").context()
require("lalin.schema")(T)

function T.LalinTree.ExprBinary:typecheck_tree_expr(type_env)
  -- node-specific semantics live here
end

return node:typecheck_tree_expr(type_env)
```

## Two authoring paths

Lalin has two surfaces that converge on the same ASDL:

| Path | How | When |
|------|-----|------|
| **`.lln` value chunks** (primary) | `fn ... end` syntax loaded by `lalin.loader` or Lua `require` | Hand-written code |
| **Builder API** (internal) | `lln.fn. name { ... }` Lua DSL heads | Macros, generators, tooling |

```text
┌─ Hand-written source ─────────────────┐
│                                        │
│  fn add(a: i32, b: i32): i32          │
│    return a + b                        │
│  end                                   │
│                                        │
│  → lalin.loadfile / Lua require        │
│    → lalin.loader activates syntax     │
│      → llbl.syntax driver rewrites     │
│        → lalin.syntax.parse_entry      │
│          → parsed AST nodes            │
│            → lalin.syntax.to_module()  │
└────────────────────────────────────────┘
                    │
                    ▼
┌─ Builder / Macro ─────────────────────┐
│                                        │
│  lln.fn. add { a [lln.i32], ... }     │
│    lln.ret (a + b),                    │
│                                        │
│  → Lua evaluates table literals        │
│    → LLBL staged heads capture values  │
│      → Decl values with Decl:syntax()  │
│        → LalinTree.Module             │
└────────────────────────────────────────┘
                    │
                    ▼

Both paths produce the same LalinTree.Module and share the pipeline below.

---

## Shared Compiler Pipeline

The compiler is organized around semantic products, not chronological steps.

```
LalinTree.Module
  │
  ▼
┌─────────────────────────────────────────┐
│ Frontend Pipeline                       │
│  Pipeline.typecheck_module()            │
│    ├─ SurfaceResolve                    │
│    ├─ ClosureConvert                    │
│    └─ Typecheck.check_module            │
│  → LalinTree.TypeModuleResult           │
└─────────────────────────────────────────┘
  │
  ▼
┌─────────────────────────────────────────┐
│ 3. Tree → Code IR                       │
│    Pipeline.checked_to_code_result()    │
│      ├─ LayoutResolve                   │
│      ├─ tree_to_code (LalinTree→LalinCode)│
│      └─ CodeValidate                    │
│    → CodeResult(code_module, contracts) │
└─────────────────────────────────────────┘
  │
  ▼
┌─────────────────────────────────────────┐
│ 4. Fact Analysis (code_*.lua)           │
│    Backend.lower_module()               │
│      ├─ CodeGraph (CFG builder)          │
│      ├─ FlowFacts (loops, domains)       │
│      ├─ ValueFacts (algebra, ranges)     │
│      ├─ MemFacts (objects, aliasing)     │
│      ├─ EffectFacts (side effects)       │
│      ├─ KernelPlan (parallelizable kernels)│
│      ├─ SchedulePlan (exec policy)       │
│      └─ LowerPlan (strategy per fragment)│
│    → KernelModulePlan + SchedulePlan     │
└─────────────────────────────────────────┘
  │
  ▼
┌─────────────────────────────────────────┐
│ 5. Stencil Planning                     │
│    StencilMachine + StencilArtifactPlan │
│    → StencilArtifact[] (apply, reduce,   │
│       scan, gather, scatter, etc.)       │
└─────────────────────────────────────────┘
  │
  ▼
┌─────────────────────────────────────────┐
│ 6. LuaJIT Lowering (luajit_lower)       │
│    Lower → LalinLuaJIT IR (LJModule)    │
│    ExecPlan (fragment division)          │
└─────────────────────────────────────────┘
  │
  ▼
┌─────────────────────────────────────────┐
│ 7. Materialization (residual_*)       │
│    ┌─ MC path (emit_luajit_artifact):    │
│    │  residual_mc.lua                  │
│    │    → load prebuilt gcc-O3 blobs     │
│    │    → mmap executable memory         │
│    │    → (optional) TCC residual glue   │
│    │                                     │
│    └─ explicit BC path:                  │
│       residual_luatrace.lua              │
│         → LuaJIT BC stencil tables       │
│         → inline Lua data with BC patches│
└─────────────────────────────────────────┘
  │
  ▼
┌─────────────────────────────────────────┐
│ 8. Lua Source Emission (luajit_emit)    │
│    → embed MC bytes or BC bank          │
│    → emit LuaJIT function definitions   │
│    → wrap in loadable Lua module         │
│    → loadstring → chunk() → module       │
└─────────────────────────────────────────┘
```

---

## Concrete Example Trace

How `lln.fn. add { a [lln.i32], b [lln.i32] } [lln.i32] { lln.ret (a + b) }`
becomes a loaded MC artifact:

```
1. LuaJIT evaluates lln.fn.add{...}
   → DSL Decl metatable (kind="fn", name="add", params=[a,b], ...)

2. dsl.to_unit("demo", decl)
   → Decl:syntax() → LalinTree.Module{ items={ItemFunc{...}} }

3. Pipeline.typecheck_module(module)
   → SurfaceResolve → ClosureConvert → Typecheck
   → TypeModuleResult{ checked = { module = { funcs={...} } } }

4. Pipeline.checked_to_code_result(checked)
   → LayoutResolve → tree_to_code → CodeValidate
   → CodeResult{ code_module = CodeModule{ funcs={...} } }

5. Backend.lower_module(code_module)
   → graph(CFG) → flow_facts → value_facts → mem_facts → effect_facts
   → kernel_plan (identifies "add" as trivial, no kernel needed)
   → schedule_plan → lower_plan
   → StencilMachine + StencilArtifactPlan
     (for a+b, produces no stencil — scalar path is fine)
   → Lower.lower_module() → LJModule{ funcs={add=...} }
   → ExecPlan → ExecModulePlan

On the default MC-first path:

6. Resolve the supplied/prebuilt MC bank
   → match selected artifact fingerprints against bank entries
   → no C compiler is invoked by the runtime compile path

7. emit_lua_artifact() emits Lua source with:
   - Embedded MC stencil bytes
   - LuaJIT function definitions for non-stencil code
   - Optional TCC residual wrappers

8. loadstring(source) → chunk() → module table
   module.add(3, 4) → runs scalar LuaJIT code or installed native stencils

If the MC bank is missing, stale, or cannot materialize, MC materialization fails
with an explicit diagnostic. The BC materializer is selected only by
`residual = "bc"`.

In explicit BC mode:
   - BC stencil bytecode is loaded
   - LuaJIT function definitions call BC stencils

8. loadstring(source) → chunk() → module table
   module.add(3, 4) → runs via LuaJIT bytecode stencils
```

---

## File Map

### DSL Surface

| File | Role |
|------|------|
| `lua/lalin/dsl/init.lua` | Lua-owned DSL surface. Defines `fn`, `struct`, `ret`, `if`, `region`, etc. heads. `to_unit()` converts Lua values into `LalinTree` ASDL. |
| `lua/lalin/dsl/format.lua` | Canonical semantic formatter for evaluated DSL values. |

### Frontend / Typecheck

Migrated LalinTree semantics live on ASDL classes as ordinary Lua methods.
Concrete union members own their own behavior; rewritten code must not use
`schema.classof(x) == Variant`, `kind` strings, or selector tables to choose
semantic behavior. When the method API needs more schema support, add it to
ASDL first; nullary variants also receive methods directly with normal
`function Module.Variant:operation(...) ... end` syntax.

| File | Role |
|------|------|
| `lua/lalin/frontend_pipeline.lua` | Orchestrates DSL→Tree→Typecheck→Code pipeline. Entry points: `typecheck_module`, `checked_to_code_result`, `code_result_to_back`, `code_result_to_c`. |
| `lua/lalin/tree_typecheck.lua` | Typecheck entrypoint and remaining stage orchestration while LalinTree methods are being split out. |
| `lua/lalin/tree_typecheck_type.lua` | Type-owned typecheck semantics for `LalinType` and literals. |
| `lua/lalin/tree_typecheck_expr.lua` | Expression/ref-owned typecheck semantics for `LalinTree.Expr*` and `LalinBind.ValueRef*`. |
| `lua/lalin/tree_typecheck_layout.lua` | Layout/ref matching semantics for `LalinSem.TypeLayout*` and `LalinType.TypeRef*`. |
| `lua/lalin/tree_expr_type.lua` | Expression type inference. |
| `lua/lalin/tree_stmt_type.lua` | Statement-level type operations (termination, etc.). |
| `lua/lalin/tree_place_type.lua` | Place (lvalue) type inference. |
| `lua/lalin/tree_module_type.lua` | Module-level type resolution, type environments, imports. |
| `lua/lalin/tree_field_resolve.lua` | Field resolution — struct.field to types and offsets. |
| `lua/lalin/tree_contract_facts.lua` | Contract facts from function declarations (bounds, disjointness, SoA). |
| `lua/lalin/tree_control_facts.lua` | Control-flow facts from control regions (entry/block/continuation). |
| `lua/lalin/tree_to_code.lua` | Typed AST to `LalinCode` lowering; ASDL classes own tree→code methods. |

### Code IR & Fact Analysis

| File | Role |
|------|------|
| `lua/lalin/code_type.lua` | Code type operations, size/alignment, target configuration. |
| `lua/lalin/code_validate.lua` | Validates `LalinCode` IR invariants. |
| `lua/lalin/code_graph.lua` | CFG builder — basic blocks, edges, loops, function-level graphs. |
| `lua/lalin/code_flow_facts.lua` | Flow analysis — domains, trip counts, loop structure. |
| `lua/lalin/code_value_facts.lua` | Value analysis — algebra, closed-form expressions, ranges, reductions. |
| `lua/lalin/code_mem_facts.lua` | Memory analysis — objects, intervals, aliasing, access patterns. |
| `lua/lalin/code_effect_facts.lua` | Effect analysis — read/write/atomic/rw, contract effects. |
| `lua/lalin/code_kernel_plan.lua` | Kernel identification — finds parallelizable loop/function fragments, produces `LalinKernel` plans; loop selection is typed ASDL behavior. |
| `lua/lalin/code_schedule_plan.lua` | Schedule planning — assigns scalar/vector/closed-form strategies per kernel; schedule selection is typed ASDL behavior. |
| `lua/lalin/code_lower_plan.lua` | Lowering strategy — decides code/kernel/closed-form per fragment; lower-fragment selection is typed ASDL behavior. |
| `lua/lalin/code_aggregate_abi.lua` | Aggregate type ABI classification — scalar/view/slice/bytespan/aggregate. |
| `lua/lalin/code_to_back.lua` | Maps `LalinCode` types/shapes to `LalinBack` back IR. |
| `lua/lalin/code_to_c.lua` | Maps `LalinCode` types/shapes to `LalinC` C IR. |

### Stencil & Execution Plans

| File | Role |
|------|------|
| `lua/lalin/exec_plan.lua` | Produces `LalinExec` plans — divides functions into scalar blocks, stencil calls, control, calls, returns, traps; exec stencil selection uses typed ASDL methods. |
| `lua/lalin/stencil_methods.lua` | Stencil-machine methods — classifies kernel body into point-expression plus sink vocabulary without a relation runner. |
| `lua/lalin/stencil_artifact_plan.lua` | Generates canonical stencil artifacts: `store_n`, `reduce_n`, `scan_n`, and scatter-reduce descriptors. Store-shaped loops are `store_n` with explicit point body, sink, and layout modes. |
| `lua/lalin/stencil_c.lua` | Generates complete C translation unit from stencil artifacts for GCC compilation. Produces the C source that becomes the MC bank. |
| `lua/lalin/stencil_metastencil.lua` | Cross-provider stencil matching (MC bank ↔ BC bank equivalence). |
| `lua/lalin/stencil_support_matrix.lua` | Declares which stencil operations are supported/rejected/future. |

### LuaJIT Backend

| File | Role |
|------|------|
| `lua/lalin/luajit_backend.lua` | Central backend orchestration — lower_module(), build_mc_bank(), build_bc_bank(), emit_lua_artifact(). |
| `lua/lalin/luajit_lower.lua` | Lowers `LalinCode` + kernel plans to `LalinLuaJIT` IR. Builds stencil machines; kernel/skeleton stencil lowering selection uses typed ASDL methods. |
| `lua/lalin/luajit_emit.lua` | Emits Lua source from `LalinLuaJIT` IR — LuaJIT functions with FFI ctypes and stencil calls. |
| `lua/lalin/luajit_expr.lua` | Lua expression utilities for emission. |
| `lua/lalin/luajit_ctype.lua` | Converts `LalinCode.CodeType` to LuaJIT FFI ctype descriptors. |
| `lua/lalin/luajit_measure.lua` | Runtime measurement utilities (sizes, alignment, pointer bits). |

### Copy-Patch Materialization

| File | Role |
|------|------|
| `lua/lalin/residual_mc.lua` | **MC (machine code) path** — installs pre-compiled stencil blobs via mmap+exec, provides FFI wrappers. MC stencils are compiled by gcc at prebuild time. |
| `lua/lalin/residual_mc_intern_set.lua` | Intern set for MC stencils — deduplicates by canonical content hash, registry of reusable blobs. |
| `lua/lalin/residual_bc.lua` | BC bank platform — runtime target detection, target matching, bank identity. |
| `lua/lalin/residual_luatrace.lua` | **BC (bytecode) path** — LuaTrace trace-shaped stencil code, BC copy+compile residual materialization. Fallback/probe surface. |

### C Backend

| File | Role |
|------|------|
| `lua/lalin/c_emit.lua` | Emits C source from `LalinC.BackendUnit` — .c, .h, combined artifact output. |
| `lua/lalin/lower_to_c.lua` | Lowers `LalinCode` + lower plan to C IR. |
| `lua/lalin/c_validate.lua` | Validates C IR invariants. |
| `lua/lalin/c_helpers.lua` | C helper function library for stencil operations. |
| `lua/lalin/c_tcc.lua` | libtcc (TinyCC) integration for in-process C JIT compilation of residual glue wrappers. Not used for stencil compilation. |
| `lua/lalin/c_abi.lua` | C ABI classification — how types are passed/returned. |
| `lua/lalin/c_coverage.lua` | Coverage tracking — marks unimplemented C backend constructs. |

### Compiler Process

| File | Role |
|------|------|
| `lua/lalin/compiler_driver.lua` | Public orchestration boundary — lowers modules through the compiler-process graph. |
| `lua/lalin/compiler_package.lua` | Defines the compiler process as a `LalinPhase` package with worlds, machines, phases, roots. `LalinPhase` is process vocabulary, not the removed PVM recording runtime. |
| `lua/lalin/compiler_machines.lua` | Concrete machine implementations (typecheck, checked→c_code, code→c). |
| `lua/lalin/compiler_model.lua` | Loads full schema into a context. |
| `lua/lalin/compiler_abi.lua` | CodeResult ABI validation. |
| `lua/lalin/phase_model.lua` | Loads LalinPhase schema. |
| `lua/lalin/phase_dsl.lua` | LLBL dialect for authoring phase packages. |
| `lua/lalin/phase_plan.lua` | Phase graph planner — finds valid paths, produces ordered Plan. |
| `lua/lalin/phase_execute.lua` | Plan executor — runs phase steps, resolves machines, passes outputs. |
| `lua/lalin/phase_validate.lua` | Validates phase package structure. |

### Back Infrastructure

| File | Role |
|------|------|
| `lua/lalin/back_program.lua` | Back IR program construction utilities. |
| `lua/lalin/back_inspect.lua` | Inspection/debug tools for back IR. |
| `lua/lalin/back_command_binary.lua` | External compiler invocation (TCC, GCC). |
| `lua/lalin/back_provenance.lua` | Provenance tracking for back IR values. |
| `lua/lalin/back_target_model.lua` | Target model — CPU features, ABI, capabilities. |
| `lua/lalin/back_validate.lua` | Back IR validation. |

### Error / Diagnostics

| File | Role |
|------|------|
| `lua/lalin/error/init.lua` | Error management facade — registry, emit, reports, render. |
| `lua/lalin/error/span.lua` | Source span type and operations. |
| `lua/lalin/error/report.lua` | ErrorReport construction. |
| `lua/lalin/error/catalog.lua` | Error catalog — code registry, explainers by phase. |
| `lua/lalin/error/registry.lua` | Issue registry — collects, deduplicates, produces reports. |
| `lua/lalin/error/format.lua` | Shared formatting utilities. |
| `lua/lalin/error/present_terminal.lua` | Terminal rendering of diagnostics. |
| `lua/lalin/error/issue_collector.lua` | CollectingCollector and ThrowingCollector — phase boundary to diagnostic engine. |
| `lua/lalin/error/cascade_filter.lua` | Cascade suppression filter. |
| `lua/lalin/error/span_resolvers.lua` | Phase-specific span resolvers. |
| `lua/lalin/error/suggest.lua` | Error suggestions. |

### Source Infrastructure

| File | Role |
|------|------|
| `lua/lalin/source_anchor_index.lua` | Source anchor index — maps positions to anchors. |
| `lua/lalin/source_position_index.lua` | Line/column position index. |
| `lua/lalin/source_map.lua` | Source location mapping utilities. |
| `lua/lalin/source_analysis.lua` | Source analysis utilities. |
| `lua/lalin/source_text_apply.lua` | Source text manipulation operations. |

### Prebuild Tools

| File | Role |
|------|------|
| `tools/gen_lalin_mc_bank.lua` | Prebuilds the embedded MC stencil bank. Generates all stencil artifacts from the intern set, compiles them via `gcc -O3 -march=native`, extracts binary blobs, and emits `lalin_embedded_mc_bank.c`/`.h`. |
| `tools/gen_lalin_module_bank.lua` | Prebuilds the LuaJIT BC bank. Dumps all required `.lua` source files to bytecode and emits C byte-array sources for embedding. |

### Other

| File | Role |
|------|------|
| `lua/lalin/init.lua` | Public facade — `.lln` value loading, `lalin.compile`, `lalin.emit_c_artifact`, etc. |
| `lua/lalin/loader.lua` | `.lln` loadfile/loadstring/searchpath/searcher integration. |
| `lua/lalin/cli.lua` | CLI interface. |
| `lua/lalin/ast.lua` | AST utility layer. |
| `lua/lalin/quote.lua` | Quotation utilities. |
| `lua/lalin/reduction_algebra.lua` | Reduction algebra (commutative, associative) for stencil optimization. |
| `lua/lalin/value_proxy.lua` | Value proxy for DSL values. |
| `lua/lalin/closure_convert.lua` | Closure conversion pass. |
| `lua/lalin/surface_resolve.lua` | Surface name resolution. |
| `lua/lalin/sem_call_decide.lua` | Call semantic decision. |
| `lua/lalin/sem_const_eval.lua` | Constant evaluation. |
| `lua/lalin/sem_layout_resolve.lua` | Layout resolution. |
| `lua/lalin/sem_switch_decide.lua` | Switch dispatch decision. |
| `lua/lalin/project_asdl.lua` | Project ASDL utilities. |
| `lua/lalin/project_ready_facts.lua` | Project readiness facts. |
| `lua/lalin/project_report.lua` | Project report generation. |
| `lua/lalin/buffer_view.lua` | Buffer view utilities. |
| `lua/lalin/flatline.lua` | Flatline — debug representation for ASDL values. |

---

## Schema / ASDL Modules

Each file in `lua/lalin/schema/` returns a `lalinschema` Module defining
the ASDL types for that domain:

| File | Key Types |
|------|-----------|
| `core.lua` | Name, Path, Id, Scalar, Literal, BinaryOp, CmpOp, CastOp, Intrinsic, AtomicOrdering |
| `type.lua` | Type — TScalar, TPtr, TView, TSlice, TArray, TLease, TOwned, TAccess, THandle, TClosure, TFunc, Param, FieldDecl |
| `tree.lua` | Module, Expr (30+ variants), Stmt (20+), Place, Func, ConstItem, Region, ControlBlock, SwitchArm, Domain |
| `code.lua` | CodeModule, CodeFunc, CodeBlock, CodeInst, CodeTerm, CodeType, CodeValue, CodeOp, CodeContract |
| `graph.lua` | Graph, GraphFunc, GraphEdge, GraphLoop, GraphBlock |
| `flow.lua` | FlowDomain, FlowTripCount, FlowEdgeFact, FlowModuleFacts |
| `value.lua` | ValueExpr, ClosedFormFact, ReductionFact, AlgebraProof, ValueModuleFacts |
| `mem.lua` | MemObject, MemAccess, MemInterval, MemAccessPattern, MemModuleFacts |
| `effect.lua` | OpEffect, EffectModuleFacts |
| `kernel.lua` | KernelSubject, KernelDomain, KernelLane, KernelPlan, KernelReject, KernelModulePlan |
| `stencil.lua` | StencilArtifact, StencilPlan, StencilSinkVocab, StencilLayout, StencilModulePlan |
| `schedule.lua` | KernelSchedule, ScheduleKind, ScheduleModulePlan |
| `lower.lua` | LowerFragment, LowerStrategy, LowerModulePlan |
| `exec.lua` | ExecFragment, ExecFragmentKind, ExecModulePlan |
| `residual.lua` | ResidualFunctionPlan, stencil patch-template families/coordinates, patch plans, C residual units |
| `back.lua` | BackTargetModel, BackFunc, BackBlock, BackInst, BackProgram |
| `c.lua` | CBackendUnit, CBackendFunc, CBackendType, CBackendStmt |
| `c_ast.lua` | C AST node types |
| `luajit.lua` | LJModule, LJFunc, LJBlock, LJExpr, LJInst, LJCType, LJStencilMachine |
| `luatrace.lua` | LuaTrace trace descriptors, BC bank types |
| `compiler.lua` | CodeResult, FlatlineImageIssue |
| `phase.lua` | Package, World, Machine, Phase, Root, Plan, PlanStep |
| `bind.lua` | Binding, ValueRef |
| `sem.lua` | FieldRef, FieldLayout, TypeLayout, LayoutEnv, ConstValue |
| `link.lua` | Link plan and target model |
| `host.lua` | Host field representation |
| `parse.lua` | Parse tree types |
| `source.lua` | Source location types |
| `mlua.lua` | MLua document analysis |
| `project.lua` | Project structure |

---

## Native Residual Direction

The target backend direction is described in
`docs/RESIDUAL_NATIVE_ARCHITECTURE.md`: stencil instances define exact
semantics, copy-patch expands binary patch templates for selected instances, TCC
compiles non-stencil C residuals, and LuaJIT hosts/loads rather than silently
executing fallback loops.

The target decision is a typed residual function plan:

```text
ResidualFunctionExactStencil
| ResidualFunctionPatchTemplate
| ResidualFunctionC
| ResidualFunctionRejected
```

Stencil instances remain the semantic identity. Patch-template families are a
typed projection of those instances into binary templates with holes, not a
looser stencil language and not a SOAC storage category. C residuals are the
native path for code that does not squarely fit a selected stencil template.
Rejection is explicit and typed.

The sections below describe the current materializers and C/AOT path. Some of
that implementation still has LuaJIT-shaped names because LuaJIT remains the
host and loader, but the architectural direction is native residual
materialization.

## Two Copy-Patch Materialization Paths

These are the LuaJIT-hosted executable paths. Lua remains the loader and FFI
host; hot stencil bodies are materialized as MC bank blobs or explicit bytecode
artifacts.

### MC Path (prebuilt, fast)

```
PREBUILD (Makefile / gen_lalin_mc_bank.lua):
  stencil_intern_set (residual_mc_intern_set)
    → enumerate all stencil operation combinations
    → StencilC.source(artifacts) → complete C translation unit
    → gcc -c -std=c99 -O3 -march=native -fno-builtin -fno-pic ...
    → readelf -Wr (relocations) / -SW (sections) / -Ws (symbols)
    → materialize each .text.<symbol> section into binary blob
      (resolve all local relocations, no runtime fixups needed)
    → embed as unsigned char[] arrays in
      lalin_embedded_mc_bank.c / lalin_embedded_mc_bank.h

RUNTIME / ARTIFACT EMISSION (emit_luajit_artifact):
  selected artifacts
    → resolve supplied/prebuilt MCStencilBank
    → emit_mc_bank_source(bank)
    → emit Lua source with embedded MC blobs
    → at load: mmap() executable memory, ffi.copy() stencil bytes,
      mprotect() RW→X, ffi.cast() to function pointers
  Current optional step: emit_native_residuals()
    → libtcc compiles C wrappers in-memory
    → wrappers call installed stencils through host symbols
    → replaces LuaJIT trace calls with direct native FFI calls
  Target step:
    → ResidualFunctionC emits non-stencil residual code as C
    → TCC links residual C to exact/patched stencils
  → load: installed native code, optionally wrapped by TCC glue
```

The public MC path consumes an MCStencilBank. It does not invoke `gcc` from the
normal runtime compile path. Use `build_mc_bank` from an explicit prebuild step
or supply an externally generated/embedded bank through `mc_bank`. Missing-bank
or materialization failures are hard errors.

**Key facts**:
- Compiler: `gcc` (or `$CC`), default flags `-std=c99 -O3 -march=native -c`
- Time: explicit prebuild only; runtime loads or embeds an existing bank
- Output: binary blobs embedded in emitted Lua artifacts, or in the `lalin` host
  binary for prebuilt banks
- TCC role: runtime C residuals and host-symbol linking to installed stencils;
  not stencil optimization

### BC Path (explicit bytecode path)

```
Canonical stencil artifacts
  → residual_luatrace.realize_bc_artifacts(artifacts)
    → generate LuaTrace trace-shaped stencil tables
    → build BC bank with artifact fingerprints
    → emit inline Lua data with BC copy+compile residual
  → luajit_emit embeds BC bank data
  → load: LuaJIT compiles the emitted functions
```

No external compiler needed. The BC bank is built on the fly at runtime when
`residual = "bc"` is selected explicitly or when default MC materialization
falls back with a warning.

---

## C / AOT Emission Path

`emit_c_artifact` is the whole-program C path. It is not another LuaJIT
materializer. It lowers the selected typed program to C so the user can compile
the generated artifact with `gcc` or another C compiler and get their program.

Conceptually:

```text
LalinTree.Module
  -> typecheck
  -> LalinCode facts
  -> kernel/stencil selection
  -> fuse selected stencil-shaped work at C level
  -> emit C implementation + header/support
  -> user compiles the C artifact with gcc
```

This path exists for AOT/native integration:

- The artifact is ordinary C source plus generated header/support pieces.
- Selected stencil-shaped loops should become C-level fused code, so GCC sees
  the hot loop body instead of a LuaJIT call boundary.
- The user owns the final compiler invocation, flags, linker inputs, and target
  ABI choices.
- `emit_c_artifact` is the path for “compile the whole program with GCC”.
  `residual_mc` is the path for “load a LuaJIT module that calls prebuilt GCC
  stencil blobs”.

The ownership boundary is:

| Path | Host | Compiler role | Output |
|------|------|---------------|--------|
| `emit_c_artifact` | user/native program | compile emitted program C | C source/header/support |
| `residual_mc` | LuaJIT | prebuild reusable stencil blobs | Lua module installing MC bank entries |
| `residual_bc` | LuaJIT | none | Lua module with bytecode stencil bank |

---

## Region Model

`region.` is the generic LLBL control-machine head. This is one of the main
reasons LLBL composes the whole language: the same control algebra can describe
native CFG, processes, parser steps, scheduler steps, LLPVM tasks, and backend
pull machines. A region is:

```text
input product + state product + named exit protocol + transition body
```

Streams are not a separate semantic category. A pull stream is a region with a
pull protocol. GPS is one lowering of a pull-shaped region:

```lua
gen(param, state) -> nil
gen(param, state) -> next_state, payload...
```

This keeps laziness and fusion explicit. A consumer asks for the next exit; the
machine computes only enough to produce that exit. Whole arrays, reports,
diagnostic bags, backend buffers, and artifacts are materializers, not the
region itself.

Lalin consumes generic region descriptors when the body uses native Lalin
`entry`, `block`, `jump`, and `emit` vocabulary. LLPVM consumes region-shaped
work as phase/task machines. LLBL processes lower event protocols to GPS.

Region composition has two runtime shapes:

```text
emit
  direct CFG splice; no frame; all exits wired at the call site

call
  instrumentable/recursive boundary; implemented as sealed function plus
  encoded exit union plus dispatch back to named exits
```

Use `emit` for ordinary internal composition. Use `call` when the region needs
its own frame for recursion, profiling, debugging, or instrumentation.

---

## Language Layers

LLBL owns the extensible language substrate. This is the center of the
architecture:

- symbols and namespace values
- staged heads and role normalization
- fragments and spread expansion
- origins, comments, diagnostics, formatting, and indexing hooks
- generic regions, protocols, GPS lowering, and process events
- language composition and managed `use()` sessions

The `llbl` member is the identity element of language composition. Composing a
language with `llbl.core_language()` returns the other language when no rename or
preference override is requested. Every language therefore shares the same bare
substrate by default: symbol creation, source/generated symbol provenance,
origin tracking, diagnostics, fragments, regions, the formatting document
model, and language export ownership.

The identity-owned service surface is:

```text
llbl.shared.symbols
llbl.shared.origins
llbl.shared.diagnostics
llbl.shared.fragments
llbl.shared.regions
llbl.shared.formatting
llbl.shared.languages
```

Symbol resolution is shared, but symbol meaning is not. LLBL resolves a symbol
to a language binding:

```lua
local binding = language:resolve_symbol(sym)
```

The binding says which language member exported the name, whether the source was
generated, and whether the symbol is unresolved. Lalin, LLPVM, LalinSchema, and
other dialects decide what that binding means semantically.

The language audit records more than ownership. It records:

```text
owns / uses
resolves / formats / indexes / lowers / materializes
```

Those capability axes are the review surface for existing dialects.

LLBL bootstraps itself in two stages:

- `llbl.kernel`: the small Lua stage-0 substrate that owns primitive values,
  origins, diagnostics, GPS, regions, stage-0 grammar records, and the dialect
  compiler.
- `llbl.self`: the stage-1 `llbl` dialect, built by `lua/llbl/bootstrap.lua` using
  the stage-0 substrate.
- `llbl.grammar`: the public grammar facade backed by `llbl.self`; it emits the
  same declaration records expected by the dialect compiler, but the facade
  itself is now an LLBL dialect surface.
- `llbl.bootstrap.machines`: region-backed bootstrap machines for work such as
  role normalization and doc rendering.

Lalin is the compiled member. It owns native language semantics:

- scalar, pointer, view, handle, lease, and owned type values
- declarations, products, protocols, functions, and regions
- expression and statement semantics
- resource and ownership checking
- typecheck, lowering, and backend projection

LalinSchema owns schema/type-language semantics:

- product and sum schema declarations
- typed ASDL constructor families
- schema projection into runtime values

LLPVM owns low-level VM/task semantics:

- bytecode images and borrowed buffers
- worlds, tapes, machines, phases, tasks, and run records
- process-shaped validation and inspection

The reduction rule is strict: if two members can express the same semantic
primitive, one member owns it and the other projects to it. Overlapping
implementations are a design bug, not a feature.

---

## Compiler Boundaries

Important boundaries:

- DSL normalization produces explicit Lalin syntax/tree values.
- Typechecking owns name, type, ownership, and control validity.
- LalinCode is the normalized compiler product used by later lowering.
- Kernel facts describe recognized loop/control/dataflow structure.
- Schedule facts describe execution policy such as vectorization and unroll.
- Stencil plans select materializable execution descriptors.
- LuaTrace/LuaJIT materializers build executable artifacts.

Schedules are not semantics. They may choose lanes, tails, grouping, and
compiler/materializer policy, but they may not invent effects, stores,
reductions, alias facts, or safety conditions.

---

## Backend Model

The backend has two materialization paths, selected by `opts.residual`:

| Path | Default for | Compiler needed | Build time |
|------|-------------|-----------------|-----------|
| `residual = "mc"` | `lalin.compile()`, `emit_luajit_artifact()` | `gcc` (or `$CC`) with `-O3 -march=native` | Explicit prebuild only |
| `residual = "bc"` | Explicit bytecode mode | None | On the fly at runtime |

The two paths share the same stencil planning pipeline and differ only in
materialization strategy.

### MC Path (`residual_mc`)

The MC path owns hot stencil bodies as pre-compiled native machine code.

**Prebuild** (`tools/gen_lalin_mc_bank.lua`, run by `make`):
- The intern set (`residual_mc_intern_set.lua`) enumerates every covered
  stencil descriptor combination (`store_n`, `reduce_n`, `scan_n`, `scatter_reduce_n`
  × all memory layouts × all producer shapes × scalar/vector schedule).
- `StencilC.source()` generates a complete C translation unit with one
  function per stencil variant.
- `gcc -c -std=c99 -O3 -march=native` compiles to an object file.
- `readelf` parses relocations, sections, and symbols; each `.text.<symbol>`
  section is materialized into a self-contained binary blob with all local
  relocations resolved.
- The blobs are embedded as `unsigned char[]` in
  `lalin_embedded_mc_bank.c` / `.h` and compiled into the `lalin` host binary.

**Artifact emission / runtime**:
- The selected stencil artifacts are matched against a supplied/prebuilt MC bank.
- The MC stencil bytes are embedded in the emitted LuaJIT artifact and installed
  via `mmap()` + `ffi.copy()` into executable memory, then `ffi.cast()` to get
  function pointers.

### Residual JIT (TCC, optional, MC path only)

The residual JIT compiles thin C wrappers around installed MC bank stencils.
It is compiled by **libtcc** (in-memory, in-process, no external process):

- For each LuaJIT function that calls an MC bank stencil, a small C wrapper
  function is generated (e.g., `int32_t wrapper(void *xs, int32_t start, int32_t stop) { ... }`).
- libtcc compiles all wrappers as a single in-memory translation unit.
- The resulting symbols replace the original LuaJIT trace calls with direct
  native FFI calls at coarse function/stencil boundaries.
- This is optional and skipped if libtcc is unavailable.
- The residual must not become an element-by-element FFI strategy.

### BC Path (`residual_bc`)

The BC path is the explicit bytecode semantic path and probe surface:

- LuaTrace lowering emits trusted LuaJIT-shaped functions from typed stencil
  plans.
- The BC bank stores exact compiled prototypes with artifact fingerprints.
- Materialization loads the selected bytecode entry without bytecode holes.
- No external compiler needed — the BC bank is built on the fly at runtime.
- `lalin.compile()` defaults to MC. This path is used only when selected with
  `residual = "bc"`.

### Ground rules

Artifact emission is plan → selected stencil artifacts → supplied MC bank →
optional residual glue. If the MC bank is missing or materialization fails,
default materialization fails. The explicit `residual = "bc"` path may build a
local bytecode bank because
BC is the semantic artifact itself.

The backend must consume semantic facts honestly:

The backend must consume semantic facts honestly:

- type families and ABI layout
- array/view/span descriptors
- readonly, bounds, alias, and residence facts
- reductions and effect classification
- vectorization schedule policy
- target and materializer constraints

If a fact is required for correctness or performance but is not represented in
ASDL, the schema is incomplete and must be fixed before lowering is extended.

---

## C And Native Stencil Role

The C path is an optional projection and measurement tool. It is useful for:

- checking semantic equivalence against a simple generated target
- generating native MC banks ahead of time
- comparing LuaJIT and C compiler performance
- making target ABI decisions explicit

It is not the main authoring runtime.

---

## Diagnostics

Diagnostics are structured values. They should carry:

- code
- message
- primary origin
- related origins
- head, slot, role, event, or phase context when available
- prose comments captured from source context where useful

Fast generated paths should be diagnostically lazy. They carry compact metadata
and replay through reflective machinery on failure when a rich diagnostic is
needed.

---

## Completion Law

A lowering is complete only when its full semantic language is represented,
validated, measured, and wired through the backend. Do not move upward to a
higher lowering while the lower layer still has known semantic gaps.
