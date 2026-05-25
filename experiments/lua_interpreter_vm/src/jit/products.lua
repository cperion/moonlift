-- Moonlift Lua VM JIT — product tree.
--
-- This module is intentionally only product definitions.  It does not plan,
-- materialize, execute, benchmark, or pretend to be a JIT.  The JIT control
-- plane must be built as explicit Moonlift data products and machines on top
-- of this surface.

local host = require("moonlift.host")

-- Ensure the VM semantic products are registered before JIT products refer to
-- Proto/Value/Frame/LuaThread by name.
require("experiments.lua_interpreter_vm.src.products")

-- Semantic address/range: points at immutable Proto.code; never mutates it.
local SemanticAddr = host.struct [[struct SemanticAddr proto: ptr(Proto); pc: index; frame: u32 end]]
local SemanticRange = host.struct [[struct SemanticRange proto: ptr(Proto); start_pc: index; end_pc: index; shape: u8 end]]

-- Effects/projections: compile-time/control-plane obligations.
local Effect = host.struct [[struct Effect flags: u64 end]]
local BoundaryRequirement = host.struct [[struct BoundaryRequirement flags: u64 end]]
local ProjectionRequirement = host.struct [[struct ProjectionRequirement flags: u64 end]]

local Fact = host.struct [[struct Fact kind: u16; value: u32; aux0: u64; aux1: u64 end]]
local DependencyKey = host.struct [[struct DependencyKey kind: u16; ptr0: ptr(u8); aux0: u64; generation: u64 end]]

local TypedValue = host.struct [[struct TypedValue id: u32; kind: u8; type_tag: u32; payload0: u64; payload1: u64; op: u16; lhs: u32; rhs: u32 end]]

local VirtualState = host.struct [[struct VirtualState addr: SemanticAddr; frame: u32; base: index; top: index; slot_values: ptr(u32); slot_count: index; values: ptr(TypedValue); value_count: index; facts: ptr(Fact); fact_count: index; deps: ptr(DependencyKey); dep_count: index end]]

local ProjectedSlot = host.struct [[struct ProjectedSlot slot: index; value_id: u32; required_tag: u32; flags: u32 end]]
local Projection = host.struct [[struct Projection id: u32; kind: u8; addr: SemanticAddr; frame: u32; base: index; top: index; slots: ptr(ProjectedSlot); slot_count: index; roots: ptr(u32); root_count: index; flags: u64 end]]

-- Semantic operation language: proof/selection surface, not a backend IR.
local StateOp = host.struct [[struct StateOp kind: u16; op: u16; a: u32; b: u32; c: u32; aux0: u64; aux1: u64; effect: Effect end]]
local StateProgram = host.struct [[struct StateProgram range: SemanticRange; ops: ptr(StateOp); op_count: index; initial_state: ptr(VirtualState); final_state: ptr(VirtualState) end]]

-- Trace products: tracing is a StencilPlan frontend, not a second backend.
local Guard = host.struct [[struct Guard kind: u16; value_id: u32; dep_index: u32; projection_id: u32; flags: u32; aux0: u64; aux1: u64 end]]
local TraceAnchor = host.struct [[struct TraceAnchor addr: SemanticAddr; kind: u8; status: u8; counter: u32; blacklist: u32; generation: u64 end]]
local TraceRecord = host.struct [[struct TraceRecord anchor: TraceAnchor; ops: ptr(StateOp); op_count: index; guards: ptr(Guard); guard_count: index; snapshots: ptr(Projection); snapshot_count: index; deps: ptr(DependencyKey); dep_count: index; flags: u32 end]]

-- Stencil library products.
local StencilHole = host.struct [[struct StencilHole offset: index; kind: u8; width: u8; aux: u32 end]]
local StencilReloc = host.struct [[struct StencilReloc offset: index; kind: u8; target: u32; width: u8 end]]
local StencilPayload = host.struct [[struct StencilPayload offset: index; kind: u8; size: index; aux0: u64; aux1: u64 end]]

local CodeStencil = host.struct [[struct CodeStencil kind: u8; op: u16; effect: Effect; bytes: ptr(u8); size: index; holes: ptr(StencilHole); hole_count: index; relocs: ptr(StencilReloc); reloc_count: index; payloads: ptr(StencilPayload); payload_count: index; abi: u8; clobbers: u64 end]]
local StencilLibrary = host.struct [[struct StencilLibrary stencils: ptr(CodeStencil); stencil_count: index; generation: u64 end]]

local StencilConfig = host.struct [[struct StencilConfig kind: u16; op: u16; value_type: u16; lhs_loc: u8; rhs_loc: u8; out_loc: u8; passthrough_mask: u64; pattern_id: u32 end]]
local StencilPattern = host.struct [[struct StencilPattern id: u32; ops: ptr(u16); op_count: index; required_effects: u64; forbidden_effects: u64; stencil: ptr(CodeStencil); score: u32; flags: u32 end]]
local StencilPatternLibrary = host.struct [[struct StencilPatternLibrary patterns: ptr(StencilPattern); pattern_count: index; generation: u64 end]]
local StencilNode = host.struct [[struct StencilNode stencil: ptr(CodeStencil); config: StencilConfig; next: u32; alt: u32; label: u32; boundary_id: u32; projection_id: u32 end]]
local TraceStencilMatch = host.struct [[struct TraceStencilMatch start: index; covered_ops: index; stencil: ptr(CodeStencil); config: StencilConfig; score: u32; flags: u32 end]]

-- Offline/library-construction products. Runtime may consume promoted results,
-- but it must not synthesize new stencil shapes on the hot path.
local TraceMotif = host.struct [[struct TraceMotif id: u32; ops: ptr(u16); op_count: index; hits: u64; guard_count: u32; exit_count: u32; score: u32; flags: u32 end]]
local PromotionEvidence = host.struct [[struct PromotionEvidence motif_id: u32; hits: u64; total_ops: u64; guard_successes: u64; exits: u64; byte_savings: i64; ns_savings: i64; confidence: u32 end]]
local StencilReplacement = host.struct [[struct StencilReplacement kind: u8; stencil: ptr(CodeStencil); nodes: ptr(StencilNode); node_count: index; flags: u32 end]]
local StencilEquivalence = host.struct [[struct StencilEquivalence contract_id: u32; input_hash: u64; output_hash: u64; effect_flags: u64; projection_flags: u64 end]]
local RewriteStencil = host.struct [[struct RewriteStencil id: u32; kind: u8; pattern: ptr(StencilPattern); required_facts: ptr(Fact); required_fact_count: index; forbidden_effects: u64; replacement: StencilReplacement; equivalence: StencilEquivalence; flags: u32 end]]
local StencilPromotion = host.struct [[struct StencilPromotion evidence: PromotionEvidence; pattern: ptr(StencilPattern); promoted: ptr(CodeStencil); status: u8; flags: u32 end]]

-- Bounded-arity closure/refinement products.  These describe offline stencil
-- saturation and runtime unit refinement without adding compiler tiers.
local StencilSummary = host.struct [[struct StencilSummary covered_ops: index; closure_depth: u8; max_arity: u8; effect_flags: u64; projection_flags: u64; dep_count: index; exit_count: u32; hole_count: index; code_size: index; cost_score: i64 end]]
local StencilClosurePolicy = host.struct [[struct StencilClosurePolicy max_arity: u8; max_depth: u8; max_covered_ops: index; max_code_size: index; max_holes: index; max_exits: u32; max_variants: u32 end]]
local StencilClosureRound = host.struct [[struct StencilClosureRound depth: u8; input_count: index; candidate_count: index; promoted_count: index; generation: u64 end]]
local StencilPlanMetrics = host.struct [[struct StencilPlanMetrics node_count: index; covered_ops: index; max_depth: u8; granularity_score: u32; estimated_size: index end]]
local StencilPlanRefinement = host.struct [[struct StencilPlanRefinement source_generation: u64; result_generation: u64; from_depth: u8; to_depth: u8; old_unit: ptr(u8); new_unit: ptr(u8); reason: u32; flags: u32 end]]

local CodeFixup = host.struct [[struct CodeFixup site_offset: index; target_label: u32; kind: u8; aux: u32 end]]
local StencilPlan = host.struct [[struct StencilPlan nodes: ptr(StencilNode); node_count: index; fixups: ptr(CodeFixup); fixup_count: index; projections: ptr(Projection); projection_count: index; estimated_size: index end]]

-- Executable image products.  These are sidecar state beside immutable Proto.code.
local CodeSlab = host.struct [[struct CodeSlab rw: ptr(u8); rx: ptr(u8); size: index; used: index; generation: u64 end]]
local EntryCell = host.struct [[struct EntryCell addr: SemanticAddr; target: ptr(u8); fallback: ptr(u8); unit: ptr(u8); counter: u32; status: u8; generation: u64 end]]
local EdgeCell = host.struct [[struct EdgeCell target: ptr(u8); fallback: ptr(u8); target_unit: ptr(u8); kind: u8; status: u8; pad0: u16; generation: u64 end]]
local ExecutableUnit = host.struct [[struct ExecutableUnit range: SemanticRange; entry: ptr(u8); code: ptr(u8); code_size: index; plan_hash: u64; deps: ptr(DependencyKey); dep_count: index; projections: ptr(Projection); projection_count: index; generation: u64 end]]
local ExecImage = host.struct [[struct ExecImage proto: ptr(Proto); generation: u64; entries: ptr(EntryCell); entry_count: index; units: ptr(ptr(ExecutableUnit)); unit_count: index; stencils: ptr(StencilLibrary); code: ptr(CodeSlab) end]]

-- Host-visible outcome of compiled code, isomorphic to vm_loop continuations.
local NativeJitOutcome = host.struct [[struct NativeJitOutcome status: u32; exit_id: u32; pc: u64; payload0: u64; payload1: u64 end]]

return {
    SemanticAddr = SemanticAddr,
    SemanticRange = SemanticRange,
    Effect = Effect,
    BoundaryRequirement = BoundaryRequirement,
    ProjectionRequirement = ProjectionRequirement,
    Fact = Fact,
    DependencyKey = DependencyKey,
    TypedValue = TypedValue,
    VirtualState = VirtualState,
    ProjectedSlot = ProjectedSlot,
    Projection = Projection,
    StateOp = StateOp,
    StateProgram = StateProgram,
    Guard = Guard,
    TraceAnchor = TraceAnchor,
    TraceRecord = TraceRecord,
    StencilHole = StencilHole,
    StencilReloc = StencilReloc,
    StencilPayload = StencilPayload,
    CodeStencil = CodeStencil,
    StencilLibrary = StencilLibrary,
    StencilConfig = StencilConfig,
    StencilPattern = StencilPattern,
    StencilPatternLibrary = StencilPatternLibrary,
    StencilNode = StencilNode,
    TraceStencilMatch = TraceStencilMatch,
    TraceMotif = TraceMotif,
    PromotionEvidence = PromotionEvidence,
    StencilReplacement = StencilReplacement,
    StencilEquivalence = StencilEquivalence,
    RewriteStencil = RewriteStencil,
    StencilPromotion = StencilPromotion,
    StencilSummary = StencilSummary,
    StencilClosurePolicy = StencilClosurePolicy,
    StencilClosureRound = StencilClosureRound,
    StencilPlanMetrics = StencilPlanMetrics,
    StencilPlanRefinement = StencilPlanRefinement,
    CodeFixup = CodeFixup,
    StencilPlan = StencilPlan,
    CodeSlab = CodeSlab,
    EntryCell = EntryCell,
    EdgeCell = EdgeCell,
    ExecutableUnit = ExecutableUnit,
    ExecImage = ExecImage,
    NativeJitOutcome = NativeJitOutcome,
}
