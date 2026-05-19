local pvm = require("moonlift.pvm")

local M = {}

function M.Define(T)
    local Sem = T.MoonSem
    local Tr = T.MoonTree

    local stmt_arm_key
    local expr_arm_key
    local decide_stmt_switch
    local decide_expr_switch

    local function key_kind(key)
        if key == "" then return "expr" end
        return "const"
    end

    stmt_arm_key = pvm.phase("moonlift_sem_stmt_switch_arm_key", {
        [Tr.SwitchStmtArm] = function(arm) return pvm.once(arm.raw_key) end,
    })

    expr_arm_key = pvm.phase("moonlift_sem_expr_switch_arm_key", {
        [Tr.SwitchExprArm] = function(arm) return pvm.once(arm.raw_key) end,
    })

    local function decide_keys(keys)
        local has_const = false
        local has_expr = false
        for i = 1, #keys do
            local kind = key_kind(keys[i])
            if kind == "const" then has_const = true end
            if kind == "expr" then has_expr = true end
        end
        if has_expr and has_const then
            return { kind = "compare_fallback", keys = keys, reason = "mixed const and expression switch keys" }
        end
        if has_expr then
            return { kind = "expr_keys", keys = keys }
        end
        return { kind = "const_keys", keys = keys }
    end

    decide_stmt_switch = pvm.phase("moonlift_sem_stmt_switch_decide", {
        [Tr.StmtSwitch] = function(stmt)
            local keys = {}
            for i = 1, #stmt.arms do keys[#keys + 1] = pvm.one(stmt_arm_key(stmt.arms[i])) end
            return pvm.once(decide_keys(keys))
        end,
    })

    decide_expr_switch = pvm.phase("moonlift_sem_expr_switch_decide", {
        [Tr.ExprSwitch] = function(expr)
            local keys = {}
            for i = 1, #expr.arms do keys[#keys + 1] = pvm.one(expr_arm_key(expr.arms[i])) end
            return pvm.once(decide_keys(keys))
        end,
    })

    return {
        key_kind = key_kind,
        decide_keys = decide_keys,
        decide_stmt_switch = decide_stmt_switch,
        decide_expr_switch = decide_expr_switch,
        keys = function(keys) return decide_keys(keys) end,
        stmt = function(stmt) return pvm.one(decide_stmt_switch(stmt)) end,
        expr = function(expr) return pvm.one(decide_expr_switch(expr)) end,
    }
end

return M
