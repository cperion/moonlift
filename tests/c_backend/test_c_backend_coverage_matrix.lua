package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("lalin.pvm")
local Schema = require("lalin.schema")
local Coverage = require("lalin.c_coverage")

local T = pvm.context(); Schema(T)

local VALID = Coverage.statuses()
assert(VALID.supported and VALID.phase_unreachable and VALID.language_rejected, "missing final C coverage status")
assert(VALID.backend_todo == nil, "backend_todo is not a valid final C coverage status")

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
    ["LalinType.TypeRef"] = sum_variants("LalinType", "TypeRef"),
    ["LalinType.ArrayLen"] = sum_variants("LalinType", "ArrayLen"),
    ["LalinType.Type"] = sum_variants("LalinType", "Type"),

    ["LalinTree.View"] = sum_variants("LalinTree", "View"),
    ["LalinTree.Domain"] = sum_variants("LalinTree", "Domain"),
    ["LalinTree.IndexBase"] = sum_variants("LalinTree", "IndexBase"),
    ["LalinTree.Place"] = sum_variants("LalinTree", "Place"),
    ["LalinTree.Expr"] = sum_variants("LalinTree", "Expr"),
    ["LalinTree.Stmt"] = sum_variants("LalinTree", "Stmt"),
    ["LalinTree.Func"] = sum_variants("LalinTree", "Func"),
    ["LalinTree.ExternFunc"] = sum_variants("LalinTree", "ExternFunc"),
    ["LalinTree.ConstItem"] = sum_variants("LalinTree", "ConstItem"),
    ["LalinTree.StaticItem"] = sum_variants("LalinTree", "StaticItem"),
    ["LalinTree.TypeDecl"] = sum_variants("LalinTree", "TypeDecl"),
    ["LalinTree.Item"] = sum_variants("LalinTree", "Item"),

    ["LalinTree.SwitchStmtArm"] = { SwitchStmtArm = true },
    ["LalinTree.SwitchExprArm"] = { SwitchExprArm = true },
    ["LalinTree.SwitchVariantStmtArm"] = { SwitchVariantStmtArm = true },
    ["LalinTree.SwitchVariantExprArm"] = { SwitchVariantExprArm = true },
    ["LalinTree.ControlProducts"] = {
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

    ["LalinCore.UnaryOp"] = sum_variants("LalinCore", "UnaryOp"),
    ["LalinCore.BinaryOp"] = sum_variants("LalinCore", "BinaryOp"),
    ["LalinCore.CmpOp"] = sum_variants("LalinCore", "CmpOp"),
    ["LalinCore.LogicOp"] = sum_variants("LalinCore", "LogicOp"),
    ["LalinCore.SurfaceCastOp"] = sum_variants("LalinCore", "SurfaceCastOp"),
    ["LalinCore.MachineCastOp"] = sum_variants("LalinCore", "MachineCastOp"),
    ["LalinCore.Intrinsic"] = sum_variants("LalinCore", "Intrinsic"),
    ["LalinCore.AtomicOrdering"] = sum_variants("LalinCore", "AtomicOrdering"),
    ["LalinCore.AtomicRmwOp"] = sum_variants("LalinCore", "AtomicRmwOp"),
}

local tables = Coverage.all_tables()

for sum_name, expected_variants in pairs(expected) do
    local actual = tables[sum_name]
    assert(actual ~= nil, "missing coverage table for " .. sum_name)
    for variant in pairs(expected_variants) do
        local c = actual[variant]
        assert(c ~= nil, "missing coverage classification for " .. sum_name .. "." .. variant)
        assert(VALID[c.status], "invalid final tree_to_code/code_validate/code_to_c coverage status for " .. sum_name .. "." .. variant .. ": " .. tostring(c.status))
        assert(type(c.section) == "string" and c.section ~= "", "missing section for " .. sum_name .. "." .. variant)
        assert(type(c.reason) == "string" and c.reason ~= "", "missing reason for " .. sum_name .. "." .. variant)
        if c.status ~= "supported" then
            assert(c.reason:match("%S"), "empty diagnostic reason for " .. sum_name .. "." .. variant)
        end
        assert(c.status ~= "backend_todo", "backend_todo is not allowed after the LalinCode C pipeline switch: " .. sum_name .. "." .. variant)
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
assert(Coverage.assert_known("LalinType.Type", "TScalar").status == "supported")

-- There is no relaxed/non-final mode: the LalinCode C pipeline must classify every
-- row as supported, phase_unreachable, or language_rejected.
io.write("lalin C backend coverage matrix ok\n")
