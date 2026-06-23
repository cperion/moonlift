package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local Schema = require("moonlift.schema")
local T = pvm.context(); Schema(T)

local Core = T.MoonCore
local Ty = T.MoonType
local Tr = T.MoonTree
local Open = T.MoonOpen
local Bn = T.MoonBind
local C = T.MoonC
local CodeType = require("moonlift.code_type")(T)
local Helpers = require("moonlift.c_helpers")(T)
local Validate = require("moonlift.c_validate")(T)

local i32_ty = Ty.TScalar(Core.ScalarI32)
local cctx = { target = CodeType.default_target({}), layout_env = nil, diagnostics = {}, globals = {}, global_types = {}, global_ids = {}, env = {}, locals = {}, local_types = {}, local_storage = {}, helpers = {}, helpers_by_id = {}, helper_order = {}, sigs = {}, sig_order = {}, types = {}, type_decls_by_id = {} }

local function must_fail(label, fn, pattern)
    local ok, err = pcall(fn)
    assert(not ok, label .. " unexpectedly succeeded")
    err = tostring(err)
    if pattern then assert(err:match(pattern), label .. " error did not match " .. pattern .. ": " .. err) end
end

must_fail("TSlot projection", function()
    CodeType.type_to_code(Ty.TSlot(Open.TypeSlot("T", "T")), cctx)
end, "slot")

local i32 = C.CBackendScalar(Core.ScalarI32)
local access = C.CBackendMemoryAccess(i32, 4, C.CBackendMayTrap, true, Core.AtomicSeqCst)
local atomic = C.CBackendHelperUse(Helpers.helper_id(C.CBackendHelperAtomicLoad(access)), C.CBackendHelperAtomicLoad(access))
local report = Validate.validate(C.CBackendUnit("m", CodeType.default_target({ dialect = "c99" }), {}, {}, {}, {}, { atomic }, {}))
local saw_atomic_feature = false
for i = 1, #report.issues do if pvm.classof(report.issues[i]) == C.CBackendIssueInvalidTargetFeature then saw_atomic_feature = true end end
assert(saw_atomic_feature, "atomics without C11 target support should be diagnosed")
assert(package.loaded["moonlift.tree_to_c"] == nil)
assert(package.loaded["moonlift.c_places"] == nil)

io.write("moonlift c_backend_negative ok\n")
