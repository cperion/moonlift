# Native Template Hard-Yank Plan

This is the implementation plan for replacing the legacy residual/exact-bank
backend with the native template copy-patch compiler described in
`docs/RESIDUAL_NATIVE_ARCHITECTURE.md`.

This is not a minimal refactor. Correctness and architectural coherence are the
constraints. Current ASDL, code, tests, public APIs, helper modules, and build
scripts may all be changed or deleted. Do not preserve old names through
wrappers, adapters, shims, or compatibility paths.

## Doctrine

- Hard yank old architecture. Delete it; do not wrap it.
- ASDL first. Add the native template vocabulary before implementation logic.
- Concrete ASDL leaf methods own behavior.
- No `kind`, class dispatch, handler maps, side tables, option bags, context
  bags, or nil protocols.
- No residual concept.
- No coverage tracking.
- No exact embedded stencil archive as the main bank.
- No caps as semantics.
- Tests may be red while the tower is being replaced.
- Remove old tests that assert old architecture. Add tests that assert the new
  ASDL and method contracts.

## Target Module Shape

New modules:

```text
lua/lalin/schema/native.lua
lua/lalin/native.lua
lua/lalin/native_algebra.lua
lua/lalin/native_saturation.lua
lua/lalin/native_template.lua
lua/lalin/native_copy.lua
lua/lalin/native_bank.lua
lua/lalin/native_emit.lua
tools/gen_lalin_native_bank.lua
```

Legacy modules to delete or empty during the cut:

```text
lua/lalin/schema/residual.lua
lua/lalin/residual_native.lua
lua/lalin/residual_mc.lua
lua/lalin/residual_mc_intern_set.lua
tools/gen_lalin_mc_bank.lua
```

Do not keep files as compatibility facades. If a filename must remain
temporarily because the build includes it, make the build fail loudly until the
caller is moved, then delete the file.

## Target ASDL Vocabulary

Add `LalinNative` schema. It should contain the complete native compiler
vocabulary.

### Requests And Results

```text
NativeCompileRequest
NativeCompileResult
NativeTarget
NativeRuntime
NativeRuntimeSymbol
NativeBuildRequest
NativeBankBuildResult
```

`NativeCompileResult` is successful native compilation. Missing implementation
is not a result leaf.

### Algebra

```text
NativeAlgebraForm
NativeProducer
NativeAccess
NativeBody
NativeConsumer
NativeSchedule
NativeProofRequirement
NativeProof
```

Concrete leaves:

```text
NativeProducerRange1D
NativeProducerRangeND
NativeProducerTiledND
NativeProducerWindowND
NativeProducerPullStream

NativeAccessContiguous
NativeAccessAffine
NativeAccessViewDescriptor
NativeAccessSliceDescriptor
NativeAccessByteSpanDescriptor
NativeAccessFieldProjection
NativeAccessSoAComponent
NativeAccessIndexed

NativeBodyInput
NativeBodyConst
NativeBodyUnary
NativeBodyBinary
NativeBodyCompare
NativeBodySelect
NativeBodyCast
NativeBodyPredicate
NativeBodyWindowInput
NativeBodyTuple

NativeConsumerStore
NativeConsumerReduce
NativeConsumerScan
NativeConsumerScatter
NativeConsumerScatterReduce
NativeConsumerPartition
NativeConsumerFind
NativeConsumerHorizontal

NativeScheduleScalar
NativeScheduleVector
NativeScheduleUnrolled
NativeScheduleTiled
```

### Saturation

```text
NativeSaturationRequest
NativeSaturation
NativePrimitiveBasis
NativeFusionProof
NativeFusedForm
NativeSupertemplateSelection
```

No `Uncovered`, no `NeedsResidual`, no implementation TODO leaf.

### Templates

```text
NativeTemplateFamily
NativeTemplateAxis
NativeTemplate
NativeSupertemplate
NativeTemplateBank
NativeTemplateBankRequest
NativeTemplateBankBuildPolicy
NativeTemplateMetadata
```

### Graph And Copy Plan

```text
NativeTemplateGraph
NativeTemplateNode
NativeControlEdge
NativeValueEdge
NativeCopyPlan
NativeCodeLayout
NativePatchBinding
NativeExecutable
```

Concrete control edges:

```text
NativeFallthroughEdge
NativeConditionalBranchEdge
NativeLoopBackedgeEdge
NativeExitEdge
NativeContinuationEdge
NativeRuntimeCallReturnEdge
```

Concrete value edges:

```text
NativeRegisterValueEdge
NativeStackSlotValueEdge
NativeRuntimeParamEdge
NativePatchCoordinateEdge
NativeAccumulatorValueEdge
```

### Patching

```text
NativePatchCoordinate
NativePatchHole
NativeRelocation
NativeRegisterProtocol
NativeCallProtocol
```

Patch holes:

```text
NativePatchImm32
NativePatchImm64
NativePatchPtr
NativePatchRel32
NativePatchBranchTarget
NativePatchFieldOffset
NativePatchComponentIndex
NativePatchStride
NativePatchFrameOffset
```

## Required Method Tower

### Code To Native Algebra

Install methods on existing Code/Kernel/LuaJIT ASDL leaves:

```text
CodeModule:to_native_module(input)
CodeFunc:to_native_algebra(input)
CodeInstOp*:append_native_algebra(input)
CodeTermOp*:append_native_control(input)
KernelProof*:to_native_proof(input)
StencilDescriptor:to_native_algebra(input)
StencilProducerShape*:to_native_producer(input)
StencilAccessLayout*:to_native_access(input)
StencilPointExpr*:to_native_body(input)
StencilSink*:to_native_consumer(input)
StencilSchedule*:to_native_schedule(input)
```

No free lowering helpers that branch on classes.

### Saturation

Install methods on native ASDL leaves:

```text
NativeAlgebraForm:saturate_native(input)
NativeProducer*:saturate_native_producer(input)
NativeAccess*:compose_native_access(input)
NativeBody*:fuse_native_body(input)
NativeConsumer*:fuse_native_consumer(input)
NativeSchedule*:select_native_schedule(input)
```

All generated fused forms must come from a leaf method and a typed proof.

### Template Selection

```text
NativeFusedForm:select_native_template_graph(input)
NativeBody*:select_native_template_node(input)
NativeConsumer*:select_native_consumer_template(input)
NativeProducer*:select_native_control_templates(input)
NativeAccess*:select_native_address_template(input)
NativeSchedule*:select_native_schedule_template(input)
```

If a method is missing, the compiler errors. Do not return "uncovered".

### Copy Planning

```text
NativeTemplateGraph:select_native_copy_plan(input)
NativeControlEdge*:append_native_patches(input)
NativeValueEdge*:append_native_protocol(input)
NativeTemplateNode*:append_native_layout(input)
NativeCopyPlan:install_native(input)
NativePatchHole*:apply_native_patch(input)
NativePatchCoordinate*:native_patch_value(input)
```

## Hard-Yank Order

### 1. Add Native Schema

Create `lua/lalin/schema/native.lua`.

Add it to `schema/init.lua`.

Do not modify `schema/residual.lua` except to remove it once callers are gone.
Do not keep residual aliases.

Add schema tests:

```text
tests/schema/test_schema_native.lua
```

Assertions:

- native ASDL module loads;
- no `any`, `table`, `map`;
- basic algebra values construct;
- basic graph/copy/patch values construct;
- missing methods are absent unless explicitly installed.

### 2. Add Native Method Modules

Create empty but real method modules:

```text
native_algebra.lua
native_saturation.lua
native_template.lua
native_copy.lua
native_bank.lua
```

Each module binds to a schema context and installs methods directly on ASDL
classes.

Do not create a dispatcher facade.

### 3. Remove Residual Schema From Active Design

Delete or stop loading `lua/lalin/schema/residual.lua`.

Then fix compile errors by moving required values into `schema/native.lua`.
Do not alias old `Residual*` names to new `Native*` names.

Remove tests that assert residual schema:

```text
tests/schema/test_schema_residual.lua
```

Replace with native schema tests.

### 4. Yank Exact MC Bank Generator

Delete:

```text
tools/gen_lalin_mc_bank.lua
lua/lalin/residual_mc_intern_set.lua
```

Add:

```text
tools/gen_lalin_native_bank.lua
lua/lalin/native_bank.lua
```

The new generator consumes `NativeTemplateBankRequest` and emits
`NativeTemplateBank`. It does not emit exact final function bytes.

Remove tests:

```text
tests/code_ir/test_lalin_mc_bank_generator.lua
tests/code_ir/test_residual_mc_intern_set.lua
```

Add tests:

```text
tests/native/test_native_bank_schema.lua
tests/native/test_native_bank_build_smoke.lua
```

### 5. Yank Residual Runtime

Delete:

```text
lua/lalin/residual_native.lua
lua/lalin/residual_mc.lua
```

Add:

```text
lua/lalin/native_copy.lua
lua/lalin/native_template.lua
lua/lalin/native.lua
```

Native runtime installs `NativeCopyPlan`, not residual functions.

### 6. Move LuaJIT Backend Callers

Update:

```text
lua/lalin/luajit_backend.lua
lua/lalin/luajit_emit.lua
lua/lalin/init.lua
```

Old:

```text
build_mc_bank
embedded_mc_bank_for
realize_mc_artifacts
ResidualLuaJITModuleRequest
ResidualFunctionPlan
```

New:

```text
NativeTemplateBankRequest:build_native_bank()
NativeCompileRequest:compile_native()
NativeCopyPlan:install_native()
NativeExecutable
```

Do not keep old API names as wrappers.

### 7. Rebuild Template Authoring

Templates may initially be authored in C, but C is only bank-build source.

Implement:

```text
NativeTemplate:emit_template_source()
NativeTemplate:compile_template()
NativeRelocation*:to_native_patch_hole()
```

Raw compiler data must be projected into ASDL before use.

### 8. Implement Control-Flow Patching

Add real control holes:

```text
NativePatchBranchTarget
NativePatchLoopBackedge
NativePatchContinuationTarget
```

Implement leaf methods:

```text
NativeConditionalBranchEdge:append_native_patches(input)
NativeLoopBackedgeEdge:append_native_patches(input)
NativeFallthroughEdge:append_native_patches(input)
```

Fallthrough edges should be elided by layout when possible.

### 9. Implement Register Protocol

Add tests that prove pass-through values do not multiply families.

Required tests:

- binary expression with unused live value;
- branch preserving accumulator;
- horizontal consumer sharing producer index;
- runtime param passed through multiple nodes.

### 10. Replace Stencil Artifact Tests

Remove tests whose purpose is exact MC bank behavior.

Keep or rewrite tests that verify semantic output, but route them through native
template compilation.

New test groups:

```text
tests/native/test_native_map_store.lua
tests/native/test_native_reduce.lua
tests/native/test_native_scan.lua
tests/native/test_native_branch_patch.lua
tests/native/test_native_loop_backedge_patch.lua
tests/native/test_native_horizontal_fusion.lua
tests/native/test_native_field_soa.lua
tests/native/test_native_window.lua
tests/native/test_native_missing_method_loud.lua
```

## Delete List

Delete these concepts from code and tests:

```text
ResidualFunctionPlan
ResidualModulePlan
ResidualLuaJITModuleRequest
ResidualStorageRequirement
ResidualLoweringTarget
CResidual*
StencilArtifactStorage
StencilStoredExactMC
StencilStoredPatchTemplateMC
StencilRequiresCompile
MaterializedExactStencil
MaterializedPatchedStencil under Residual namespace
StencilPatchTemplateBank under Residual namespace
StencilArtifactBatch as native bank input
artifact_triplet
artifact_batch_triplet
exact embedded MC shards
lalin_embedded_mc_bank_shards
lalin_embedded_mc_bank_shard_count
```

If a concept is still needed, recreate it under native names with corrected
semantics. Do not move old code and rename it mechanically.

## New Test Philosophy

Tests should assert architecture, not compatibility:

- ASDL constructors consume ASDL values.
- Leaf methods exist on concrete leaves.
- Missing native method errors loudly.
- Template bank contains template families, not exact final functions.
- Control flow is patched through graph edges.
- Constants/offsets/targets are holes, not family axes.
- Runtime params stay ABI params.
- Saturation is generated from semantic rules, not cross-products.

Remove tests that assert:

- old residual names;
- exact embedded bank byte arrays;
- fallback behavior;
- compatibility wrappers;
- arbitrary caps as expected output.

## Completion Criteria

The hard-yank is complete when:

1. No `Residual*` compiler architecture remains active.
2. No native compiler path returns uncovered/fallback/residual results.
3. No exact embedded MC bank is used as the main bank.
4. Native schema owns algebra, saturation, templates, graph, copy plan, patching,
   and executable values.
5. Native behavior is installed as ASDL leaf methods.
6. Missing implementation is loud.
7. Tests assert the new native template architecture directly.
