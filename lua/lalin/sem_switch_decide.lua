local function bind_context(T)
    local Tr = T.LalinTree

    local function append_key(keys, key)
        local out = {}
        for i = 1, #(keys or {}) do out[i] = keys[i] end
        out[#out + 1] = key
        return out
    end

    function Tr.SwitchKeyInt:sem_switch_initial_decision()
        return Tr.SwitchConstKeys({ self })
    end

    function Tr.SwitchKeyBool:sem_switch_initial_decision()
        return Tr.SwitchConstKeys({ self })
    end

    function Tr.SwitchKeyName:sem_switch_initial_decision()
        return Tr.SwitchConstKeys({ self })
    end

    function Tr.SwitchKeyExpr:sem_switch_initial_decision()
        return Tr.SwitchExprKeys({ self })
    end

    function Tr.SwitchKeyInt:sem_switch_after_const_keys(decision)
        return Tr.SwitchConstKeys(append_key(decision.keys, self))
    end

    function Tr.SwitchKeyBool:sem_switch_after_const_keys(decision)
        return Tr.SwitchConstKeys(append_key(decision.keys, self))
    end

    function Tr.SwitchKeyName:sem_switch_after_const_keys(decision)
        return Tr.SwitchConstKeys(append_key(decision.keys, self))
    end

    function Tr.SwitchKeyExpr:sem_switch_after_const_keys(decision)
        return Tr.SwitchCompareFallback(append_key(decision.keys, self), "mixed const and expression switch keys")
    end

    function Tr.SwitchKeyInt:sem_switch_after_expr_keys(decision)
        return Tr.SwitchCompareFallback(append_key(decision.keys, self), "mixed const and expression switch keys")
    end

    function Tr.SwitchKeyBool:sem_switch_after_expr_keys(decision)
        return Tr.SwitchCompareFallback(append_key(decision.keys, self), "mixed const and expression switch keys")
    end

    function Tr.SwitchKeyName:sem_switch_after_expr_keys(decision)
        return Tr.SwitchCompareFallback(append_key(decision.keys, self), "mixed const and expression switch keys")
    end

    function Tr.SwitchKeyExpr:sem_switch_after_expr_keys(decision)
        return Tr.SwitchExprKeys(append_key(decision.keys, self))
    end

    function Tr.SwitchKey:sem_switch_after_compare_fallback(decision)
        return Tr.SwitchCompareFallback(append_key(decision.keys, self), decision.reason)
    end

    function Tr.SwitchConstKeys:sem_switch_add_key(key)
        return key:sem_switch_after_const_keys(self)
    end

    function Tr.SwitchExprKeys:sem_switch_add_key(key)
        return key:sem_switch_after_expr_keys(self)
    end

    function Tr.SwitchCompareFallback:sem_switch_add_key(key)
        return key:sem_switch_after_compare_fallback(self)
    end

    function Tr.SwitchStmtArm:sem_switch_arm_key()
        return self.key
    end

    function Tr.SwitchExprArm:sem_switch_arm_key()
        return self.key
    end

    local function decide_keys(keys)
        local decision = nil
        for i = 1, #keys do
            decision = decision and decision:sem_switch_add_key(keys[i]) or keys[i]:sem_switch_initial_decision()
        end
        return decision or Tr.SwitchConstKeys({})
    end

    function Tr.StmtSwitch:sem_switch_decision()
        local keys = {}
        for i = 1, #self.arms do keys[#keys + 1] = self.arms[i]:sem_switch_arm_key() end
        return decide_keys(keys)
    end

    function Tr.ExprSwitch:sem_switch_decision()
        local keys = {}
        for i = 1, #self.arms do keys[#keys + 1] = self.arms[i]:sem_switch_arm_key() end
        return decide_keys(keys)
    end

    return {
        decide_keys = decide_keys,
        keys = function(keys) return decide_keys(keys) end,
        stmt = function(stmt) return stmt:sem_switch_decision() end,
        expr = function(expr) return expr:sem_switch_decision() end,
    }
end

return bind_context
