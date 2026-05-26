# Lua Stencil Harness Design

## Status

This document specifies the Lua harness used to build the Lua VM JIT stencil library.

The harness is not the runtime JIT. It is the offline and semi-offline machinery that:

1. gathers Lua programs and benchmark corpora;
2. compiles Lua source into the Moonlift Lua VM bytecode;
3. profiles static bytecode windows and dynamic execution traces;
4. builds the `L0` stencil seed set;
5. accepts human-selected useful `L0` seed stencils;
6. generates `L1`, `L2`, `L3`, and `L4` stencil layers automatically;
7. verifies, benchmarks, ranks, and exports the runtime stencil library;
8. produces reports showing corpus coverage and speed impact.

Scope:

- Lua VM JIT only.
- Lua harness for corpus profiling and stencil-library generation.
- Are We Fast Yet coverage as the first mandatory benchmark corpus.
- LuaRocks / GitHub / project-corpus support as optional larger corpora.
- Offline generation through Moonlift candidate kernels and Cranelift object-code mining.
- Runtime stencil-library export.

Out of scope:

- Copy-and-patch as a general Moonlift compiler backend.
- Runtime generation of new stencil kinds.
- Runtime Cranelift usage.
- Whole-program source-code redistribution.
- A general optimizing compiler independent of the stencil library.

Doctrine:

> The harness turns real Lua programs into an empirical stencil library.
> `L0` contains primitive opcode/fact stencils plus deliberately seeded useful shapes.
> Layers `L1` through `L4` are generated automatically by bounded-arity closure.
> Measurement decides the winners.

---

## 1. Place in the whole JIT system

The full Lua VM JIT has two major sides.

```text
runtime side:
  bytecode / trace facts
      -> StencilPlan
      -> copy / stamp / fixup / publish / link
      -> ExecutableUnit

offline harness side:
  Lua corpus
      -> bytecode + profile + trace facts
      -> seed selection
      -> layered stencil generation
      -> verified runtime StencilLibrary
```

The runtime sees only the final exported library and selector tables.

The harness owns:

```text
CorpusDB
ProfileDB
L0SeedManifest
LayerBuildPlan
CandidateManifest
VerificationReport
BenchmarkReport
RuntimeStencilLibrary
RuntimeSelectorTable
```

The runtime owns:

```text
StencilLibraryView
StencilSelector
StencilPlan
ExecutableUnit
EntryCell
EdgeCell
```

The harness must never become a dependency of the hot runtime path.

---

## 2. Layer model

The library is built in layers.

```text
L0 = primitive opcode/fact stencils + manually seeded useful stencil families
L1 = arity <= 4 closure over L0
L2 = arity <= 4 closure over L0..L1
L3 = arity <= 4 closure over L0..L2
L4 = arity <= 4 closure over L0..L3
L5 = optional trace-region experiment over hot trace motifs
```

Default build targets:

```text
dev build:        L0 + L1
normal research:  L0 + L1 + L2
speed-max:        L0 + L1 + L2 + L3 + L4
trace lab:        L0 + L1 + L2 + L3 + L4 + selected L5
```

The harness documented here is responsible for automatic generation through `L4`.
`L5` is described only as an optional extension point.

### 2.1 Why L0 may contain manual seeds

`L0` is not limited to one primitive stencil per opcode.

`L0` contains:

1. mandatory primitive opcode/fact stencils;
2. primitive guard/projection/boundary/edge stencils;
3. manually seeded stencils that are obviously useful;
4. corpus-derived seed stencils observed in Are We Fast Yet and other profiles;
5. rewrite-only stencils such as DCE, redundant move, redundant guard, and fallthrough elimination.

A manually seeded stencil is not trusted because it was manually named.
It must still pass the same generation, verification, and measurement pipeline.

Examples of valid `L0` seeds:

```text
ADD_i64_known_slot_slot_to_slot
ADD_i64_guarded_slot_slot_to_slot
LOADK_MOVE_redirect
COMPARE_BRANCH_i64
TEST_JMP_truthy
RETURN1_from_slot
PROJECT_slots_3
GETTABUP_global_call0_seed
FORLOOP_i64_seed
GETARRAY_i64_seed
```

These seeds let the system cover important corpus patterns early, especially Are We Fast Yet, without waiting for several closure rounds to discover them indirectly.

---

## 3. Corpus strategy

The harness has a corpus pipeline.

```text
CorpusSource
  -> CorpusFile
  -> NormalizedLuaUnit
  -> LuaProtoBundle
  -> StaticBytecodeProfile
  -> DynamicTraceProfile
  -> CorpusProfileDB
```

### 3.1 Mandatory corpus: Are We Fast Yet

The first target corpus is Are We Fast Yet.

Purpose:

- force coverage of benchmark-style hot loops;
- cover object dispatch / method calls / algorithmic kernels;
- provide stable repeatable speed regressions;
- ensure that early stencil layers are not optimized only for tiny synthetic tests.

Harness policy:

```text
AWFY coverage is mandatory for L0 seed review.
A stencil seed is preferred if it covers repeated AWFY bytecode windows.
A generated layer is not accepted unless AWFY benchmark profiles still run.
```

The harness should treat AWFY as both:

1. a static bytecode corpus;
2. a dynamic execution corpus.

### 3.2 Additional corpora

The harness supports optional sources:

```text
LuaRocks packages
GitHub Lua repositories
OpenResty-style code
Neovim plugin Lua
LÖVE/game Lua
Moonlift internal Lua tests
handwritten microbenchmarks
Lua VM conformance tests
```

Corpus collection must store license and origin metadata. The preferred persisted artifact is a profile, not copied source code.

### 3.3 Corpus partitions

The corpus is divided into partitions.

```text
struct CorpusPartition
    id: CorpusPartitionId
    name: StringId
    kind: CorpusPartitionKind
    source_count: u32
    profile_weight: f64
    must_pass: bool
    benchmark_weight: f64
end
```

```text
enum CorpusPartitionKind
    AWFY
    LUAROCKS
    GITHUB_LUA
    OPENRESTY
    NEOVIM
    GAME_LUA
    INTERNAL_TESTS
    MICROBENCH
    CONFORMANCE
end
```

A partition can be weighted differently for seeding and for validation.

```text
AWFY:
  seed_weight = high
  benchmark_weight = high
  must_pass = true

Conformance:
  seed_weight = low
  benchmark_weight = medium
  must_pass = true

LuaRocks/GitHub:
  seed_weight = medium
  benchmark_weight = low unless runnable
  must_pass = false unless selected as fixture
```

---

## 4. Harness modules

The harness is organized as a set of Lua and Moonlift-facing modules.

```text
tools/jit_harness/
  harness.lua
  corpus.lua
  awfy.lua
  compile.lua
  profile_static.lua
  profile_dynamic.lua
  fact_trace.lua
  seed_l0.lua
  layer_closure.lua
  candidate_emit.lua
  candidate_compile.lua
  object_mine.lua
  verify.lua
  bench.lua
  select.lua
  export_runtime.lua
  report.lua
```

### 4.1 `harness.lua`

Top-level command dispatcher.

Lua signature:

```lua
function main(argv: {string}) -> integer
```

Commands:

```text
profile-awfy
profile-corpus
seed-l0
build-layer
iterate-layers
verify-layer
bench-layer
export-runtime
report
clean
```

### 4.2 `corpus.lua`

Loads and normalizes corpus sources.

Lua signatures:

```lua
function load_corpus_config(path: string) -> CorpusConfig
function enumerate_corpus(config: CorpusConfig) -> {CorpusFile}
function normalize_lua_file(file: CorpusFile) -> NormalizedLuaUnit | CorpusReject
function write_corpus_db(db: CorpusDB, path: string) -> boolean
function read_corpus_db(path: string) -> CorpusDB
```

### 4.3 `awfy.lua`

Are We Fast Yet integration.

Lua signatures:

```lua
function discover_awfy(root: string) -> AWFYCorpus
function list_awfy_benchmarks(corpus: AWFYCorpus) -> {AWFYBenchmark}
function compile_awfy_benchmark(bench: AWFYBenchmark, compiler: CompilerHandle) -> LuaProtoBundle | CompileReject
function run_awfy_benchmark(bench: AWFYBenchmark, runner: VMRunner, config: RunConfig) -> DynamicRunResult
function profile_awfy(root: string, output: string, config: HarnessConfig) -> HarnessResult
```

### 4.4 `compile.lua`

Compiles Lua source to Moonlift Lua VM bytecode.

Lua signatures:

```lua
function compile_lua_unit(unit: NormalizedLuaUnit, config: CompileConfig) -> LuaProtoBundle | CompileReject
function compile_file(path: string, config: CompileConfig) -> LuaProtoBundle | CompileReject
function dump_proto_bundle(bundle: LuaProtoBundle, path: string) -> boolean
function read_proto_bundle(path: string) -> LuaProtoBundle
```

### 4.5 `profile_static.lua`

Profiles bytecode without executing it.

Lua signatures:

```lua
function profile_proto_static(bundle: LuaProtoBundle, config: StaticProfileConfig) -> StaticBytecodeProfile
function profile_proto(proto: LuaProto, config: StaticProfileConfig) -> ProtoStaticProfile
function count_opcode_windows(proto: LuaProto, max_n: integer) -> OpcodeWindowTable
function derive_operand_shapes(proto: LuaProto) -> OperandShapeTable
function derive_control_shapes(proto: LuaProto) -> ControlShapeTable
function derive_static_liveness(proto: LuaProto) -> StaticLivenessTable
```

### 4.6 `profile_dynamic.lua`

Runs code through the instrumented VM and records dynamic traces.

Lua signatures:

```lua
function run_dynamic_profile(bundle: LuaProtoBundle, config: DynamicProfileConfig) -> DynamicTraceProfile
function run_entrypoint(entry: LuaEntrypoint, config: DynamicProfileConfig) -> DynamicRunResult
function merge_dynamic_profiles(profiles: {DynamicTraceProfile}) -> DynamicTraceProfile
```

### 4.7 `fact_trace.lua`

Canonicalizes runtime observations into facts.

Lua signatures:

```lua
function observe_value_fact(value: TValue) -> ValueFact
function observe_table_fact(table: LuaTable) -> TableFact
function observe_call_fact(callee: TValue) -> CallFact
function observe_window_fact(trace: TraceWindow) -> WindowFactKey
function canonicalize_fact_set(facts: {Fact}) -> CanonicalFactSet
function encode_fact_key(facts: CanonicalFactSet) -> FactKey
```

### 4.8 `seed_l0.lua`

Builds the `L0` seed manifest.

Lua signatures:

```lua
function load_manual_l0_seeds(path: string) -> {L0SeedSpec}
function derive_corpus_l0_seeds(profile: CorpusProfileDB, config: SeedConfig) -> {L0SeedSpec}
function merge_l0_seeds(manual: {L0SeedSpec}, derived: {L0SeedSpec}) -> L0SeedManifest
function validate_l0_seed_manifest(manifest: L0SeedManifest, lib: PrimitiveSpecLibrary) -> SeedValidationReport
function write_l0_seed_manifest(manifest: L0SeedManifest, path: string) -> boolean
```

### 4.9 `layer_closure.lua`

Generates `L1..L4` candidates by bounded-arity closure.

Lua signatures:

```lua
function build_layer(input: LayerInput, config: LayerBuildConfig) -> LayerBuildResult
function enumerate_candidate_sequences(input: LayerInput, config: LayerBuildConfig) -> CandidateSequenceStream
function validate_candidate_sequence(seq: CandidateSequence, config: LayerBuildConfig) -> SequenceValidity
function compose_sequence_contract(seq: CandidateSequence) -> StencilContract | ContractFailure
function assign_candidate_key(seq: CandidateSequence, contract: StencilContract) -> CandidateKey
```

### 4.10 `candidate_emit.lua`

Emits low-level Moonlift kernels from candidate descriptions.

Lua signatures:

```lua
function emit_candidate_kernel(candidate: StencilCandidate, config: EmitConfig) -> EmittedKernel | EmitFailure
function emit_code_stencil_kernel(candidate: StencilCandidate, config: EmitConfig) -> EmittedKernel | EmitFailure
function emit_rewrite_stencil_spec(candidate: StencilCandidate, config: EmitConfig) -> RewriteStencilSpec | EmitFailure
function write_kernel_source(kernel: EmittedKernel, output_dir: string) -> string
```

### 4.11 `candidate_compile.lua`

Compiles candidate kernels through the current Moonlift/Cranelift path.

Lua signatures:

```lua
function compile_kernel(kernel: EmittedKernel, config: CandidateCompileConfig) -> CandidateObject | CompileFailure
function compile_kernel_batch(kernels: {EmittedKernel}, config: CandidateCompileConfig) -> {CandidateCompileResult}
function dump_candidate_object(obj: CandidateObject, output_dir: string) -> ObjectDump
```

### 4.12 `object_mine.lua`

Mines machine code bytes, holes, relocations, body ranges, and clobbers.

Lua signatures:

```lua
function mine_object(obj: CandidateObject, spec: StencilCandidate, config: MineConfig) -> MinedCandidate | MineFailure
function find_body_range(obj: CandidateObject, symbol: string, config: MineConfig) -> BodyRange | MineFailure
function find_holes(bytes: ByteString, markers: {HoleMarker}) -> {HoleSite}
function find_relocations(obj: CandidateObject, symbol: string) -> {RelocSite}
function classify_clobbers(obj: CandidateObject, body: BodyRange) -> ClobberSet | MineFailure
function normalize_relocs(relocs: {RelocSite}) -> {NormalizedReloc}
```

### 4.13 `verify.lua`

Verifies mined candidates against semantic contracts.

Lua signatures:

```lua
function verify_candidate(candidate: MinedCandidate, config: VerifyConfig) -> VerificationResult
function verify_contract(candidate: MinedCandidate, contract: StencilContract) -> ContractVerification
function verify_holes(candidate: MinedCandidate) -> HoleVerification
function verify_relocs(candidate: MinedCandidate) -> RelocVerification
function verify_projection(candidate: MinedCandidate) -> ProjectionVerification
function verify_equivalence(candidate: MinedCandidate, expansion: StencilExpansion) -> EquivalenceVerification
```

### 4.14 `bench.lua`

Benchmarks candidates and layers.

Lua signatures:

```lua
function benchmark_candidate(candidate: VerifiedCandidate, config: BenchConfig) -> CandidateBenchResult
function benchmark_layer(layer: StencilLayer, corpus: CorpusProfileDB, config: BenchConfig) -> LayerBenchResult
function run_microbench(candidate: VerifiedCandidate, config: BenchConfig) -> MicroBenchResult
function run_awfy_layer_bench(layer: StencilLayer, config: BenchConfig) -> AWFYBenchResult
function compare_layers(old_layer: StencilLayer, new_layer: StencilLayer, config: BenchConfig) -> LayerComparison
```

### 4.15 `select.lua`

Ranks and selects winners for the runtime library.

Lua signatures:

```lua
function classify_candidate(candidate: VerifiedBenchCandidate, config: SelectConfig) -> CandidateClassification
function select_fastest_by_key(candidates: {VerifiedBenchCandidate}, config: SelectConfig) -> SelectionResult
function build_selector_table(layers: {StencilLayer}, config: SelectorConfig) -> RuntimeSelectorTable
function write_selector_table(table: RuntimeSelectorTable, path: string) -> boolean
```

### 4.16 `export_runtime.lua`

Exports the runtime stencil library.

Lua signatures:

```lua
function export_runtime_library(layers: {StencilLayer}, selector: RuntimeSelectorTable, config: ExportConfig) -> RuntimeStencilLibrary
function write_runtime_library(lib: RuntimeStencilLibrary, output_dir: string) -> ExportResult
function write_c_header(lib: RuntimeStencilLibrary, output_dir: string) -> string
function write_binary_blob(lib: RuntimeStencilLibrary, output_dir: string) -> string
function write_manifest(lib: RuntimeStencilLibrary, output_dir: string) -> string
```

### 4.17 `report.lua`

Produces human reports.

Lua signatures:

```lua
function write_corpus_report(profile: CorpusProfileDB, path: string) -> boolean
function write_l0_seed_report(manifest: L0SeedManifest, path: string) -> boolean
function write_layer_report(layer: StencilLayer, path: string) -> boolean
function write_coverage_report(layers: {StencilLayer}, corpus: CorpusProfileDB, path: string) -> boolean
function write_speed_report(results: LayerBenchResult, path: string) -> boolean
```

---

## 5. Product declarations

The following declarations are written in Moonlift-style pseudocode.
They specify product shape, not final syntax.

### 5.1 Identifiers

```moonlift
alias CorpusId = u64
alias CorpusFileId = u64
alias CorpusPartitionId = u32
alias ProtoId = u64
alias ProtoIndex = u32
alias Pc = u32
alias OpcodeId = u16
alias WindowId = u64
alias FactKey = u128
alias CandidateId = u64
alias StencilId = u64
alias LayerId = u8
alias BenchmarkId = u64
alias RunId = u64
alias StringId = u64
alias Hash64 = u64
alias Hash128 = u128
```

### 5.2 Corpus products

```moonlift
struct CorpusConfig
    root: Path
    partitions: Vec(CorpusPartitionConfig)
    output_dir: Path
    max_files: u64
    include_patterns: Vec(StringId)
    exclude_patterns: Vec(StringId)
    store_source_copy: bool
    store_source_hash: bool
    store_license_metadata: bool
end

struct CorpusPartitionConfig
    name: StringId
    kind: CorpusPartitionKind
    root: Path
    enabled: bool
    must_compile: bool
    must_run: bool
    seed_weight: f64
    bench_weight: f64
end

struct CorpusDB
    id: CorpusId
    created_at_unix_ns: u64
    config_hash: Hash128
    partitions: Vec(CorpusPartition)
    files: Vec(CorpusFile)
    normalized_units: Vec(NormalizedLuaUnit)
    rejects: Vec(CorpusReject)
end

struct CorpusFile
    id: CorpusFileId
    partition: CorpusPartitionId
    path: Path
    relative_path: Path
    sha256: Hash256
    size_bytes: u64
    license: LicenseInfo
    source_origin: SourceOrigin
end

struct NormalizedLuaUnit
    file_id: CorpusFileId
    normalized_id: u64
    lua_version: LuaVersion
    dialect: LuaDialect
    source_hash: Hash256
    normalized_hash: Hash256
    entry_kind: LuaEntrypointKind
    flags: NormalizationFlags
end

struct CorpusReject
    file_id: CorpusFileId
    stage: CorpusStage
    reason: CorpusRejectReason
    detail: StringId
end
```

```moonlift
enum CorpusStage
    DISCOVER
    NORMALIZE
    COMPILE
    STATIC_PROFILE
    DYNAMIC_RUN
    DYNAMIC_PROFILE
end

enum CorpusRejectReason
    IO_ERROR
    UNSUPPORTED_ENCODING
    UNSUPPORTED_LUA_VERSION
    PARSE_ERROR
    COMPILE_ERROR
    MISSING_DEPENDENCY
    DYNAMIC_RUN_FAILED
    TIMEOUT
    LICENSE_BLOCKED
end
```

### 5.3 Lua bytecode products

```moonlift
struct LuaProtoBundle
    bundle_id: u64
    source_unit: CorpusFileId
    root_proto: ProtoId
    protos: Vec(LuaProto)
    constants: Vec(LuaConstant)
    debug_info: ProtoDebugInfo
    compiler_config_hash: Hash128
end

struct LuaProto
    id: ProtoId
    index: ProtoIndex
    parent: Option(ProtoId)
    code: Vec(LuaInstr)
    max_stack: u16
    num_params: u8
    is_vararg: bool
    upvalue_count: u16
    constant_range: RangeU32
    child_proto_range: RangeU32
end

struct LuaInstr
    pc: Pc
    opcode: OpcodeId
    encoding: u32
    format: InstrFormat
    a: u16
    b: u16
    c: u16
    bx: u32
    sbx: i32
    ax: u32
end

enum InstrFormat
    ABC
    ABx
    AsBx
    Ax
    sJ
    EXTRAARG
end
```

### 5.4 Static profile products

```moonlift
struct StaticBytecodeProfile
    corpus_id: CorpusId
    compile_config_hash: Hash128
    max_window: u8
    proto_profiles: Vec(ProtoStaticProfile)
    opcode_counts: CounterTable(OpcodeId)
    window_counts: CounterTable(OpcodeWindowKey)
    operand_shape_counts: CounterTable(OperandShapeKey)
    control_shape_counts: CounterTable(ControlShapeKey)
    liveness_shape_counts: CounterTable(LivenessShapeKey)
end

struct ProtoStaticProfile
    proto: ProtoId
    instr_count: u32
    opcode_counts: CounterTable(OpcodeId)
    windows: Vec(OpcodeWindowObservation)
    loops: Vec(LoopShape)
    branches: Vec(BranchShape)
    calls: Vec(CallSiteShape)
    static_liveness: StaticLivenessTable
end

struct OpcodeWindowKey
    len: u8
    opcodes: FixedVec(OpcodeId, 8)
    formats: FixedVec(InstrFormat, 8)
    operand_shape: OperandShapeKey
    control_shape: ControlShapeKey
    effect_shape: StaticEffectShape
end

struct OpcodeWindowObservation
    key: OpcodeWindowKey
    proto: ProtoId
    start_pc: Pc
    end_pc: Pc
    count_static: u32
end
```

### 5.5 Dynamic profile products

```moonlift
struct DynamicTraceProfile
    corpus_id: CorpusId
    run_config_hash: Hash128
    runs: Vec(DynamicRunResult)
    trace_windows: CounterTable(TraceWindowKey)
    fact_windows: CounterTable(WindowFactKey)
    hot_anchors: Vec(HotAnchorProfile)
    side_exits: Vec(SideExitProfile)
    value_facts: CounterTable(ValueFactKey)
    table_facts: CounterTable(TableFactKey)
    call_facts: CounterTable(CallFactKey)
end

struct DynamicRunResult
    run_id: RunId
    benchmark: BenchmarkId
    partition: CorpusPartitionId
    status: DynamicRunStatus
    elapsed_ns: u64
    instr_executed: u64
    trace_count: u64
    timeout: bool
    error: Option(StringId)
    profile: Option(DynamicTraceProfileSlice)
end

struct TraceWindowKey
    len: u8
    semantic_addrs: FixedVec(SemanticAddr, 8)
    opcodes: FixedVec(OpcodeId, 8)
    branch_mask: u64
    exit_mask: u64
end

struct WindowFactKey
    window: TraceWindowKey
    fact_key: FactKey
    liveness_key: LivenessShapeKey
    projection_key: ProjectionShapeKey
end

struct HotAnchorProfile
    anchor: SemanticAddr
    hit_count: u64
    loop_backedge_count: u64
    call_count: u64
    side_exit_count: u64
    stable_fact_key: FactKey
    dominant_window: Option(TraceWindowKey)
end
```

### 5.6 Fact products

```moonlift
struct CanonicalFactSet
    key: FactKey
    value_facts: Vec(ValueFact)
    table_facts: Vec(TableFact)
    call_facts: Vec(CallFact)
    control_facts: Vec(ControlFact)
    liveness_facts: Vec(LivenessFact)
    dependency_facts: Vec(DependencyFact)
end

enum ValueFact
    UNKNOWN(slot: SlotId)
    IS_NIL(slot: SlotId)
    IS_FALSE(slot: SlotId)
    IS_TRUE(slot: SlotId)
    IS_BOOLEAN(slot: SlotId)
    IS_INTEGER(slot: SlotId)
    IS_FLOAT(slot: SlotId)
    IS_NUMBER(slot: SlotId)
    IS_STRING(slot: SlotId)
    IS_TABLE(slot: SlotId)
    IS_LCLOSURE(slot: SlotId)
    IS_CCLOSURE(slot: SlotId)
    IS_LIGHTUSERDATA(slot: SlotId)
    IS_FULLUSERDATA(slot: SlotId)
    IS_THREAD(slot: SlotId)
    CONST_VALUE(slot: SlotId, const_id: LuaConstId)
    SAME_VALUE(lhs: SlotId, rhs: SlotId)
end

enum TableFact
    TABLE_SHAPE_KNOWN(slot: SlotId, shape: TableShapeId)
    TABLE_METATABLE_ABSENT(slot: SlotId)
    TABLE_ARRAY_HIT(table: SlotId, key: SlotId)
    TABLE_STRING_SLOT_HIT(table: SlotId, key_const: LuaConstId, slot: TableSlotId)
    TABLE_GLOBAL_SLOT_HIT(upvalue: UpvalueId, key_const: LuaConstId, slot: TableSlotId)
end

enum CallFact
    CALLEE_KNOWN_LCLOSURE(slot: SlotId, proto: ProtoId)
    CALLEE_KNOWN_CCLOSURE(slot: SlotId, function_id: NativeFunctionId)
    CALLEE_MONOMORPHIC(slot: SlotId, target: CallTargetId)
    CALL_RETCOUNT_KNOWN(pc: Pc, count: u16)
    CALL_ARGCOUNT_KNOWN(pc: Pc, count: u16)
end

enum ControlFact
    BRANCH_TAKEN(pc: Pc)
    BRANCH_NOT_TAKEN(pc: Pc)
    LOOP_BACKEDGE(pc: Pc)
    FALLTHROUGH(pc: Pc)
    SIDE_EXIT_RARE(pc: Pc)
    SIDE_EXIT_HOT(pc: Pc)
end

enum LivenessFact
    SLOT_LIVE(slot: SlotId)
    SLOT_DEAD(slot: SlotId)
    VALUE_LAST_USE(slot: SlotId)
    RESULT_DEAD(pc: Pc)
    RESULT_RETURNED(pc: Pc)
    RESULT_IMMEDIATE_CONSUMER(pc: Pc, consumer_pc: Pc)
end
```

### 5.7 Seed products

```moonlift
struct L0SeedManifest
    id: Hash128
    created_at_unix_ns: u64
    manual_seed_file: Option(Path)
    corpus_profile_id: Option(Hash128)
    seeds: Vec(L0SeedSpec)
    rejected_seeds: Vec<L0SeedReject>
end

struct L0SeedSpec
    name: StringId
    kind: L0SeedKind
    source: L0SeedSource
    pattern: StencilPattern
    required_facts: CanonicalFactSet
    output_contract: StencilContract
    priority: SeedPriority
    target_partitions: Vec(CorpusPartitionKind)
    awfy_reason: Option(StringId)
    comments: StringId
end

enum L0SeedKind
    PRIMITIVE_OPCODE
    PRIMITIVE_GUARD
    PRIMITIVE_PROJECTION
    PRIMITIVE_BOUNDARY
    PRIMITIVE_EDGE
    MANUAL_COMPOUND
    CORPUS_OBSERVED_COMPOUND
    REWRITE_ONLY
end

enum L0SeedSource
    REQUIRED_VM_SEMANTIC
    MANUAL_DESIGN
    AWFY_OBSERVED
    CORPUS_OBSERVED
    MICROBENCH_OBSERVED
end

enum SeedPriority
    REQUIRED
    HIGH
    MEDIUM
    LOW
    EXPERIMENTAL
end
```

### 5.8 Candidate and layer products

```moonlift
struct LayerInput
    layer_id: LayerId
    previous_layers: Vec(StencilLayer)
    profile_db: CorpusProfileDB
    l0_seed_manifest: L0SeedManifest
    config: LayerBuildConfig
end

struct StencilLayer
    id: LayerId
    name: StringId
    parent_layer_ids: Vec(LayerId)
    max_arity: u8
    max_absorbed_ops: u32
    candidates: Vec(VerifiedBenchCandidate)
    selected: Vec(RuntimeStencilRecord)
    aliases: Vec(StencilAlias)
    rejected: Vec<CandidateReject>
    report: LayerReport
end

struct StencilCandidate
    id: CandidateId
    layer: LayerId
    name: StringId
    sequence: CandidateSequence
    pattern: StencilPattern
    fact_key: FactKey
    contract: StencilContract
    expansion: StencilExpansion
    kind: CandidateKind
    source: CandidateSource
end

struct CandidateSequence
    len: u8
    nodes: FixedVec(StencilNodeRef, 4)
    connective: SequenceConnective
    start_state: StateShape
    end_state: StateShape
end

enum SequenceConnective
    FALLTHROUGH
    BRANCH_PHRASE
    LOOP_BODY
    TRACE_WINDOW
    PROJECTION_BUNDLE
    CALL_BOUNDARY
    EDGE_CHAIN
end

enum CandidateKind
    CODE_STENCIL
    REWRITE_STENCIL
    ALIAS_CANDIDATE
    EMPTY_REWRITE
end

enum CandidateSource
    L0_SEED
    LAYER_CLOSURE
    CORPUS_WINDOW
    TRACE_WINDOW
    MANUAL_EXPERIMENT
end
```

### 5.9 Runtime export products

```moonlift
struct RuntimeStencilLibrary
    id: Hash128
    target_arch: TargetArch
    target_abi: TargetAbi
    layers_included: Vec(LayerId)
    code_stencils: Vec(CodeStencilRecord)
    rewrite_stencils: Vec(RewriteStencilRecord)
    selector_table: RuntimeSelectorTable
    blob: BinaryBlob
    manifest: RuntimeManifest
end

struct RuntimeSelectorTable
    id: Hash128
    max_layer: LayerId
    entries: Vec(SelectorEntry)
    fallback_stencil: StencilId
    format: SelectorFormat
end

struct SelectorEntry
    pattern_key: PatternKey
    fact_key: FactKey
    max_layer: LayerId
    choice: StencilChoice
end

enum StencilChoice
    CODE(stencil: StencilId)
    REWRITE(rewrite: StencilId)
    ALIAS(target: StencilId)
    FALLBACK(reason: FallbackReason)
end
```

---

## 6. Harness regions

The harness can be described as regions with explicit continuations.

### 6.1 Corpus loading

```moonlift
region harness_load_corpus(
    config: ptr(CorpusConfig);

    loaded: cont(db: ptr(CorpusDB)),
    rejected: cont(report: ptr(CorpusRejectReport)),
    io_error: cont(path: Path, code: IOError),
    oom: cont())
```

Semantics:

- enumerates configured partitions;
- normalizes Lua files;
- records source origin/license metadata;
- does not compile source yet;
- emits a `CorpusDB`.

### 6.2 Corpus compilation

```moonlift
region harness_compile_corpus(
    db: ptr(CorpusDB),
    config: ptr(CompileConfig);

    compiled: cont(bundle_db: ptr(ProtoBundleDB)),
    partial: cont(bundle_db: ptr(ProtoBundleDB), rejects: ptr(CompileRejectReport)),
    failed: cont(report: ptr(CompileRejectReport)),
    oom: cont())
```

Semantics:

- compiles normalized Lua units into Moonlift Lua VM bytecode;
- keeps compile rejects as profile data;
- does not reject the whole corpus when optional partitions fail;
- must reject the build if mandatory AWFY units fail.

### 6.3 Static profiling

```moonlift
region harness_profile_static(
    bundles: ptr(ProtoBundleDB),
    config: ptr(StaticProfileConfig);

    profiled: cont(profile: ptr(StaticBytecodeProfile)),
    failed: cont(report: ptr(StaticProfileFailureReport)),
    oom: cont())
```

Semantics:

- computes opcode counts;
- computes opcode windows up to `config.max_window`;
- computes operand shape and control shape tables;
- computes static liveness approximations;
- emits corpus-level static profile tables.

### 6.4 Dynamic profiling

```moonlift
region harness_profile_dynamic(
    bundles: ptr(ProtoBundleDB),
    config: ptr(DynamicProfileConfig);

    profiled: cont(profile: ptr(DynamicTraceProfile)),
    partial: cont(profile: ptr(DynamicTraceProfile), failures: ptr(DynamicRunFailureReport)),
    failed: cont(report: ptr(DynamicRunFailureReport)),
    oom: cont())
```

Semantics:

- runs runnable corpus entries in instrumented interpreter;
- records dynamic windows, hot anchors, branch outcomes, observed value facts, table facts, and call facts;
- records side exits and trace shapes;
- must support AWFY benchmark iteration loops;
- may skip non-runnable library modules.

### 6.5 Profile merge

```moonlift
region harness_merge_profiles(
    static_profile: ptr(StaticBytecodeProfile),
    dynamic_profile: ptr(DynamicTraceProfile),
    config: ptr(ProfileMergeConfig);

    merged: cont(profile_db: ptr(CorpusProfileDB)),
    failed: cont(reason: ProfileMergeFailure),
    oom: cont())
```

Semantics:

- merges static and dynamic evidence;
- computes seed weights;
- computes coverage targets;
- produces `CorpusProfileDB`.

### 6.6 L0 seed build

```moonlift
region harness_build_l0_seed_manifest(
    profile_db: ptr(CorpusProfileDB),
    manual_seeds: ptr(ManualSeedFile),
    primitive_specs: ptr(PrimitiveSpecLibrary),
    config: ptr(SeedConfig);

    built: cont(manifest: ptr(L0SeedManifest)),
    invalid: cont(report: ptr(SeedValidationReport)),
    failed: cont(reason: SeedBuildFailure),
    oom: cont())
```

Semantics:

- includes all required primitive opcode/fact stencils;
- includes manual seeds;
- derives corpus/AWFY observed seeds;
- validates seed contracts;
- emits an `L0SeedManifest`.

### 6.7 Generate L0

```moonlift
region harness_generate_l0(
    manifest: ptr(L0SeedManifest),
    config: ptr(LayerBuildConfig);

    layer: cont(l0: ptr(StencilLayer)),
    failed: cont(report: ptr(LayerFailureReport)),
    oom: cont())
```

Semantics:

- converts every seed into one or more candidates;
- emits Moonlift candidate kernels;
- compiles through Cranelift;
- mines object code;
- verifies contracts;
- benchmarks candidates;
- exports selected `L0` stencil records.

### 6.8 Generate next layer

```moonlift
region harness_generate_next_layer(
    input: ptr(LayerInput);

    layer: cont(next: ptr(StencilLayer)),
    no_new_candidates: cont(report: ptr(LayerReport)),
    failed: cont(report: ptr(LayerFailureReport)),
    oom: cont())
```

Semantics:

- enumerates all contract-valid candidate sequences up to arity 4 over the currently allowed library set;
- composes contracts;
- emits candidates;
- compiles/mines/verifies/benchmarks;
- classifies winners and aliases;
- emits next layer.

### 6.9 Iterate to L4

```moonlift
region harness_iterate_to_l4(
    l0: ptr(StencilLayer),
    profile_db: ptr(CorpusProfileDB),
    config: ptr(IterateConfig);

    complete: cont(layers: ptr(StencilLayerSet)),
    partial: cont(layers: ptr(StencilLayerSet), report: ptr(IterationReport)),
    failed: cont(report: ptr(IterationFailureReport)),
    oom: cont())
```

Semantics:

- builds L1, L2, L3, and L4 automatically;
- each layer uses previous selected layers as atoms;
- each layer preserves rejected/aliased/winner metadata;
- stops only on failure, policy limit, or successful L4.

### 6.10 Export runtime library

```moonlift
region harness_export_runtime_library(
    layers: ptr(StencilLayerSet),
    config: ptr(ExportConfig);

    exported: cont(library: ptr(RuntimeStencilLibrary)),
    failed: cont(report: ptr(ExportFailureReport)),
    oom: cont())
```

Semantics:

- builds runtime selector tables;
- emits binary blobs and metadata;
- emits C/Moonlift headers;
- emits debug reports;
- includes only selected winners and required aliases/fallbacks.

### 6.11 End-to-end build

```moonlift
region harness_build_all(
    corpus_config: ptr(CorpusConfig),
    manual_seed_file: ptr(ManualSeedFile),
    build_config: ptr(HarnessBuildConfig);

    exported: cont(library: ptr(RuntimeStencilLibrary), report: ptr(HarnessBuildReport)),
    partial: cont(report: ptr(HarnessBuildReport)),
    failed: cont(report: ptr(HarnessBuildReport)),
    oom: cont())
```

Semantics:

```text
load corpus
compile corpus
profile static
profile dynamic
merge profiles
build L0 manifest
generate L0
iterate L1..L4
export runtime library
write reports
```

---

## 7. Candidate validity

A candidate sequence is valid only if all contracts compose.

```moonlift
region validate_candidate_sequence(
    seq: ptr(CandidateSequence),
    context: ptr(SequenceValidationContext);

    valid: cont(contract: ptr(StencilContract)),
    invalid: cont(reason: SequenceInvalidReason),
    needs_boundary: cont(boundary: ptr(BoundaryRequirement)),
    oom: cont())
```

Validity requirements:

```text
1. Output StateShape of node i satisfies input StateShape of node i+1.
2. Effects compose without hiding observable Lua behavior.
3. Control exits are explicit.
4. Side exits have precise snapshots.
5. Projections preserve semantic pc/top/frame/roots.
6. Dependencies are merged.
7. Liveness facts justify DCE and output redirection.
8. Calls/yields/errors/metamethods are boundary-safe.
9. GC and barriers are preserved.
10. Debug hooks and observable stack state are not skipped.
```

Invalid examples:

```text
DCE of GETTABLE when __index may run.
Fusion across CALL without a boundary projection.
Dropping a guard whose fact is not proven at trace entry.
Changing the pc associated with a side exit.
Eliding a write that can be observed by hook/error/yield.
```

Valid examples:

```text
LOADK R1; MOVE R2 R1 -> LOADK R2 if R1 dead.
ADD Rtmp Ra Rb; RETURN Rtmp -> ADD_RETURN if ADD is pure/known.
EQ; JMP -> EQ_BRANCH if side effects and branch polarity preserved.
project_slot A; project_slot B; project_slot C -> PROJECT_slots_3.
```

---

## 8. L0 seed file format

Manual seeds live in a declarative file.

Example YAML-like schema:

```yaml
version: 1
name: moonlift-lua-l0-seeds
seeds:
  - name: add_i64_guarded_slot_slot_to_slot
    kind: MANUAL_COMPOUND
    source: MANUAL_DESIGN
    priority: HIGH
    pattern:
      opcodes: [ADD]
      operand_shape: ABC
    facts:
      B: MAYBE_INTEGER
      C: MAYBE_INTEGER
      A: RESULT_LIVE
    contract:
      effects: [MAY_SIDE_EXIT]
      projections: [INTERPRETER_ON_GUARD_FAIL]
    target_partitions: [AWFY, MICROBENCH]
    comment: "Expected to cover numeric kernels early."

  - name: test_jmp_truthy
    kind: MANUAL_COMPOUND
    source: AWFY_OBSERVED
    priority: HIGH
    pattern:
      opcodes: [TEST, JMP]
      control: CONDITIONAL_BRANCH
    facts:
      tested: TRUTHY_OR_FALSEY
    contract:
      effects: [BRANCH]
      projections: []
    target_partitions: [AWFY]
```

Seed validation rejects:

```text
unknown opcode
impossible operand shape
missing projection for effect
unknown fact domain
duplicate seed name
contract weaker than expansion
unsupported target architecture
```

---

## 9. Layer build algorithm

### 9.1 L0 generation

```text
Input:
  PrimitiveSpecLibrary
  Manual L0 seeds
  CorpusProfileDB

Output:
  StencilLayer L0

Algorithm:
  1. Include every required primitive semantic stencil.
  2. Include manual seeds.
  3. Include corpus-observed high-priority seeds.
  4. Emit candidate kernels.
  5. Compile candidates.
  6. Mine holes/relocs/body/clobbers.
  7. Verify contracts.
  8. Benchmark.
  9. Select winners and aliases.
```

### 9.2 L1..L4 generation

```text
Input:
  layers[0..n-1]
  CorpusProfileDB
  LayerBuildConfig(max_arity = 4)

Output:
  layer[n]

Algorithm:
  1. Build atom set = selected stencils from previous layers.
  2. Enumerate all arity 1..4 candidate sequences over atom set.
  3. Prefer corpus-observed windows first in scheduling, but do not restrict to them in speed-max mode.
  4. Validate contract composition.
  5. Generate candidate kernel or rewrite spec.
  6. Compile/mine/verify.
  7. Benchmark.
  8. Select fastest winner per PatternKey × FactKey × LayerId.
  9. Record aliases for dominated candidates.
  10. Emit layer manifest and report.
```

### 9.2.1 Fact-combinatorial closure

The closure generator enumerates facts as part of the candidate space.
A stencil is not merely an opcode composition. It is an opcode composition under
a canonical fact class.

```text
Candidate =
  PatternWindow
  × OperandShape
  × CanonicalFactSet
  × ContinuationShape
  × EffectContext
```

For every arity window, the harness tries all relevant declared fact axes.
For example, `GETTABLE; ADD` is not one candidate. It can produce:

```text
GETTABLE_generic_ADD_generic
GETARRAY_i64_ADD_i64
GETTABLE_string_slot_ADD_i64
GETTABLE_may_metamethod_boundary_ADD
GETTABLE_result_dead_but_effectful
```

Only contract-valid combinations are emitted. Each fact axis must provide:

```text
1. consistency rules
2. legality rules
3. dependency rules
4. projection rules
5. invalidation rules
```

This is the central optimizer rule:

```text
No fact, no discovery.
Wrong fact, wrong code.
Rich fact, larger optimization space.
```

Local physical fusions require only operand and liveness facts. LuaJIT-class
rewrites require richer products: table shape, metatable absence, known call
targets, loop-carried values, escape state, and side-exit materialization
projections.

Layer generation therefore uses:

```text
CandidateSpace(Lk) =
  compose_arity_le_4(
    stencils from L0..L{k-1},
    all declared canonical FactSet combinations,
    all valid operand/continuation/effect shapes)
```

Then selection keeps the fastest verified survivor for each:

```text
PatternKey × FactKey × StateShape × EffectContext × LayerId
```

### 9.2.2 Rewrite/shape legalization is not a later peephole pass

The harness keeps a rewrite-shaped view/pass, but it is not a separate
post-hoc optimizer that runs after ordinary stencil generation. It is the
semantic legalization point for:

```text
PatternWindow × OperandShape × CanonicalFactSet
```

A candidate can compile as native code and still have the wrong VM shape. For
example, branches, returns, calls, table writes, metamethod boundaries, and
producer-consumer rewrites all have different continuation/effect contracts.
Therefore every candidate carries explicit shape metadata:

```text
shape_kind          fallthrough | pure_rewrite | guarded_pure_rewrite |
                    branch_or_control_boundary | call_boundary |
                    effect_boundary | terminal_return
lowering            generic_opcode_sequence | move_move_forward | ...
continuation        fallthrough_pc_plus_arity | fallthrough_pc_plus_2 |
                    branch_pc_or_side_exit | return_boundary | ...
legalization_source default_opcode_shape | operand_fact_rewrite_schema | ...
```

Classic peephole optimization is represented as a small observed window plus
facts plus a specialized lowering, not as native-code patching:

```text
MOVE|MOVE @ MOVE:move_def;MOVE:move_uses_previous_def
  shape_kind   = pure_rewrite
  lowering     = move_move_forward
  continuation = fallthrough_pc_plus_2

ADDI|RETURN1 @ ADDI:i64;RETURN1:returns_previous_def
  shape_kind   = terminal_return
  lowering     = op_return1
  continuation = return_boundary_pc_plus_2
```

So the rewrite view is useful and retained, but the invariant is:

```text
The rewrite layer is a legalization/lowering-shape view over normal candidates,
not an optional later peephole optimizer.
```

### 9.2.3 Selection and benchmarking gate

Layer generation is discovery. It does not mean every generated candidate is a
runtime stencil or an atom for the next layer. A layer must pass an explicit
selection gate:

```text
verified shape
  × concrete codegen support
  × object compilation
  × profile frequency
  × profitability benchmark
  -> selected[]
```

The harness writes `selected_layer.json`; only `selected[]` may seed L2. This
prevents the L2 generator from composing thousands of legal-but-useless or
boundary-only L1 candidates.

Layer closure is cumulative, not previous-layer-only and not motif-tiling-only:

```text
L1 atoms = combinations from {L0}
L2 atoms = combinations from {L0, selected L1}
L3 atoms = combinations from {L0, selected L1, selected L2}
LN atoms = combinations from {L0, selected L1, ..., selected L(N-1)}
```

`max_arity = 4` means four composed units. The resulting opcode span can be
larger and is controlled by a separate budget such as `max_opcodes`. Profile and
motif data are filters/schedulers for slow or unobserved spans; they do not
replace the cumulative candidate-space definition.

Current offline benchmarking mode is `profitability_model_v1`. It is not a fake
random benchmark. It is a deterministic VM-shaped profitability estimate using:

```text
baseline opcode/interpreter cycles
candidate shape_kind/lowering
observed profile frequency or rewrite-fact frequency
native artifact size after compilation/composition
side-exit / guard risk
concrete lowering support
```

A stencil that compiles but only side-exits to the interpreter is classified as
legal but unprofitable. Native execution benchmarking can replace or calibrate
this model later; the selection interface remains the same.

Facts feed a lowering-plan step before emission. The lowering plan is fail-closed:
if a `FactSet` has no lowering for the selected backend, the candidate is
unsupported and must not be emitted as a placeholder stencil. For GCC this
currently includes concrete lowering for raw table reads, integer arithmetic,
returns, local rewrites, and branch facts (`EQ`/`EQK` primitive or i64 equality,
`LT` i64 compare).

For L2+, lower-layer atoms are already compiled native units. Their opcode lists
are selector/profile metadata only, not codegen input. Higher-layer composition
uses native artifacts and native budgets (`bytes`, holes, relocs, exits), while
`max_profile_span` may bound profile lookup over flattened opcode metadata.
`max_opcodes` is not a semantic validity rule for native-composed layers.

### 9.3 Speed-max scheduling

Speed-max mode does not prune by size before measurement.

It may still schedule candidates in priority order:

```text
1. AWFY-observed hot windows.
2. Dynamic corpus hot trace windows.
3. Static corpus frequent windows.
4. Manual seeds and their immediate closure neighborhoods.
5. Remaining valid combinations.
```

This scheduling affects build time only. It must not change the definition of the valid universe.

---

## 10. Benchmark and selection policy

Candidate classification:

```moonlift
enum CandidateClassification
    SELECTED_FASTEST
    SELECTED_REQUIRED_FALLBACK
    ALIAS_IDENTICAL
    DOMINATED_SLOWER
    VALID_UNMEASURED
    VALID_DEBUG_ONLY
    INVALID_CONTRACT
    INVALID_OBJECT
    INVALID_ABI
    INVALID_PROJECTION
    REJECTED_POLICY
end
```

Selection key:

```text
PatternKey × FactKey × StateShape × EffectContext × LayerId
```

Selection rule in speed-max:

```text
For each selection key, keep the fastest verified candidate.
If a larger candidate is bigger but faster, keep it.
If a smaller candidate is faster, keep it.
If two candidates tie, prefer simpler contract and fewer exits.
```

Size is recorded but not used as a primary rejection criterion unless it hurts measured speed or violates hard artifact limits.

Metrics:

```text
microbench cycles
AWFY benchmark delta
dynamic corpus speed delta
materialization time
code size
hole count
reloc count
side-exit count
exit frequency
branch misses if available
i-cache counters if available
```

---

## 11. Reports

The harness must generate human-readable reports.

### 11.1 Corpus report

```text
corpus_report.md
  partitions
  source counts
  compile success/failure
  dynamic run success/failure
  top opcodes
  top pairs/triples/quads
  top loop shapes
  top call shapes
  top table shapes
```

### 11.2 L0 seed report

```text
l0_seed_report.md
  required primitive seeds
  manual seeds
  AWFY-derived seeds
  corpus-derived seeds
  rejected seeds
  expected coverage
```

### 11.3 Layer report

```text
layer_Ln_report.md
  atom count
  candidate count
  valid count
  invalid count by reason
  verified count
  benchmarked count
  selected count
  alias count
  top speed wins
  top AWFY coverage wins
  largest absorbed bytecode windows
```

### 11.4 Coverage report

```text
coverage_report.md
  AWFY bytecode window coverage by layer
  corpus bytecode window coverage by layer
  dynamic hot trace coverage by layer
  fallback reasons
  missed high-frequency patterns
```

### 11.5 Export report

```text
runtime_export_report.md
  exported code stencils
  exported rewrite stencils
  selector table size
  fallback table size
  binary blob size
  target arch/abi
  build hashes
```

---

## 12. Command-line interface

### 12.1 Profile Are We Fast Yet

```bash
moonlift-jit-harness profile-awfy \
  --awfy-root third_party/are-we-fast-yet \
  --lua-version 5.4 \
  --out build/jit/profile/awfy
```

### 12.2 Profile a larger corpus

```bash
moonlift-jit-harness profile-corpus \
  --config jit_corpus.toml \
  --out build/jit/profile/corpus
```

### 12.3 Build L0 seeds

```bash
moonlift-jit-harness seed-l0 \
  --profile build/jit/profile/corpus/profile_db.json \
  --manual seeds/l0_manual.yaml \
  --out build/jit/layers/l0_seed_manifest.json
```

### 12.4 Generate L0

```bash
moonlift-jit-harness build-layer \
  --layer 0 \
  --seed-manifest build/jit/layers/l0_seed_manifest.json \
  --out build/jit/layers/L0
```

### 12.5 Iterate to L4

```bash
moonlift-jit-harness iterate-layers \
  --from build/jit/layers/L0/layer.json \
  --to-layer 4 \
  --max-arity 4 \
  --mode speed-max \
  --profile build/jit/profile/corpus/profile_db.json \
  --out build/jit/layers
```

### 12.6 Export runtime library

```bash
moonlift-jit-harness export-runtime \
  --layers build/jit/layers/L0 build/jit/layers/L1 build/jit/layers/L2 build/jit/layers/L3 build/jit/layers/L4 \
  --target x86_64-sysv \
  --out build/jit/runtime_stencils
```

---

## 13. Build configuration

Example TOML:

```toml
[harness]
mode = "speed-max"
max_layer = 4
max_arity = 4
store_source_copy = false
store_license_metadata = true

[corpus.awfy]
enabled = true
root = "third_party/are-we-fast-yet"
must_compile = true
must_run = true
seed_weight = 10.0
bench_weight = 10.0

[corpus.luarocks]
enabled = true
root = "corpus/luarocks"
must_compile = false
must_run = false
seed_weight = 2.0
bench_weight = 0.5

[static_profile]
max_window = 8
record_operand_shapes = true
record_liveness = true

[dynamic_profile]
enabled = true
max_trace_len = 4096
max_runs_per_benchmark = 20
record_value_facts = true
record_table_facts = true
record_call_facts = true

[layer]
max_arity = 4
allow_manual_l0_seeds = true
generate_all_valid = true
prune_size_before_measurement = false

[selection]
primary_metric = "speed"
prefer_smaller_on_tie = true
keep_debug_aliases = true

[export]
target = "x86_64-sysv"
include_debug_names = true
include_reports = true
```

---

## 14. Invariants

The harness must preserve these invariants.

### 14.1 Semantic invariants

```text
Proto.code is immutable.
Interpreter semantics are the source of truth.
Every stencil contract is verified against its expansion or primitive semantics.
Every side exit has a precise projection.
Every effect has an explicit boundary requirement.
Every dependency is exported for runtime invalidation.
```

### 14.2 Harness/runtime boundary invariants

```text
Runtime does not call Cranelift.
Runtime does not mine object files.
Runtime does not generate new stencil kinds.
Runtime does not search the full universe.
Runtime only uses exported CodeStencil / RewriteStencil / SelectorTable products.
```

### 14.3 Corpus invariants

```text
Corpus profiles are reproducible from recorded config hashes.
Source origin and license metadata are recorded.
Source code does not need to be redistributed with the stencil library.
AWFY coverage is reported for every accepted speed-max library.
```

### 14.4 Layer invariants

```text
L0 contains required primitive stencils and accepted seeds.
Ln is generated from previous layers using arity <= 4.
Selected candidates are verified before export.
Aliases point only to verified selected stencils.
Layer reports preserve rejected candidate reasons.
```

---

## 15. Relationship to runtime refinement

The harness builds layers that the runtime uses as refinement levels.

```text
runtime PlanVersion generation 0 -> selector max layer L0
runtime PlanVersion generation 1 -> selector max layer L1
runtime PlanVersion generation 2 -> selector max layer L2
runtime PlanVersion generation 3 -> selector max layer L3
runtime PlanVersion generation 4 -> selector max layer L4
```

The runtime does not understand how a layer was generated.
It only sees:

```text
StencilId
LayerId
PatternKey
FactKey
Contract
Code bytes / rewrite rule
Selector entry
```

This is the point of the harness: turn empirical Lua bytecode and dynamic trace behavior into a finite runtime stencil universe.

---

## 16. Minimal implementation sequence

### Phase 1: AWFY static profile

- Discover AWFY Lua files.
- Compile to Moonlift Lua VM bytecode.
- Count opcode singles/pairs/triples/quads.
- Write `corpus_report.md`.

### Phase 2: L0 manual + AWFY seeds

- Write `seeds/l0_manual.yaml`.
- Generate `L0SeedManifest`.
- Generate/verify primitive `L0` stencils.
- Include high-value AWFY seeds.

### Phase 3: L1 closure

- Enumerate arity <= 4 sequences over `L0`.
- Generate candidates.
- Compile/mine/verify.
- Benchmark on AWFY micro/macro tests.
- Export `L1` report.

### Phase 4: L2-L4 automation

- Iterate layer generation automatically.
- Use AWFY and corpus profiles for scheduling.
- Keep speed-max policy.
- Export `RuntimeStencilLibrary`.

### Phase 5: dynamic fact profiling

- Instrument interpreter.
- Record facts for AWFY runs.
- Feed facts into `L0` seed and layer generation.
- Regenerate layers.

### Phase 6: larger corpora

- Add LuaRocks/GitHub/project corpora.
- Keep source profile metadata.
- Expand seed coverage.
- Compare speed and coverage.

---

## 17. Summary

The harness is the empirical engine of the Lua VM JIT.

It starts from real Lua bytecode, especially Are We Fast Yet, then builds `L0` from required primitive stencils plus manually and empirically chosen seed stencils. From there it automatically grows `L1` through `L4` by bounded-arity closure.

The harness is allowed to be expensive. It may compile thousands or millions of candidates, mine object code, benchmark aggressively, and generate large reports. The runtime must remain simple.

Final runtime promise:

```text
facts + bytecode window
    -> generated selector table
    -> existing stencil
    -> copy/stamp/fixup/publish/link
```

No runtime stencil synthesis. No runtime Cranelift. No hidden optimizer.

The stencil library is generated by measurement, and the runtime only consumes the measured result.
