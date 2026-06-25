# Lalin ASDL kernel/fact tower redesign
Redesign Lalin's ASDL phase tower so fact gathering produces canonical fast lower-layer representatives before dumb backend projection. Seed ASDL modules added: LalinFlow, LalinMem, LalinKernel.
**Workflow ID**: wf-asdl-kernel-tower
**Started**: 2026-06-15 11:45:38
---

## Scout Output — 2026-06-15 11:52:30

## Files Retrieved

1. `lua/lalin/schema/flow.asdl` (lines 1-55) - Seed `LalinFlow` schema: CFG edges, loop/domain/range facts; depends on `LalinCode`.
2. `lua/lalin/schema/mem.asdl` (lines 1-70) - Seed `LalinMem` schema: access/base/index/pattern/alignment/bounds/alias/dependence/proof facts; depends on `LalinCode`, `LalinFlow`, and `LalinTree.ContractFact`.
3. `lua/lalin/schema/kernel.asdl` (lines 1-82) - Seed `LalinKernel` schema: canonical kernel streams/exprs/reductions/stores/schedules/module plan; depends on `LalinCode`, `LalinFlow`, `LalinMem`, `LalinVec`.
4. `lua/lalin/schema/init.lua` (lines 10-23, 121-137) - Schema load order includes `code`, then `flow`, `mem`, `kernel`, then `parse`, `vec`, etc.
5. `lua/lalin/schema/code.asdl` (lines 66-82, 138-189) - `LalinCode` memory/place/load/store/terminator/module definitions.
6. `lua/lalin/schema/vec.asdl` (lines 185-290) - Existing tree-based vector safety/kernel plan schema.
7. `lua/lalin/frontend_pipeline.lua` (lines 64-75, 80-197) - Current native/C pipelines; tree → code → validation → backend/C, plus vector replacement hook from typed tree.
8. `lua/lalin/tree_to_code.lua` (lines 317-318, 480-488, 650-672, 758-900, 1295-1456) - Main lowering from typed tree/control regions into `LalinCode`; emits memory access metadata but not flow/mem/kernel facts.
9. `lua/lalin/code_to_back.lua` (lines 192-346, 430-469) - Direct `LalinCode` → `LalinBack` projection; supports replacement funcs.
10. `lua/lalin/code_to_c.lua` (lines 38-48, 151-192, 204-215, 269-291, 299-304, 539-577) - Direct `LalinCode` → `LalinC`; many scalar/atomic ops lower through helpers.
11. `lua/lalin/code_validate.lua` (lines 1-180, 431-439, 512-515, 604-606) - Current `LalinCode` validator and memory access validation.
12. `lua/lalin/vec_loop_facts.lua` (lines 240-625) - Existing tree/control-region vector fact extraction.
13. `lua/lalin/vec_kernel_plan.lua` (lines 1-260, grep hits 119-187) - Existing tree-based vector kernel planner.
14. `lua/lalin/vec_kernel_safety.lua` (lines 236-481) - Existing vector bounds/alignment/alias/safety decision.
15. `lua/lalin/vec_kernel_to_back.lua` (lines 297-329, 420-507, 538-746, 910-913) - Existing vector plan → backend command lowering.
16. `lua/lalin/schema/back.asdl` (lines 117-119, 265-279, 355-377) - Backend memory info/alias facts/load-store command forms/inspection schema.
17. `lua/lalin/back_validate.lua` (lines 111-130, 239-241, 594-629, 856-919) - Backend memory/alias/access validation.
18. `lua/lalin/host_module_values.lua` (lines 271-291, 345-405, 421-447) - Hosted API C backend selection/emit/compile path.
19. `benchmarks/bench_c_vs_cranelift.lua` (lines 53-80, 124-243, 306-308) - C-vs-Cranelift benchmark with libtcc vs shared-O3 distinction.
20. `benchmarks/bench_kernels.lua` (lines 331-379, 467-513) - Kernel benchmark harness using pipeline `parse_and_lower`.
21. `tests/test_schema_core.lua` (lines 8-14, 49-122) - Schema loader smoke tests; currently covers `LalinCode` construction but not explicit Flow/Mem/Kernel nodes.
22. `tests/test_schema_compile_pipeline.lua` (lines 26-40) - Pipeline asserts `LalinCode` exposure and no legacy `tree_to_back`.
23. `tests/test_code_to_back.lua` (lines 28-37, 76-95, 134-148) - Code lowering/projection/JIT tests and no `tree_to_back`.
24. `tests/test_code_to_c.lua` (lines 40-49, 102-138, 143-149) - Code→C validation/emission tests, helper expectation.
25. `tests/test_code_validate.lua` (lines 61-180) - Code validation tests, including invalid memory access alignment.
26. `tests/test_vec_kernel_plan.lua` (lines 113-187) - Existing vector kernel planning coverage for reduce/map/safety assumptions.
27. `lua/lalin/asdl_context.lua` (lines 260-345, 668-705) - ASDL type checking/definition behavior; unknown type failure, all definitions pre-registered before class build.
28. `lua/lalin/context_define_schema.lua` (lines 1-22, 107-124) - Schema modules flattened into one definition list before context define.

## Key Code

### Seed ASDL fact/kernel tower already exists but is schema-only

`lua/lalin/schema/init.lua`:

```lua
local SCHEMA_ASDL_MODULES = {
    "core",
    "back",
    ...
    "tree",
    "code",
    "flow",
    "mem",
    "kernel",
    "parse",
    "vec",
    ...
}
```

`lua/lalin/schema/flow.asdl`:

```asdl
FlowFactSet = (
  LalinCode.CodeModuleId module,
  LalinFlow.FlowEdge* edges,
  LalinFlow.FlowLoopFacts* loops,
  LalinFlow.FlowValueRange* ranges,
  LalinFlow.FlowReject* rejects
) unique
```

`lua/lalin/schema/mem.asdl`:

```asdl
MemAccessFact = (
  LalinMem.MemAccessId id,
  LalinCode.CodeFuncId func,
  LalinCode.CodeBlockId block,
  LalinMem.MemAccessKind kind,
  LalinCode.CodePlace place,
  LalinCode.CodeMemoryAccess access,
  LalinMem.MemBase base,
  LalinMem.MemIndex index,
  LalinMem.MemAccessPattern pattern,
  LalinMem.MemAlignment alignment,
  LalinMem.MemBounds bounds,
  LalinMem.MemTrap trap
) unique
```

`lua/lalin/schema/kernel.asdl`:

```asdl
KernelModulePlan = (
  LalinCode.CodeModuleId module,
  LalinFlow.FlowFactSet flow,
  LalinMem.MemFactSet memory,
  LalinKernel.KernelFuncPlan* funcs
) unique
```

No implementation modules exist yet:

- `find lua/lalin -name '*flow*'` → only `schema/flow.asdl`
- `find lua/lalin -name '*mem*'` → only `schema/mem.asdl`
- `find lua/lalin -name '*kernel*'` → `schema/kernel.asdl` plus old `vec_kernel_*`

### Current pipeline bypasses new fact tower

`lua/lalin/frontend_pipeline.lua`:

```lua
local TreeToCode = require("lalin.tree_to_code").Define(T)
local CodeValidate = require("lalin.code_validate").Define(T)
local CodeToBack = require("lalin.code_to_back").Define(T)
local CodeToC = require("lalin.code_to_c").Define(T)
local VecKernelPlan = require("lalin.vec_kernel_plan").Define(T)
local VecKernelToBack = require("lalin.vec_kernel_to_back").Define(T)
```

Native path:

```lua
local resolved = Layout.module(checked.module, opts.layout_env)
local code_module = TreeToCode.module(resolved, ...)
local code_report = CodeValidate.validate(code_module, collector)

local program = CodeToBack.module(code_module, {
  validate = false,
  replacement_funcs = vector_back_replacements(resolved)
})
```

Vector hook is still typed-tree based:

```lua
local ok_plan, plan = pcall(function()
  return VecKernelPlan.plan(name, visibility, params, result_ty, body, contracts or {})
end)
local ok_lower, lowered = pcall(function()
  return VecKernelToBack.lower_func(name, visibility, params, result_ty, plan)
end)
```

### Current `LalinCode` memory facts are local metadata

`lua/lalin/tree_to_code.lua`:

```lua
local function memory_access(ctx, mode, source_ty, code_type)
    return Code.CodeMemoryAccess(
      mode,
      code_type or code_ty(ctx, source_ty),
      align_of(ctx, source_ty),
      Code.CodeMayTrap,
      false,
      nil
    )
end
```

Loads/stores:

```lua
local function load_place(ctx, place, source_ty, reason)
    local dst = new_temp(ctx, reason or "load")
    append_inst(ctx, Code.CodeInstLoad(dst, place,
      memory_access(ctx, Code.CodeMemoryRead, source_ty, code_ty(ctx, source_ty))),
      origin_generated(reason or "load"))
    return dst, code_ty(ctx, source_ty)
end

local function store_place(ctx, place, source_ty, value, origin)
    append_inst(ctx, Code.CodeInstStore(place, value,
      memory_access(ctx, Code.CodeMemoryWrite, source_ty, code_ty(ctx, source_ty))),
      origin or origin_generated("store"))
end
```

### Backend projection is already “dumb” / direct

`lua/lalin/code_to_back.lua`:

```lua
local function memory_info(ctx, access, tag)
    ...
    return Back.BackMemoryInfo(
        Back.BackAccessId("code:" .. tag),
        Back.BackAlignKnown(access.align or 1),
        Back.BackDerefBytes(bytes, "CodeMemoryAccess"),
        Back.BackMayTrap,
        Back.BackMayNotMove,
        access_mode(access.mode)
    )
end
```

Load/store projection:

```lua
ctx.cmds[#ctx.cmds + 1] =
  Back.CmdLoadInfo(bid(k.dst), shape(k.access.ty), addr,
                   memory_info(ctx, k.access, i.id.text))

ctx.cmds[#ctx.cmds + 1] =
  Back.CmdStoreInfo(shape(k.access.ty), addr, bid(k.value),
                    memory_info(ctx, k.access, i.id.text))
```

Replacement hook:

```lua
local replacements = opts.replacement_funcs or {}
...
for name, cmds in pairs(replacements) do
    for i = 1, #cmds do ctx.cmds[#ctx.cmds + 1] = cmds[i] end
end
```

### Existing vector machinery proves the intended pattern, but over `LalinTree`

`lua/lalin/vec_loop_facts.lua` recognizes canonical tree control regions:

```lua
if #region.blocks ~= 0 then return nil, "multi-block vector loop recognition deferred" end
local jump = find_self_jump(region)
...
local index_i, stop = find_exit_test(region, bindings)
...
return V.VecLoopFacts(
  region_loop_id(region.region_id),
  V.VecLoopSourceControlRegion(...),
  V.VecDomainCounted(params[index_i].init, stop, step),
  { V.VecPrimaryInduction(...) },
  V.VecExprGraph(exprs),
  memory,
  aliases,
  dependences,
  ranges,
  stores,
  reductions,
  {},
  rejects
)
```

`lua/lalin/vec_kernel_safety.lua` computes bounds/alignment/alias safety:

```lua
local bounds, bound_assumptions, bound_proofs, bound_rejects =
  bounds_for_uses(self.facts, self.uses, stop, self.contracts or {}, self.core.scalars or {})

local alignments = alignments_for_uses(self.uses)
local aliases, alias_assumptions = aliases_for_uses(self.uses, self.contracts or {})

if #bound_rejects > 0 then
  safety = V.VecKernelSafetyRejected(bound_rejects)
elseif #assumptions == 0 then
  safety = V.VecKernelSafetyProven(proofs)
else
  safety = V.VecKernelSafetyAssumed(proofs, assumptions)
end
```

`lua/lalin/vec_kernel_to_back.lua` emits backend memory info/alias facts from vector safety:

```lua
cmds[#cmds + 1] =
  Back.CmdLoadInfo(loaded, shape_vec(vec_ty), address_for_binding(...),
                   memory_info(ctx, Back.BackAccessRead, "vload", ...))

cmds[#cmds + 1] =
  Back.CmdStoreInfo(shape_vec(vec_ty), address_for_binding(...), vec_value,
                    memory_info(vec_ctx, Back.BackAccessWrite, "vstore", ...))

emit_alias_facts(cmds, aliases or {}, alias_state)
```

## Relationships

- Current main path:
  - `parse/open/closure/type/layout`
  - `tree_to_code`
  - `code_validate`
  - `code_to_back` or `code_to_c`
  - backend validator / C validator
- Current vector fast path:
  - `frontend_pipeline.vector_back_replacements(resolved LalinTree)`
  - `vec_kernel_plan.plan(...)`
  - `vec_kernel_to_back.lower_func(...)`
  - replacement backend commands spliced into `code_to_back`
- New desired fact tower schemas are positioned after `LalinCode`:
  - `LalinFlow` references `LalinCode`
  - `LalinMem` references `LalinCode`, `LalinFlow`, and `LalinTree.ContractFact`
  - `LalinKernel` references `LalinCode`, `LalinFlow`, `LalinMem`, `LalinVec`
- Backend validation already understands richer memory command metadata:
  - `BackMemoryInfo`
  - `CmdLoadInfo` / `CmdStoreInfo`
  - `CmdAliasFact`
  - duplicate/missing access validation
  - dereference/trapping/motion checks

## Observations

- `LalinFlow`, `LalinMem`, and `LalinKernel` are loaded by schema but have no Lua analysis/planning/lowering modules yet.
- Existing vector lowering is a concrete precedent for fact → plan → backend, but its facts are tied to `LalinTree`, `LalinBind`, and control-region syntax.
- `LalinCode` already has the right raw ingredients for code-based analysis: blocks, params, terminators, places, loads/stores, ptr offsets, view ops, signatures.
- `code_to_back.lua` and `code_to_c.lua` are projection points; both currently consume only `LalinCode`.
- `code_to_back.lua` already has a `replacement_funcs` seam used by vector lowering.
- `code_to_c.lua` lowers many arithmetic/atomic operations via helper calls; benchmarks explicitly distinguish libtcc “compile-smoke/JIT C path” from shared `-O3`.
- Tests strongly enforce that native/C lowering no longer loads legacy `tree_to_back` / `tree_to_c` modules.
- ASDL definition machinery flattens modules into one definition list before building classes, so forward type references inside the schema are tolerated if the referenced type exists somewhere in the schema. Unknown type names fail loudly in `asdl_context.make_check`.
- Dependency risk is mostly semantic/module-boundary risk, not immediate textual load-order failure: `kernel.asdl` depends on `LalinVec`, while it is listed before `vec.asdl`, but schema definition pre-registration makes this work today.
- `MemProofContract` depends back on `LalinTree.ContractFact`; that keeps part of the new memory proof layer tied to tree-level contract facts.

## Knowledge-builder Output — 2026-06-15 11:55:37

### What Matters Most for This Problem

- **Semantic phase boundary:** whether facts are truly derived from `LalinCode`, or still depend on `LalinTree`.
- **Backend reach:** the redesign must benefit both Cranelift/Back and C/libtcc-style dumb projection, not only the existing vector Back replacement seam.
- **Safety invariants:** bounds, alias, trap, volatility, atomics, and dependence facts must not become “optimization hints” that contradict `LalinCode`.
- **Canonical representative stability:** if facts choose a faster lower-layer form, IDs, signatures, access metadata, and validation boundaries must remain coherent.
- **Determinism and fail-loud behavior:** current vector replacement is speculative and silently swallowed; the new tower needs observable ASDL reasons without turning unsupported cases into compiler failures.
- **Migration risk:** existing vector logic is useful, but it is tree/control-region shaped; direct reuse may preserve the wrong phase boundary.

### Non-Obvious Observations

- The existing vector fast path is **not backend-neutral**. It lowers tree facts directly to `LalinBack` replacement commands, so it cannot help `code_to_c.lua`. Since the task explicitly cares about libtcc/default JIT C, any “canonical fast representative” that appears only as backend commands is too late for the C path.

- `code_to_back.lua`’s replacement seam is **function-level and all-or-nothing**. A replacement suppresses the normal `CmdDeclareFunc` and scalar body for that function, then expects the replacement command list to declare and define an ABI-compatible function itself. That hidden invariant is not visible at the `LalinCode` boundary.

- The current vector path validates the scalar `CodeModule`, then may emit unrelated replacement Back commands. This means `CodeValidate` is currently validating a body that may be dead. If the fact tower continues to bypass `LalinCode`, validation remains split between “source of facts” and “actual emitted program.”

- The C path has no analogous replacement seam. It projects `LalinCode` directly into C backend AST. Therefore, any improvement intended for libtcc has to confront the fact that `CodeToC` currently sees only scalar `LalinCode`, not `LalinKernel`.

- `code_to_c.lua` lowers many arithmetic operations through helper calls. For libtcc, helper-heavy scalar C is a poor optimization substrate. This makes the desired “canonical fast code before dumb projection” more important for C than for Cranelift, because libtcc will not recover high-level loop/algebra/vector structure later.

- `LalinFlow` is nominally code-based, but loop recognition after `tree_to_code` is materially different from the existing tree vectorizer. Tree recognition sees explicit control regions and self-jumps; `LalinCode` sees synthetic entry/exit blocks, block params, branch/trap blocks from asserts, and SSA-like jump arguments. The old recognition shape will not map directly.

- Block params in `LalinCode` are the real phi nodes. Induction facts must be inferred from `CodeTermJump` argument flow plus defining instructions such as `CodeInstBinary`. This is more general than the tree recognizer, but it means value-def/use reconstruction becomes a core invariant.

- `FlowEdgeKind` mixes syntactic edge categories with analysis categories. A `CodeTermJump` edge can also be a loop backedge. If edge kind is single-valued, the tower needs a consistent convention for whether “backedge” replaces or annotates “jump.”

- `FlowValueRange` stores several bounds as raw strings. That is weaker than the rest of the ASDL tower, which mostly references typed IDs and nodes. Range facts may become hard to compare, canonicalize, or validate if arithmetic meaning stays stringly.

- `MemAccessFact` duplicates `CodeMemoryAccess` while also adding stronger alignment, bounds, trap, and pattern facts. This creates a possible contradiction surface: e.g. `CodeMemoryAccess.trap = CodeMayTrap` while `MemTrap = MemNonTrapping`, or known alignments disagree.

- Current `code_to_back.lua` ignores richer trap/motion possibilities: it always emits `BackMayTrap` and `BackMayNotMove` from `CodeMemoryAccess`. So even if `LalinMem` proves non-trapping or no-alias facts, current projection will erase them unless the projection boundary changes.

- Backend validation already enforces relationships like “can move requires non-trapping.” This implies memory facts cannot be treated as independent decorations; trap, dereference size, access mode, and motion facts form a safety bundle.

- `LalinCode` memory addressing is split across nested `CodePlace` forms and explicit `CodeInstPtrOffset` value graphs. A memory fact layer must normalize both. Otherwise equivalent accesses can look unrelated depending on whether indexing stayed as a place or became pointer arithmetic.

- Views are especially subtle. Both `code_to_back.lua` and `code_to_c.lua` maintain side maps for view values, because `CodeInstView`, `CodeInstViewData`, `CodeInstViewLen`, and `CodeInstViewStride` are not simple memory operations. A code-based memory/kernel analysis that ignores this side behavior will miss canonical stream bases and lengths.

- `MemProofContract` still references `LalinTree.ContractFact`. That preserves a tree-level semantic dependency inside the supposedly code/lower fact tower. This is not just a load-order issue; it means proof provenance may still require tree concepts after `LalinCode`.

- Existing vector safety distinguishes proven, assumed, and rejected plans. The seed `LalinKernel` schema preserves that distinction, but assumptions are currently just `string*`. There is no explicit guard/check node in `KernelPlan`, so assumed safety depends on contracts being enforced or trusted elsewhere.

- Atomics and volatility are legality fences. `LalinMem` has atomic access kinds, but `LalinKernel` streams do not appear to carry atomic ordering or volatile semantics. That implies atomic/volatile accesses likely need hard rejection or very explicit preservation; otherwise a kernel plan can accidentally erase memory-ordering semantics.

- Existing vector planning uses `pcall` and silently falls back on failure. That conflicts with Lalin’s fail-fast/fail-loud philosophy, but unsupported optimization should not abort compilation either. The non-obvious distinction is: unsupported patterns should become ASDL rejection facts, while internal inconsistency should remain a compiler error.

- Replacement functions are emitted with `pairs(replacements)`, so multiple replacements have nondeterministic order. For ASDL/PVM-style cached compilation and reproducible benchmarks, fact and plan emission order matters more than it first appears.

- `CodeFuncId` is `fn:<name>` and not module-qualified, while globals include module names. If fact sets become cached, combined, or compared across modules, function IDs have a latent collision risk unless module scope is always implicit and isolated.

- `MemAccessId` and backend `BackAccessId` need a stable relationship. Current backend access IDs are `"code:" .. inst.id.text`; vector lowering emits its own access IDs. Any canonical lowering that expands one source access into multiple unrolled/vector accesses must preserve enough mapping for alias/dependence validation and inspection.

- The seed schemas have no validator yet. Schema smoke tests prove constructors load, not that facts are complete, sorted, referentially valid, non-contradictory, or module-consistent.

### Knowledge Gaps

- How strongly the Rust/Cranelift backend currently uses `BackMemoryInfo` and `CmdAliasFact` for optimization versus validation only.
- Whether the C backend schema has any existing vector/unrolled representation suitable for canonical fast code.
- Exact semantics and enforcement point of contracts such as noalias/readonly/writeonly.
- Whether multi-module compilation can place multiple `CodeModule`s or fact sets in one backend program.
- Which benchmarks are intended to prove the libtcc/default-C improvement path.

## Worker Output — 2026-06-15 14:02:03

## Completed
Implemented ready foundational tasks for `wf-asdl-kernel-tower`:

- T002 schema constructor coverage
- T003 code-level contract fact extraction
- T004 `LalinCode -> LalinFlow` facts
- T005 `LalinCode -> LalinMem` facts
- T006 `LalinCode/Flow/Mem/Contracts -> LalinKernel` planning
- T008 Kernel tower validation

Blocked as unsafe for this session:
- T007 vector migration onto Kernel tower
- T009 Kernel projection to C/Back

No ready tasks remain.

## Files Changed
- `tests/test_schema_core.lua` - Flow/Mem/Kernel constructor tests
- `lua/lalin/tree_to_code.lua` - emits `CodeContractFactSet`
- `tests/test_tree_to_code.lua` - contract lowering tests
- `lua/lalin/code_flow_facts.lua` - new Flow fact extraction phase
- `tests/test_code_flow_facts.lua` - Flow fact tests
- `lua/lalin/code_mem_facts.lua` - new Mem fact extraction phase
- `tests/test_code_mem_facts.lua` - Mem fact tests
- `lua/lalin/code_kernel_plan.lua` - new Kernel planning phase
- `tests/test_code_kernel_plan.lua` - Kernel planning tests
- `lua/lalin/kernel_validate.lua` - new tower validator
- `tests/test_kernel_validate.lua` - validation tests

## Verification
Ran:

```sh
luajit tests/test_schema_core.lua
luajit tests/test_tree_to_code.lua
luajit tests/test_code_flow_facts.lua
luajit tests/test_code_mem_facts.lua
luajit tests/test_code_kernel_plan.lua
luajit tests/test_kernel_validate.lua
```

All passed.

## Notes
- T007/T009 were blocked rather than partially implemented because they require broader vector/projection design decisions.
- `git status` shows unrelated existing `museum/gps.lua` submodule/modification; I did not touch it.
