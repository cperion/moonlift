package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local Schema = require("moonlift.schema")
local Coverage = require("moonlift.c_coverage")

local T = pvm.context(); Schema.Define(T)

local VALID = Coverage.statuses()

local function class_name(cls)
    return tostring(cls):match("Class%([^%.]+%.([^%)]+)%)") or tostring(cls)
end

local function sorted_keys(t)
    local keys = {}
    for k in pairs(t) do keys[#keys + 1] = k end
    table.sort(keys)
    return keys
end

local function sum_variants(mod_name, sum_name)
    local sum = T[mod_name][sum_name]
    assert(sum and sum.members, "missing sum " .. mod_name .. "." .. sum_name)
    local variants = {}
    for cls in pairs(sum.members) do
        if cls.kind then
            variants[cls.kind] = true
        end
    end
    return variants
end

local expected = {
    ["MoonType.TypeRef"] = sum_variants("MoonType", "TypeRef"),
    ["MoonType.ArrayLen"] = sum_variants("MoonType", "ArrayLen"),
    ["MoonType.Type"] = sum_variants("MoonType", "Type"),

    ["MoonTree.View"] = sum_variants("MoonTree", "View"),
    ["MoonTree.Domain"] = sum_variants("MoonTree", "Domain"),
    ["MoonTree.IndexBase"] = sum_variants("MoonTree", "IndexBase"),
    ["MoonTree.Place"] = sum_variants("MoonTree", "Place"),
    ["MoonTree.Expr"] = sum_variants("MoonTree", "Expr"),
    ["MoonTree.Stmt"] = sum_variants("MoonTree", "Stmt"),
    ["MoonTree.Func"] = sum_variants("MoonTree", "Func"),
    ["MoonTree.ExternFunc"] = sum_variants("MoonTree", "ExternFunc"),
    ["MoonTree.ConstItem"] = sum_variants("MoonTree", "ConstItem"),
    ["MoonTree.StaticItem"] = sum_variants("MoonTree", "StaticItem"),
    ["MoonTree.TypeDecl"] = sum_variants("MoonTree", "TypeDecl"),
    ["MoonTree.Item"] = sum_variants("MoonTree", "Item"),

    ["MoonTree.SwitchStmtArm"] = { SwitchStmtArm = true },
    ["MoonTree.SwitchExprArm"] = { SwitchExprArm = true },
    ["MoonTree.SwitchVariantStmtArm"] = { SwitchVariantStmtArm = true },
    ["MoonTree.SwitchVariantExprArm"] = { SwitchVariantExprArm = true },
    ["MoonTree.ControlProducts"] = {
        VariantBind = true,
        BlockLabel = true,
        BlockParam = true,
        EntryBlockParam = true,
        JumpArg = true,
        EntryControlBlock = true,
        ControlBlock = true,
        ControlStmtRegion = true,
        ControlExprRegion = true,
        ControlVariantArmFact = true,
        ImportItem = true,
        DataItem = true,
    },

    ["MoonCore.UnaryOp"] = sum_variants("MoonCore", "UnaryOp"),
    ["MoonCore.BinaryOp"] = sum_variants("MoonCore", "BinaryOp"),
    ["MoonCore.CmpOp"] = sum_variants("MoonCore", "CmpOp"),
    ["MoonCore.LogicOp"] = sum_variants("MoonCore", "LogicOp"),
    ["MoonCore.SurfaceCastOp"] = sum_variants("MoonCore", "SurfaceCastOp"),
    ["MoonCore.MachineCastOp"] = sum_variants("MoonCore", "MachineCastOp"),
    ["MoonCore.Intrinsic"] = sum_variants("MoonCore", "Intrinsic"),
    ["MoonCore.AtomicOrdering"] = sum_variants("MoonCore", "AtomicOrdering"),
    ["MoonCore.AtomicRmwOp"] = sum_variants("MoonCore", "AtomicRmwOp"),
}

local tables = Coverage.all_tables()
local backend_todos = {}

for sum_name, expected_variants in pairs(expected) do
    local actual = tables[sum_name]
    assert(actual ~= nil, "missing coverage table for " .. sum_name)
    for variant in pairs(expected_variants) do
        local c = actual[variant]
        assert(c ~= nil, "missing coverage classification for " .. sum_name .. "." .. variant)
        assert(VALID[c.status], "invalid status for " .. sum_name .. "." .. variant .. ": " .. tostring(c.status))
        assert(type(c.section) == "string" and c.section ~= "", "missing section for " .. sum_name .. "." .. variant)
        assert(type(c.reason) == "string" and c.reason ~= "", "missing reason for " .. sum_name .. "." .. variant)
        if c.status ~= "supported" then
            assert(c.reason:match("%S"), "empty diagnostic reason for " .. sum_name .. "." .. variant)
        end
        if c.status == "backend_todo" then
            backend_todos[#backend_todos + 1] = sum_name .. "." .. variant .. " — " .. c.reason
        end
    end
    for variant in pairs(actual) do
        assert(expected_variants[variant], "stale extra coverage classification for " .. sum_name .. "." .. variant)
    end
end

for sum_name in pairs(tables) do
    assert(expected[sum_name], "stale extra coverage table " .. sum_name)
end

-- Spot-check short-name aliases and assert_known API used by validators/lowering.
assert(Coverage.classification("Expr", "ExprDot").status == "phase_unreachable")
assert(Coverage.assert_known("MoonType.Type", "TScalar").status == "supported")

local final_mode = os.getenv("MOONLIFT_C_BACKEND_FINAL") == "1" or arg[1] == "--final-complete"
if final_mode then
    table.sort(backend_todos)
    assert(#backend_todos == 0, "C backend final-completion mode found backend_todo rows:\n" .. table.concat(backend_todos, "\n"))
elseif #backend_todos > 0 then
    io.write("moonlift C backend coverage matrix has ", tostring(#backend_todos), " backend_todo row(s); run with MOONLIFT_C_BACKEND_FINAL=1 or --final-complete for the final completion gate\n")
end

io.write("moonlift C backend coverage matrix ok\n")
