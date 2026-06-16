package.path = './?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;' .. package.path

local ffi = require('ffi')
local pvm = require('moonlift.pvm')
local Schema = require('moonlift.schema')
local T = pvm.context(); Schema.Define(T)

local Parse = require('moonlift.parse').Define(T)
local OpenFacts = require('moonlift.open_facts').Define(T)
local OpenValidate = require('moonlift.open_validate').Define(T)
local OpenExpand = require('moonlift.open_expand').Define(T)
local ClosureConvert = require('moonlift.closure_convert').Define(T)
local Typecheck = require('moonlift.tree_typecheck').Define(T)
local Layout = require('moonlift.sem_layout_resolve').Define(T)
local TreeToCode = require('moonlift.tree_to_code').Define(T)
local CodeValidate = require('moonlift.code_validate').Define(T)
local CodeGraph = require('moonlift.code_graph').Define(T)
local CodeFlowFacts = require('moonlift.code_flow_facts').Define(T)
local CodeValueFacts = require('moonlift.code_value_facts').Define(T)
local CodeMemFacts = require('moonlift.code_mem_facts').Define(T)
local CodeEffectFacts = require('moonlift.code_effect_facts').Define(T)
local CodeKernelPlan = require('moonlift.code_kernel_plan').Define(T)
local CodeSchedulePlan = require('moonlift.code_schedule_plan').Define(T)
local CodeLowerPlan = require('moonlift.code_lower_plan').Define(T)
local LowerToBack = require('moonlift.lower_to_back').Define(T)
local CodeToBack = require('moonlift.code_to_back').Define(T)
local KernelValidate = require('moonlift.kernel_validate').Define(T)
local BackValidate = require('moonlift.back_validate').Define(T)
local BackJit = require('moonlift.back_jit').Define(T)

local Code = T.MoonCode
local Lower = T.MoonLower
local Kernel = T.MoonKernel
local Mem = T.MoonMem
local Back = T.MoonBack

local function assert_no_issues(label, issues) assert(#issues == 0, label .. ' expected no issues, got ' .. tostring(#issues)) end
local function lower_all(src)
    local parsed = Parse.parse_module(src); assert_no_issues('parse', parsed.issues)
    local expanded = OpenExpand.module(parsed.module); assert_no_issues('open', OpenValidate.validate(OpenFacts.facts_of_module(expanded)).issues)
    local checked = Typecheck.check_module(ClosureConvert.module(expanded)); assert_no_issues('typecheck', checked.issues)
    local code, contracts = TreeToCode.module_with_contracts(Layout.module(checked.module)); assert_no_issues('code', CodeValidate.validate(code).issues)
    local graph = CodeGraph.graph(code)
    local flow = CodeFlowFacts.facts(code, graph)
    local value = CodeValueFacts.facts(code, graph, flow)
    local mem = CodeMemFacts.semantic_facts(code, graph, flow, value, contracts)
    local effect = CodeEffectFacts.facts(code, graph, mem, contracts)
    local kernels = CodeKernelPlan.plan(code, graph, flow, value, mem, effect)
    local schedules = CodeSchedulePlan.plan(code, kernels, flow, value, mem, effect)
    local lower = CodeLowerPlan.plan(code, graph, kernels, schedules, Lower.LowerTargetBack)
    return code, graph, flow, value, mem, effect, kernels, schedules, lower
end

local code, graph, flow, value, mem, effect, kernels, schedules, lower = lower_all([[
func mixed(noalias dst: ptr(i32), readonly src: ptr(i32), n: i32): i32
    requires bounds(dst, n)
    requires bounds(src, n)
    requires disjoint(dst, src)
    let sum: i32 = block copy_loop(i: i32 = 0, acc: i32 = 0): i32
        if i >= n then yield acc end
        let x: i32 = src[i]
        dst[i] = x
        jump copy_loop(i = i + 1, acc = acc + x)
    end
    return block code_loop(k: i32 = 0): i32
        if k >= 1 then yield sum end
        jump code_loop(k = k + 1)
    end
end
]])
local saw_semantic, saw_code, semantic_has_fallback = false, false, false
for _, fp in ipairs(lower.funcs or {}) do
    for _, fragment in ipairs(fp.fragments or {}) do
        local cls = pvm.classof(fragment.strategy)
        if cls == Lower.LowerStrategyKernel or cls == Lower.LowerStrategyClosedForm then
            saw_semantic = true
            for _, issue in ipairs(fragment.issues or {}) do if pvm.classof(issue)==Lower.LowerIssueFallback then semantic_has_fallback=true end end
        elseif cls == Lower.LowerStrategyCode then
            saw_code = true
        end
    end
end
assert(saw_semantic, 'supported copy loop should lower as a semantic Kernel/ClosedForm fragment')
assert(saw_code, 'mixed function should preserve Code fragments for prologue/epilogue or unsupported loop')
assert(not semantic_has_fallback, 'supported semantic fragment must not carry LowerIssueFallback')
assert_no_issues('semantic validate', KernelValidate.validate(code,graph,flow,value,mem,effect,kernels,schedules,lower).issues)
local program = LowerToBack.module(code, graph, flow, value, mem, effect, kernels, schedules, lower)
assert_no_issues('back', BackValidate.validate(program).issues)
local saw_load_metadata = false
for _, cmd in ipairs(program.cmds or {}) do
    if pvm.classof(cmd) == Back.CmdLoadInfo and pvm.classof(cmd.memory.trap) == Back.BackNonTrapping and pvm.classof(cmd.memory.alignment) == Back.BackAlignKnown and pvm.classof(cmd.memory.motion) == Back.BackCanMove then saw_load_metadata = true end
end
assert(saw_load_metadata, 'lowered loads should consume MemBackendAccessInfo metadata')
local jit=BackJit.jit(); local artifact=jit:compile(program); local fn=ffi.cast('int32_t (*)(int32_t*, const int32_t*, intptr_t)', artifact:getpointer(Back.BackFuncId('mixed')))
local src=ffi.new('int32_t[5]',{10,20,30,40,50}); local dst=ffi.new('int32_t[5]',{0,0,0,0,0}); assert(fn(dst,src,5)==150); for i=0,4 do assert(dst[i]==src[i]) end; artifact:free()

-- View lowering smoke: projections come from explicit CodeInstViewMake descriptor components.
local origin = Code.CodeOriginGenerated('view smoke')
local i32 = Code.CodeTyInt(32, Code.CodeSigned)
local ptr_i32 = Code.CodeTyDataPtr(i32)
local sig = Code.CodeSigId('sig:view')
local fn_id = Code.CodeFuncId('fn:view_len')
local entry = Code.CodeBlockId('block:entry')
local p = Code.CodeValueId('v:p')
local len = Code.CodeValueId('v:len')
local stride = Code.CodeValueId('v:stride')
local view = Code.CodeValueId('v:view')
local out = Code.CodeValueId('v:out')
local view_module = Code.CodeModule(Code.CodeModuleId('module:view'), { Code.CodeSig(sig, { ptr_i32, Code.CodeTyIndex, Code.CodeTyIndex }, { Code.CodeTyIndex }) }, {}, {}, {}, {}, {
    Code.CodeFunc(fn_id, 'view_len', Code.CodeLinkageLocal, sig, { Code.CodeParam(p,'p',ptr_i32,origin), Code.CodeParam(len,'len',Code.CodeTyIndex,origin), Code.CodeParam(stride,'stride',Code.CodeTyIndex,origin) }, {}, entry, {
        Code.CodeBlock(entry, 'entry', {}, { Code.CodeInst(Code.CodeInstId('inst:view'), Code.CodeInstViewMake(view, i32, p, len, stride), origin), Code.CodeInst(Code.CodeInstId('inst:len'), Code.CodeInstViewLen(out, view), origin) }, Code.CodeTerm(Code.CodeTermId('term:return'), Code.CodeTermReturn({ out }), origin), origin),
    }, origin),
}, origin)
assert_no_issues('view code', CodeValidate.validate(view_module).issues)
assert_no_issues('view back', BackValidate.validate(CodeToBack.module(view_module, { validate = false })).issues)

local unsafe_code, unsafe_graph, unsafe_flow, unsafe_value, unsafe_mem, unsafe_effect, unsafe_kernels, unsafe_schedules, unsafe_lower = lower_all([[
func unsafe_load(src: ptr(i32), n: i32): i32
    return block loop(i: i32 = 0, acc: i32 = 0): i32
        if i >= n then yield acc end
        jump loop(i = i + 1, acc = acc + src[i])
    end
end
]])
local saw_unknown_extent=false; for _, object in ipairs(unsafe_mem.objects or {}) do if pvm.classof(object.extent)==Mem.MemExtentUnknown then saw_unknown_extent=true end end; assert(saw_unknown_extent)
local saw_kernel_no_plan, saw_lower_fallback=false,false
for _, plan in ipairs(unsafe_kernels.plans or {}) do if pvm.classof(plan)==Kernel.KernelNoPlan and pvm.classof(plan.subject)==Kernel.KernelSubjectLoop and #(plan.rejects or {})>0 then saw_kernel_no_plan=true end end
for _, fp in ipairs(unsafe_lower.funcs or {}) do for _, fr in ipairs(fp.fragments or {}) do for _, issue in ipairs(fr.issues or {}) do if pvm.classof(issue)==Lower.LowerIssueFallback then saw_lower_fallback=true end end end end
assert(saw_kernel_no_plan and saw_lower_fallback, 'removing bounds must cause explicit KernelNoPlan/LowerIssueFallback')

io.write('moonlift semantic_lowering_fragments ok\n')
