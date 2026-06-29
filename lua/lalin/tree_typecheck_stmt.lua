return function(T)
    local C = T.LalinCore
    local B = T.LalinBind
    local Ty = T.LalinType
    local Tr = T.LalinTree

    local function append_all(out, values)
        for i = 1, #(values or {}) do out[#out + 1] = values[i] end
    end

    local function type_eq(a, b)
        return a == b
    end

    local function check_expected(site, expected, actual, issues)
        if not type_eq(expected, actual) then issues[#issues + 1] = Tr.TypeIssueExpected(site, expected, actual) end
    end

    local function type_expr_expect(expr, input, expected)
        return expr:typecheck_tree_expr_expected(input:typecheck_tree_expected_expr_input(expected))
    end

    local function block_param_binding(region_id, label, param, index, class)
        return B.Binding(C.Id("control:param:" .. region_id .. ":" .. label.name .. ":" .. param.name), param.name, param.ty, class)
    end

    function Tr.EntryBlockParam:typecheck_tree_add_to_scope(input, region_id, label, index)
        local init = type_expr_expect(self.init, input, self.ty)
        local issues = {}
        append_all(issues, init.issues)
        check_expected("entry param", self.ty, init.ty, issues)
        local binding = block_param_binding(region_id, label, self, index, B.BindingClassEntryBlockParam(region_id, label.name, index))
        local scope = input.scope:typecheck_tree_add_value(B.ValueEntry(self.name, binding))
        return input:typecheck_tree_with_scope(scope), Tr.EntryBlockParam(self.name, self.ty, init.expr), issues
    end

    function Tr.BlockParam:typecheck_tree_add_to_scope(input, region_id, label, index)
        local binding = block_param_binding(region_id, label, self, index, B.BindingClassBlockParam(region_id, label.name, index))
        local scope = input.scope:typecheck_tree_add_value(B.ValueEntry(self.name, binding))
        return input:typecheck_tree_with_scope(scope), self, {}
    end

    function Tr.JumpArg:typecheck_tree_jump_arg(input)
        local value = self.value:typecheck_tree_expr(input:typecheck_tree_expr_input())
        return Tr.JumpArg(self.name, value.expr), value.issues
    end

    function Tr.StmtReturnValue:typecheck_tree_stmt(input)
        local value = type_expr_expect(self.value, input, input.return_ty)
        local issues = {}
        append_all(issues, value.issues)
        check_expected("return", input.return_ty, value.ty, issues)
        return Tr.TypeStmtResult(input, { Tr.StmtReturnValue(self.h, value.expr) }, issues)
    end

    function Tr.StmtReturnVoid:typecheck_tree_stmt(input)
        local issues = {}
        check_expected("return", input.return_ty, Ty.TScalar(C.ScalarVoid), issues)
        return Tr.TypeStmtResult(input, { Tr.StmtReturnVoid(self.h) }, issues)
    end

    function Tr.StmtExpr:typecheck_tree_stmt(input)
        local expr = self.expr:typecheck_tree_expr(input:typecheck_tree_expr_input())
        return Tr.TypeStmtResult(input, { Tr.StmtExpr(self.h, expr.expr) }, expr.issues)
    end

    function Tr.StmtLet:typecheck_tree_stmt(input)
        local init = type_expr_expect(self.init, input, self.binding.ty)
        local issues = {}
        append_all(issues, init.issues)
        check_expected("let", self.binding.ty, init.ty, issues)
        local scope = input.scope:typecheck_tree_add_value(B.ValueEntry(self.binding.name, self.binding))
        return Tr.TypeStmtResult(input:typecheck_tree_with_scope(scope), { Tr.StmtLet(self.h, self.binding, init.expr) }, issues)
    end

    function Tr.StmtVar:typecheck_tree_stmt(input)
        local init = type_expr_expect(self.init, input, self.binding.ty)
        local issues = {}
        append_all(issues, init.issues)
        check_expected("var", self.binding.ty, init.ty, issues)
        local scope = input.scope:typecheck_tree_add_value(B.ValueEntry(self.binding.name, self.binding))
        return Tr.TypeStmtResult(input:typecheck_tree_with_scope(scope), { Tr.StmtVar(self.h, self.binding, init.expr) }, issues)
    end

    function Tr.StmtSet:typecheck_tree_stmt(input)
        local place = self.place:typecheck_tree_place(input:typecheck_tree_place_input())
        local value = type_expr_expect(self.value, input, place.ty)
        local issues = {}
        append_all(issues, place.issues)
        append_all(issues, value.issues)
        check_expected("set", place.ty, value.ty, issues)
        return Tr.TypeStmtResult(input, { Tr.StmtSet(self.h, place.place, value.expr) }, issues)
    end

    function Tr.StmtAtomicStore:typecheck_tree_stmt(input)
        local addr = self.addr:typecheck_tree_expr(input:typecheck_tree_expr_input())
        local value = type_expr_expect(self.value, input, self.ty)
        local issues = {}
        append_all(issues, addr.issues)
        append_all(issues, value.issues)
        check_expected("atomic store", self.ty, value.ty, issues)
        return Tr.TypeStmtResult(input, { Tr.StmtAtomicStore(self.h, self.ty, addr.expr, value.expr, self.ordering) }, issues)
    end

    function Tr.StmtAtomicFence:typecheck_tree_stmt(input)
        return Tr.TypeStmtResult(input, { self }, {})
    end

    function Tr.StmtIf:typecheck_tree_stmt(input)
        local cond = type_expr_expect(self.cond, input, Ty.TScalar(C.ScalarBool))
        local issues = {}
        append_all(issues, cond.issues)
        check_expected("if condition", Ty.TScalar(C.ScalarBool), cond.ty, issues)
        local then_body = input:typecheck_tree_stmt_body(self.then_body)
        local else_body = input:typecheck_tree_stmt_body(self.else_body)
        append_all(issues, then_body.issues)
        append_all(issues, else_body.issues)
        return Tr.TypeStmtResult(input, { Tr.StmtIf(self.h, cond.expr, then_body.stmts, else_body.stmts) }, issues)
    end

    function Tr.StmtAssert:typecheck_tree_stmt(input)
        local cond = type_expr_expect(self.cond, input, Ty.TScalar(C.ScalarBool))
        local issues = {}
        append_all(issues, cond.issues)
        check_expected("assert condition", Ty.TScalar(C.ScalarBool), cond.ty, issues)
        return Tr.TypeStmtResult(input, { Tr.StmtAssert(self.h, cond.expr) }, issues)
    end

    function Tr.SwitchStmtArm:typecheck_tree_stmt_arm(input)
        local body = input:typecheck_tree_stmt_body(self.body)
        return Tr.SwitchStmtArm(self.key, body.stmts), body.issues
    end

    function Tr.SwitchVariantStmtArm:typecheck_tree_stmt_arm(input)
        local body = input:typecheck_tree_stmt_body(self.body)
        return Tr.SwitchVariantStmtArm(self.variant_name, self.binds, body.stmts), body.issues
    end

    function Tr.StmtSwitch:typecheck_tree_stmt(input)
        local value = self.value:typecheck_tree_expr(input:typecheck_tree_expr_input())
        local issues = {}
        append_all(issues, value.issues)
        local arms = {}
        for i = 1, #(self.arms or {}) do
            local arm, arm_issues = self.arms[i]:typecheck_tree_stmt_arm(input)
            arms[#arms + 1] = arm
            append_all(issues, arm_issues)
        end
        local variant_arms = {}
        for i = 1, #(self.variant_arms or {}) do
            local arm, arm_issues = self.variant_arms[i]:typecheck_tree_stmt_arm(input)
            variant_arms[#variant_arms + 1] = arm
            append_all(issues, arm_issues)
        end
        local default_body = input:typecheck_tree_stmt_body(self.default_body)
        append_all(issues, default_body.issues)
        return Tr.TypeStmtResult(input, { Tr.StmtSwitch(self.h, value.expr, arms, variant_arms, default_body.stmts) }, issues)
    end

    function Tr.StmtJump:typecheck_tree_stmt(input)
        local args = {}
        local issues = {}
        for i = 1, #(self.args or {}) do
            local arg, arg_issues = self.args[i]:typecheck_tree_jump_arg(input)
            args[#args + 1] = arg
            append_all(issues, arg_issues)
        end
        return Tr.TypeStmtResult(input, { Tr.StmtJump(self.h, self.target, args) }, issues)
    end

    function Tr.StmtJumpCont:typecheck_tree_stmt(input)
        local args = {}
        local issues = {}
        for i = 1, #(self.args or {}) do
            local arg, arg_issues = self.args[i]:typecheck_tree_jump_arg(input)
            args[#args + 1] = arg
            append_all(issues, arg_issues)
        end
        return Tr.TypeStmtResult(input, { Tr.StmtJumpCont(self.h, self.cont, args) }, issues)
    end

    function Tr.TypeYieldMode:typecheck_tree_yield_void(stmt, input)
        return Tr.TypeStmtResult(input, { stmt }, { Tr.TypeIssueUnexpectedYield("yield") })
    end

    function Tr.TypeYieldVoid:typecheck_tree_yield_void(stmt, input)
        return Tr.TypeStmtResult(input, { stmt }, {})
    end

    function Tr.TypeYieldMode:typecheck_tree_yield_value(stmt, input)
        local value = stmt.value:typecheck_tree_expr(input:typecheck_tree_expr_input())
        local issues = {}
        append_all(issues, value.issues)
        issues[#issues + 1] = Tr.TypeIssueUnexpectedYield("yield")
        return Tr.TypeStmtResult(input, { Tr.StmtYieldValue(stmt.h, value.expr) }, issues)
    end

    function Tr.TypeYieldValue:typecheck_tree_yield_value(stmt, input)
        local value = type_expr_expect(stmt.value, input, self.ty)
        local issues = {}
        append_all(issues, value.issues)
        check_expected("yield", self.ty, value.ty, issues)
        return Tr.TypeStmtResult(input, { Tr.StmtYieldValue(stmt.h, value.expr) }, issues)
    end

    function Tr.StmtYieldVoid:typecheck_tree_stmt(input)
        return input.yield:typecheck_tree_yield_void(self, input)
    end

    function Tr.StmtYieldValue:typecheck_tree_stmt(input)
        return input.yield:typecheck_tree_yield_value(self, input)
    end

    function Tr.EntryControlBlock:typecheck_tree_control_entry(input)
        local stmt_input = input.stmt
        local params = {}
        local issues = {}
        for i = 1, #(self.params or {}) do
            local next_input, param, param_issues = self.params[i]:typecheck_tree_add_to_scope(stmt_input, input.region_id, self.label, i)
            stmt_input = next_input
            params[#params + 1] = param
            append_all(issues, param_issues)
        end
        local body = stmt_input:typecheck_tree_stmt_body(self.body)
        append_all(issues, body.issues)
        return Tr.EntryControlBlock(self.label, params, body.stmts), issues
    end

    function Tr.ControlBlock:typecheck_tree_control_block(input)
        local stmt_input = input.stmt
        local params = {}
        local issues = {}
        for i = 1, #(self.params or {}) do
            local next_input, param, param_issues = self.params[i]:typecheck_tree_add_to_scope(stmt_input, input.region_id, self.label, i)
            stmt_input = next_input
            params[#params + 1] = param
            append_all(issues, param_issues)
        end
        local body = stmt_input:typecheck_tree_stmt_body(self.body)
        append_all(issues, body.issues)
        return Tr.ControlBlock(self.label, params, body.stmts), issues
    end

    function Tr.ControlStmtRegion:typecheck_tree_control_stmt_region(input)
        local control_input = Tr.TypeControlInput(input.stmt, self.region_id)
        local entry, entry_issues = self.entry:typecheck_tree_control_entry(control_input)
        local issues = {}
        append_all(issues, entry_issues)
        local blocks = {}
        for i = 1, #(self.blocks or {}) do
            local block, block_issues = self.blocks[i]:typecheck_tree_control_block(control_input)
            blocks[#blocks + 1] = block
            append_all(issues, block_issues)
        end
        return Tr.TypeControlStmtRegionResult(Tr.ControlStmtRegion(self.region_id, entry, blocks), issues)
    end

    function Tr.ControlExprRegion:typecheck_tree_control_expr_region(input)
        local control_input = Tr.TypeControlInput(input.stmt, self.region_id)
        local entry, entry_issues = self.entry:typecheck_tree_control_entry(control_input)
        local issues = {}
        append_all(issues, entry_issues)
        local blocks = {}
        for i = 1, #(self.blocks or {}) do
            local block, block_issues = self.blocks[i]:typecheck_tree_control_block(control_input)
            blocks[#blocks + 1] = block
            append_all(issues, block_issues)
        end
        return Tr.TypeControlExprRegionResult(Tr.ControlExprRegion(self.region_id, self.result_ty, entry, blocks), issues)
    end

    function Tr.StmtControl:typecheck_tree_stmt(input)
        local region = self.region:typecheck_tree_control_stmt_region(Tr.TypeControlInput(input, self.region.region_id))
        local issues = {}
        append_all(issues, region.issues)
        return Tr.TypeStmtResult(input, { Tr.StmtControl(self.h, region.region) }, issues)
    end

    function Tr.StmtTrap:typecheck_tree_stmt(input)
        return Tr.TypeStmtResult(input, { self }, {})
    end

    function Tr.TypeStmtInput:typecheck_tree_stmt_body(stmts)
        local state = self
        local out = {}
        local issues = {}
        for i = 1, #(stmts or {}) do
            local r = stmts[i]:typecheck_tree_stmt(state)
            state = r.state
            append_all(out, r.stmts)
            append_all(issues, r.issues)
        end
        return Tr.TypeStmtResult(state, out, issues)
    end
end
