local pvm = require("moonlift.pvm")

local M = {}

function M.Define(T)
    local Sem = T.MoonSem
    local Tr = T.MoonTree

    local key_kind
    local stmt_arm_key
    local expr_arm_key
    local decide_keys
    local decide_stmt_switch
    local decide_expr_switch

    key_kind = pvm.phase("moon2_sem_switch_key_kind", {
        [Sem.SwitchKeyConst] = function() return pvm.once("const") end,
        [Sem.SwitchKeyRaw] = function() return pvm.once("const") end,
        [Sem.SwitchKeyExpr] = function() return pvm.once("expr") end,
    })

    stmt_arm_key = pvm.phase("moon2_sem_stmt_switch_arm_key", {
        [Tr.SwitchStmtArm] = function(arm) return pvm.once(arm.key) end,
    })

    expr_arm_key = pvm.phase("moon2_sem_expr_switch_arm_key", {
        [Tr.SwitchExprArm] = function(arm) return pvm.once(arm.key) end,
    })

    decide_keys = pvm.phase("moon2_sem_switch_decide_keys", {
        [Sem.SwitchKeySet] = function(set)
            local has_const = false
            local has_expr = false
            for i = 1, #set.keys do
                local kind = pvm.one(key_kind(set.keys[i]))
                if kind == "const" then has_const = true end
                if kind == "expr" then has_expr = true end
            end
            if has_expr and has_const then
                return pvm.once(Sem.SwitchDecisionCompareFallback(set.keys, "mixed const and expression switch keys"))
            end
            if has_expr then
                return pvm.once(Sem.SwitchDecisionExprKeys(set.keys))
            end
            return pvm.once(Sem.SwitchDecisionConstKeys(set.keys))
        end,
    })

    decide_stmt_switch = pvm.phase("moon2_sem_stmt_switch_decide", {
        [Tr.StmtSwitch] = function(stmt)
            local keys = {}
            for i = 1, #stmt.arms do keys[#keys + 1] = pvm.one(stmt_arm_key(stmt.arms[i])) end
            return decide_keys(Sem.SwitchKeySet(keys))
        end,
    })

    decide_expr_switch = pvm.phase("moon2_sem_expr_switch_decide", {
        [Tr.ExprSwitch] = function(expr)
            local keys = {}
            for i = 1, #expr.arms do keys[#keys + 1] = pvm.one(expr_arm_key(expr.arms[i])) end
            return decide_keys(Sem.SwitchKeySet(keys))
        end,
    })

    return {
        key_kind = key_kind,
        decide_keys = decide_keys,
        decide_stmt_switch = decide_stmt_switch,
        decide_expr_switch = decide_expr_switch,
        keys = function(keys) return pvm.one(decide_keys(Sem.SwitchKeySet(keys))) end,
        stmt = function(stmt) return pvm.one(decide_stmt_switch(stmt)) end,
        expr = function(expr) return pvm.one(decide_expr_switch(expr)) end,
    }
end

return M
