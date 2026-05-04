local M = {}

local EntryParamValue = {}
EntryParamValue.__index = EntryParamValue

local ContValue = {}
ContValue.__index = ContValue

local BlockValue = {}
BlockValue.__index = BlockValue

local RegionFragValue = {}
RegionFragValue.__index = RegionFragValue

local RegionBuilder = {}
RegionBuilder.__index = RegionBuilder

local BlockBuilder = {}
BlockBuilder.__index = BlockBuilder

local function assert_name(name, site)
    assert(type(name) == "string" and name:match("^[_%a][_%w]*$"), site .. " expects an identifier")
end

function RegionFragValue:moonlift_splice_source()
    return self.name
end

function RegionFragValue:__tostring()
    return "MoonRegionFragValue(" .. self.name .. ")"
end

local function ordered_pairs_from_map(map)
    local keys = {}
    for k in pairs(map or {}) do keys[#keys + 1] = k end
    table.sort(keys)
    local i = 0
    return function()
        i = i + 1
        local k = keys[i]
        if k ~= nil then return k, map[k] end
    end
end

function M.Install(api, session)
    local T = session.T
    local C, Ty, B, O, Sem, Tr = T.MoonCore, T.MoonType, T.MoonBind, T.MoonOpen, T.MoonSem, T.MoonTree

    local function as_param(v, site)
        if type(v) == "table" and getmetatable(v) == api.ParamValue then return v end
        error((site or "expected param value") .. ": got " .. type(v), 3)
    end

    local function as_entry_param(v, site)
        if type(v) == "table" and getmetatable(v) == EntryParamValue then return v end
        error((site or "expected entry param value") .. ": got " .. type(v), 3)
    end

    local function jump_args(args)
        local out = {}
        for name, expr in ordered_pairs_from_map(args or {}) do
            out[#out + 1] = Tr.JumpArg(name, api.as_moonlift_expr(expr, "jump arg expects expression value"))
        end
        return out
    end

    local function switch_key(value)
        local mt = type(value) == "table" and getmetatable(value) or nil
        local cls = mt and mt.__class or nil
        if cls == Sem.SwitchKeyRaw or cls == Sem.SwitchKeyConst or cls == Sem.SwitchKeyExpr then return value end
        if type(value) == "number" or type(value) == "string" then return Sem.SwitchKeyRaw(tostring(value)) end
        if type(value) == "boolean" then return Sem.SwitchKeyRaw(value and "1" or "0") end
        if type(value) == "table" and type(value.as_expr_value) == "function" then
            return Sem.SwitchKeyExpr(value:as_expr_value().expr)
        end
        error("switch key expects raw number/string/boolean, SwitchKey, or expression value", 3)
    end

    local function binding_extra_for_type(tv)
        local extra = {}
        if tv.pointee then extra.pointee_type = tv.pointee; extra.element_type = tv.pointee end
        if tv.element then extra.element_type = tv.element end
        return extra
    end

    local function copy_bindings(src)
        local out = {}
        for k, v in pairs(src or {}) do out[k] = v end
        return out
    end

    local function block_param_expr(region_id, label, param, index, is_entry)
        local class = is_entry and B.BindingClassEntryBlockParam(region_id, label.name, index) or B.BindingClassBlockParam(region_id, label.name, index)
        local binding = B.Binding(C.Id("control:param:" .. region_id .. ":" .. label.name .. ":" .. param.name), param.name, param.ty, class)
        local tv = api.type_from_asdl(param.ty, param.name)
        return api.expr_ref(binding, tv, param.name, binding_extra_for_type(tv))
    end

    local function child_block_builder(parent)
        return setmetatable({ region = parent.region, block = parent.block, body = {}, bindings = copy_bindings(parent.bindings) }, BlockBuilder)
    end

    local function make_block_builder(region, block_value, params, is_entry)
        local bindings = copy_bindings(region.bindings)
        local label = block_value.label
        for i = 1, #params do
            bindings[params[i].name] = block_param_expr(region.region_id, label, params[i], i, is_entry)
        end
        return setmetatable({ region = region, block = block_value, body = {}, bindings = bindings }, BlockBuilder)
    end

    function api.entry_param(name, ty, init)
        assert_name(name, "entry_param")
        local tv = api.as_type_value(ty, "entry_param expects type value")
        local e = api.as_expr_value(init, "entry_param expects init expression")
        return setmetatable({ kind = "entry_param", name = name, type = tv, init = e, decl = Tr.EntryBlockParam(name, tv.ty, e.expr) }, EntryParamValue)
    end

    function api.cont(params)
        params = params or {}
        local block_params = {}
        for i = 1, #params do
            local p = as_param(params[i], "cont param")
            block_params[i] = Tr.BlockParam(p.name, p.type.ty)
        end
        return setmetatable({ kind = "cont", params = params, block_params = block_params }, ContValue)
    end

    function BlockBuilder:param(name)
        local v = self.bindings[name]
        assert(v ~= nil, "unknown block binding: " .. tostring(name))
        return v
    end

    function BlockBuilder:emit_stmt(stmt)
        self.body[#self.body + 1] = stmt
        return stmt
    end

    function BlockBuilder:expr(expr)
        local e = api.as_expr_value(expr, "expr statement expects expression value")
        return self:emit_stmt(Tr.StmtExpr(Tr.StmtSurface, e.expr))
    end

    function BlockBuilder:return_(expr)
        if expr == nil then return self:emit_stmt(Tr.StmtReturnVoid(Tr.StmtSurface)) end
        return self:emit_stmt(Tr.StmtReturnValue(Tr.StmtSurface, api.as_moonlift_expr(expr, "return expects expression")))
    end

    function BlockBuilder:yield_(expr)
        if expr == nil then return self:emit_stmt(Tr.StmtYieldVoid(Tr.StmtSurface)) end
        return self:emit_stmt(Tr.StmtYieldValue(Tr.StmtSurface, api.as_moonlift_expr(expr, "yield expects expression")))
    end

    function BlockBuilder:jump(target, args)
        if type(target) == "table" and getmetatable(target) == BlockValue then
            return self:emit_stmt(Tr.StmtJump(Tr.StmtSurface, target.label, jump_args(args)))
        elseif type(target) == "table" and getmetatable(target) == ContValue then
            assert(target.slot ~= nil, "cannot jump to continuation value outside a region fragment")
            return self:emit_stmt(Tr.StmtJumpCont(Tr.StmtSurface, target.slot, jump_args(args)))
        end
        error("jump target must be a block or continuation value", 2)
    end

    local function merge_region_dep(deps, fragment)
        if deps == nil or fragment == nil then return end
        deps.region_frags[fragment.name] = fragment
        local fdeps = fragment.deps
        if fdeps and fdeps.region_frags then
            for k, v in pairs(fdeps.region_frags) do deps.region_frags[k] = v end
        end
        if fdeps and fdeps.expr_frags then
            for k, v in pairs(fdeps.expr_frags) do deps.expr_frags[k] = v end
        end
    end

    function BlockBuilder:emit(fragment, runtime_args, fills)
        assert(type(fragment) == "table" and (getmetatable(fragment) == RegionFragValue or getmetatable(fragment) == api.CanonicalRegionFragValue), "emit expects a region fragment value")
        merge_region_dep(self.region.deps, fragment)
        local args = {}
        for i = 1, #(runtime_args or {}) do args[i] = api.as_moonlift_expr(runtime_args[i], "emit runtime arg expects expression") end
        local fill_values = {}
        for name, target in ordered_pairs_from_map(fills or {}) do
            local cont = fragment.conts[name]
            if cont == nil then api.raise_host_issue(session.T.MoonHost.HostIssueInvalidEmitFill(fragment.name, tostring(name))) end
            if type(target) == "table" and getmetatable(target) == BlockValue then
                fill_values[#fill_values + 1] = O.ContBinding(name, O.ContTargetLabel(target.label))
            elseif type(target) == "table" and getmetatable(target) == ContValue and target.slot ~= nil then
                fill_values[#fill_values + 1] = O.ContBinding(name, O.ContTargetSlot(target.slot))
            else
                error("continuation fill must be a block value or in-fragment continuation value", 2)
            end
        end
        for name in pairs(fragment.conts) do if (fills or {})[name] == nil then api.raise_host_issue(session.T.MoonHost.HostIssueMissingEmitFill(fragment.name, name)) end end
        return self:emit_stmt(Tr.StmtUseRegionFrag(Tr.StmtSurface, session:symbol_key("emit", fragment.name), fragment.name, args, {}, fill_values))
    end

    function BlockBuilder:if_(cond, then_fn, else_fn)
        local c = api.as_expr_value(cond, "if_ expects condition expression")
        assert(type(then_fn) == "function", "if_ expects then builder function")
        local tb = child_block_builder(self)
        then_fn(tb)
        local else_body = {}
        if else_fn ~= nil then
            assert(type(else_fn) == "function", "if_ expects else builder function")
            local eb = child_block_builder(self)
            else_fn(eb)
            else_body = eb.body
        end
        return self:emit_stmt(Tr.StmtIf(Tr.StmtSurface, c.expr, tb.body, else_body))
    end

    function BlockBuilder:switch_(value, arms, default_fn)
        local v = api.as_expr_value(value, "switch_ expects value expression")
        assert(type(arms) == "table", "switch_ expects an ordered arm list")
        local out_arms = {}
        for i = 1, #arms do
            local arm = arms[i]
            assert(type(arm) == "table", "switch_ arm must be a table")
            assert(arm.key ~= nil, "switch_ arm requires key")
            assert(type(arm.body) == "function", "switch_ arm requires body builder function")
            local ab = child_block_builder(self)
            arm.body(ab)
            out_arms[#out_arms + 1] = Tr.SwitchStmtArm(switch_key(arm.key), ab.body)
        end
        local default_body = {}
        if default_fn ~= nil then
            assert(type(default_fn) == "function", "switch_ default expects builder function")
            local db = child_block_builder(self)
            default_fn(db)
            default_body = db.body
        end
        return self:emit_stmt(Tr.StmtSwitch(Tr.StmtSurface, v.expr, out_arms, default_body))
    end

    function RegionBuilder:param(name)
        local v = self.bindings[name]
        assert(v ~= nil, "unknown region binding: " .. tostring(name))
        return v
    end

    function RegionBuilder:entry(name, entry_params, body_fn)
        assert(self.entry_block == nil, "region already has an entry block")
        assert_name(name, "entry")
        entry_params = entry_params or {}
        local decls = {}
        for i = 1, #entry_params do decls[i] = as_entry_param(entry_params[i], "entry param").decl end
        local block = setmetatable({ kind = "block", label = Tr.BlockLabel(name), params = decls, is_entry = true }, BlockValue)
        local bb = make_block_builder(self, block, decls, true)
        if body_fn then body_fn(bb) end
        block.body = bb.body
        self.entry_block = block
        return block
    end

    function RegionBuilder:block(name, params, body_fn)
        assert_name(name, "block")
        params = params or {}
        local decls = {}
        for i = 1, #params do local p = as_param(params[i], "block param"); decls[i] = Tr.BlockParam(p.name, p.type.ty) end
        local block = setmetatable({ kind = "block", label = Tr.BlockLabel(name), params = decls, is_entry = false, _region = self, _decl_params = decls }, BlockValue)
        local bb = make_block_builder(self, block, decls, false)
        if body_fn then body_fn(bb) end
        block.body = bb.body
        self.blocks[#self.blocks + 1] = block
        return block
    end

    function RegionBuilder:block_decl(name, params)
        assert_name(name, "block_decl")
        params = params or {}
        local decls = {}
        for i = 1, #params do local p = as_param(params[i], "block param"); decls[i] = Tr.BlockParam(p.name, p.type.ty) end
        local block = setmetatable({ kind = "block", label = Tr.BlockLabel(name), params = decls, is_entry = false, body = {}, _region = self, _decl_params = decls }, BlockValue)
        self.blocks[#self.blocks + 1] = block
        return block
    end

    function BlockValue:body_fn(body_fn)
        assert(self._region ~= nil, "block body cannot be assigned outside its region")
        assert(type(body_fn) == "function", "block body expects builder function")
        local bb = make_block_builder(self._region, self, self._decl_params or self.params or {}, false)
        body_fn(bb)
        self.body = bb.body
        return self
    end

    function BlockValue:body(body_fn)
        return self:body_fn(body_fn)
    end

    local function new_region_builder(kind, name, result_ty, bindings)
        return setmetatable({
            kind = kind,
            name = name,
            region_id = session:symbol_key("region", name),
            result = result_ty,
            bindings = copy_bindings(bindings),
            entry_block = nil,
            blocks = {},
            conts = {},
            deps = { region_frags = {}, expr_frags = {} },
        }, RegionBuilder)
    end

    local function entry_asdl(block)
        assert(block ~= nil, "control region requires an entry block")
        return Tr.EntryControlBlock(block.label, block.params, block.body or {})
    end

    local function blocks_asdl(blocks)
        local out = {}
        for i = 1, #blocks do out[i] = Tr.ControlBlock(blocks[i].label, blocks[i].params, blocks[i].body or {}) end
        return out
    end

    function api._build_control_expr_region(result_ty, bindings, builder_fn)
        local tv = api.as_type_value(result_ty, "region result type expected")
        local r = new_region_builder("expr_region", "expr", tv, bindings)
        builder_fn(r)
        return Tr.ExprControl(Tr.ExprSurface, Tr.ControlExprRegion(r.region_id, tv.ty, entry_asdl(r.entry_block), blocks_asdl(r.blocks)))
    end

    function api.region_frag(name, runtime_params, conts, builder_fn)
        assert_name(name, "region_frag")
        runtime_params = runtime_params or {}
        local open_params = {}
        local bindings = {}
        for i = 1, #runtime_params do
            local p = as_param(runtime_params[i], "region_frag runtime param")
            local op = O.OpenParam(session:symbol_key("open_param", name .. ":" .. p.name), p.name, p.type.ty)
            open_params[i] = op
            local binding = B.Binding(C.Id("open-param:" .. name .. ":" .. p.name), p.name, p.type.ty, B.BindingClassOpenParam(op))
            bindings[p.name] = api.expr_ref(binding, p.type, p.name)
        end
        local r = new_region_builder("region_frag", name, nil, bindings)
        local slots = {}
        local cont_values = {}
        for cname, cont in ordered_pairs_from_map(conts or {}) do
            assert(type(cont) == "table" and getmetatable(cont) == ContValue, "region_frag conts must be cont values")
            local slot = O.ContSlot(session:symbol_key("cont", name .. ":" .. cname), cname, cont.block_params)
            local cv = setmetatable({ kind = "cont", params = cont.params, block_params = cont.block_params, slot = slot }, ContValue)
            cont_values[cname] = cv
            slots[#slots + 1] = slot
        end
        r.conts = cont_values
        if builder_fn then builder_fn(r) end
        local frag = O.RegionFrag(name, open_params, slots, O.OpenSet({}, {}, {}, {}), entry_asdl(r.entry_block), blocks_asdl(r.blocks))
        session.T._moonlift_host_region_frags = session.T._moonlift_host_region_frags or {}
        session.T._moonlift_host_region_frags[name] = frag
        return setmetatable({ kind = "region_frag", moonlift_quote_kind = "region_frag", name = name, params = runtime_params, frag = frag, conts = cont_values, protocol = nil, deps = r.deps }, RegionFragValue)
    end

    -- Patch function builders after host_func_values has installed them.
    if api.FuncBuilder then
        function api.FuncBuilder:return_region(result_ty, builder_fn)
            local expr = api._build_control_expr_region(result_ty, self.bindings, builder_fn)
            return self:emit(T.MoonTree.StmtReturnValue(T.MoonTree.StmtSurface, expr))
        end
    end

    local block_methods = {}
    for k, v in pairs(BlockBuilder) do block_methods[k] = v end
    BlockBuilder.__index = function(self, key)
        local method = block_methods[key]
        if method ~= nil then return method end
        if key == "label" then return self.block.label end
        if key == "is_entry" then return self.block.is_entry end
        return self.bindings[key]
    end

    local region_methods = {}
    for k, v in pairs(RegionBuilder) do region_methods[k] = v end
    RegionBuilder.__index = function(self, key)
        local method = region_methods[key]
        if method ~= nil then return method end
        if key == "conts" then return rawget(self, "conts") end
        if key == "entry_block" then return rawget(self, "entry_block") end
        if key == "blocks" then return rawget(self, "blocks") end
        local binding = self.bindings[key]
        if binding ~= nil then return binding end
        local conts = rawget(self, "conts")
        return conts and conts[key] or nil
    end

    api.EntryParamValue = EntryParamValue
    api.ContValue = ContValue
    api.BlockValue = BlockValue
    api.RegionFragValue = RegionFragValue
    api.RegionBuilder = RegionBuilder
    api.BlockBuilder = BlockBuilder
end

return M
