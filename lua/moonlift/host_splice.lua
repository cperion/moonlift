-- host_splice.lua — single coercion point for splice-hole filling.
--
-- Turns Lua host values into MoonOpen.SlotBinding given a parser-determined
-- slot role.  This is the ONLY place that decides what a Lua value means for
-- a particular slot kind.
--
-- Patterns used:
--   pvm.classof(node) == SomeConcreteClass   -- ASDL class check (standard)
--   pvm.classof(node) ~= false               -- "is any ASDL node?"
--   duck-typing on well-known Lua fields      -- for host value types

local pvm = require("moonlift.pvm")

local M = {}

-- ── Classification ────────────────────────────────────────────────────────────

-- Return a human-readable kind string for error messages.
function M.kind_of(value)
    local tv = type(value)
    if tv ~= "table" and tv ~= "userdata" then return tv end
    local kind = rawget(value, "moonlift_quote_kind") or rawget(value, "kind")
    if kind then return kind end
    if type(value.as_type_value) == "function" then return "type_value" end
    if type(value.as_expr_value) == "function" then return "expr_value" end
    local cls = pvm.classof(value)
    if cls and cls.kind then return cls.kind end
    return "table"
end

-- ── Protocol helper ───────────────────────────────────────────────────────────

-- Ask a host value to splice itself into the given role.
-- Returns the role-specific result, or nil if the value has no protocol.
local function protocol(value, role, session, site)
    if (type(value) == "table" or type(value) == "userdata")
        and type(value.moonlift_splice) == "function" then
        return value:moonlift_splice(role, session, site)
    end
    return nil
end

-- ── Top-level dispatch ────────────────────────────────────────────────────────

-- Fill a parser-produced Slot sum wrapper with a Lua value.
function M.fill(session, slot, value, site, role, spread)
    local O = session.T.MoonOpen
    local cls = pvm.classof(slot)

    if role == "expr_list"  then return M.fill_expr_list(session, slot.slot, value, site) end
    if role == "type_list"  then return M.fill_type_list(session, slot.slot, value, site) end
    if role == "param_list" then return M.fill_param_list(session, slot.slot, value, site) end
    if role == "field_list" then return M.fill_field_list(session, slot.slot, value, site) end
    if role == "variant_list" then return M.fill_variant_list(session, slot.slot, value, site) end
    if role == "switch_stmt_arm_list" then return M.fill_switch_stmt_arm_list(session, slot.slot, value, site) end
    if role == "switch_expr_arm_list" then return M.fill_switch_expr_arm_list(session, slot.slot, value, site) end
    if role == "open_param_list" then return M.fill_open_param_list(session, slot.slot, value, site) end
    if role == "block_param_list" then return M.fill_block_param_list(session, slot.slot, value, site) end
    if role == "entry_param_list" then return M.fill_entry_param_list(session, slot.slot, value, site) end
    if role == "cont_slot_list" then return M.fill_cont_slot_list(session, slot.slot, value, site) end
    if role == "control_block_list" then return M.fill_control_block_list(session, slot.slot, value, site) end

    if cls == O.SlotType       then return M.fill_type(session, slot.slot, value, site) end
    if cls == O.SlotExpr       then return M.fill_expr(session, slot.slot, value, site) end
    if cls == O.SlotRegion     then return M.fill_region_body(session, slot.slot, value, site) end
    if cls == O.SlotRegionFrag then return M.fill_region_frag(session, slot.slot, value, site) end
    if cls == O.SlotExprFrag   then return M.fill_expr_frag(session, slot.slot, value, site) end
    if cls == O.SlotName       then return M.fill_name(session, slot.slot, value, site) end

    error((site or "splice") .. ": unsupported splice slot class " .. tostring(cls), 2)
end

-- ── Type slot ─────────────────────────────────────────────────────────────────

-- Accepted:  host TypeValue (as_type_value()), direct MoonType ASDL node.
-- Rejected:  bare string, number, boolean, nil, fragment values.
function M.fill_type(session, slot, value, site)
    local O = session.T.MoonOpen

    local ty = nil

    -- 1. Protocol method (TypeValue returns self.ty)
    local p = protocol(value, "type", session, site)
    if p ~= nil then ty = p end

    -- 2. Duck-typed: as_type_value()
    if not ty and type(value) == "table"
               and type(value.as_type_value) == "function" then
        ty = value:as_type_value().ty
    end

    -- 3. Raw ASDL type node passed directly (pvm.classof is non-false for ASDL nodes)
    if not ty and pvm.classof(value) ~= false then
        ty = value
    end

    if not ty then
        error((site or "splice") .. ": expected type value for @{} type splice, got " .. M.kind_of(value), 2)
    end

    local ok, binding = pcall(function()
        return O.SlotBinding(O.SlotType(slot), O.SlotValueType(ty))
    end)
    if ok then return binding end
    error((site or "splice") .. ": type value context mismatch; use the active session's moon.* API", 2)
end

-- ── Expression slot ───────────────────────────────────────────────────────────

-- Accepted:  number (int/float lit), boolean (bool lit), nil (nil lit),
--            string (string literal), host ExprValue (as_expr_value()),
--            direct Expr ASDL node.
function M.fill_expr(session, slot, value, site)
    local T  = session.T
    local C, Tr, O, B = T.MoonCore, T.MoonTree, T.MoonOpen, T.MoonBind

    local expr = nil

    -- 1. Protocol method
    local p = protocol(value, "expr", session, site)
    if p ~= nil then
        -- protocol may return an Expr ASDL node directly
        if pvm.classof(p) ~= false then
            expr = p
        else
            expr = p  -- let the SlotValueExpr constructor validate it
        end
    end

    -- 2. Primitive Lua values → literal ASDL nodes
    if not expr then
        local tv = type(value)
        if tv == "number" then
            if value == math.floor(value) and value >= -2^31 and value < 2^31 then
                expr = Tr.ExprLit(Tr.ExprSurface, C.LitInt(tostring(math.floor(value))))
            else
                expr = Tr.ExprLit(Tr.ExprSurface, C.LitFloat(tostring(value)))
            end
        elseif tv == "boolean" then
            expr = Tr.ExprLit(Tr.ExprSurface, C.LitBool(value))
        elseif tv == "nil" then
            expr = Tr.ExprLit(Tr.ExprSurface, C.LitNil)
        elseif tv == "string" then
            expr = Tr.ExprLit(Tr.ExprSurface, C.LitString(value))
        end
    end

    -- 3. Host ExprValue or direct ASDL Expr node.
    if not expr and type(value) == "table" then
        if type(value.as_expr_value) == "function" then
            expr = value:as_expr_value().expr
        elseif pvm.classof(value) ~= false then
            expr = value
        end
    end

    -- 4. Host function-like value → name reference expression.
    -- The function is registered in the ephemeral module by CallableFunc:__call,
    -- so the typechecker resolves this name reference.
    if not expr and type(value) == "table" then
        local kind = rawget(value, "kind")
        if kind == "func" or kind == "extern_func" then
            expr = Tr.ExprRef(Tr.ExprSurface, B.ValueRefName(rawget(value, "name") or "?"))
        end
    end

    if not expr then
        error((site or "splice") .. ": expected expression value for @{} expr splice, got " .. M.kind_of(value), 2)
    end

    return O.SlotBinding(O.SlotExpr(slot), O.SlotValueExpr(expr))
end

local function as_array(value, site, role)
    if type(value) ~= "table" then
        error((site or "splice") .. ": expected list for @{} " .. role .. " splice, got " .. M.kind_of(value), 3)
    end
    return value
end

local function coerce_type(session, value, site)
    local binding = M.fill_type(session, session.T.MoonOpen.TypeSlot("__tmp_type", "__tmp_type"), value, site)
    return binding.value.ty
end

local function coerce_expr(session, value, site)
    local binding = M.fill_expr(session, session.T.MoonOpen.ExprSlot("__tmp_expr", "__tmp_expr", nil), value, site)
    return binding.value.expr
end

function M.fill_expr_list(session, slot, value, site)
    local O = session.T.MoonOpen
    local xs = as_array(value, site, "expr_list")
    local out = {}
    for i = 1, #xs do out[#out + 1] = coerce_expr(session, xs[i], (site or "splice") .. "[" .. i .. "]") end
    return O.SlotBinding(O.SlotExpr(slot), O.SlotValueExprs(out))
end

function M.fill_type_list(session, slot, value, site)
    local O = session.T.MoonOpen
    local xs = as_array(value, site, "type_list")
    local out = {}
    for i = 1, #xs do out[#out + 1] = coerce_type(session, xs[i], (site or "splice") .. "[" .. i .. "]") end
    return O.SlotBinding(O.SlotType(slot), O.SlotValueTypes(out))
end

function M.fill_param_list(session, slot, value, site)
    local O, Ty = session.T.MoonOpen, session.T.MoonType
    local xs = as_array(value, site, "param_list")
    local out = {}
    for i = 1, #xs do
        local v = xs[i]
        if type(v) == "table" and v.decl and pvm.classof(v.decl) == Ty.Param then
            out[#out + 1] = v.decl
        elseif pvm.classof(v) == Ty.Param then
            out[#out + 1] = v
        else
            error((site or "splice") .. "[" .. i .. "]: expected parameter value, got " .. M.kind_of(v), 2)
        end
    end
    return O.SlotBinding(O.SlotRegion(slot), O.SlotValueParams(out))
end

function M.fill_field_list(session, slot, value, site)
    local O, Ty = session.T.MoonOpen, session.T.MoonType
    local xs = as_array(value, site, "field_list")
    local out = {}
    for i = 1, #xs do
        local v = xs[i]
        if type(v) == "table" and v.decl and pvm.classof(v.decl) == Ty.FieldDecl then
            out[#out + 1] = v.decl
        elseif pvm.classof(v) == Ty.FieldDecl then
            out[#out + 1] = v
        else
            error((site or "splice") .. "[" .. i .. "]: expected field value, got " .. M.kind_of(v), 2)
        end
    end
    return O.SlotBinding(O.SlotRegion(slot), O.SlotValueFields(out))
end

function M.fill_variant_list(session, slot, value, site)
    local O, Ty = session.T.MoonOpen, session.T.MoonType
    local xs = as_array(value, site, "variant_list")
    local out = {}
    for i = 1, #xs do
        local v = xs[i]
        if type(v) == "table" and v.decl and pvm.classof(v.decl) == Ty.VariantDecl then
            out[#out + 1] = v.decl
        elseif pvm.classof(v) == Ty.VariantDecl then
            out[#out + 1] = v
        else
            error((site or "splice") .. "[" .. i .. "]: expected variant value, got " .. M.kind_of(v), 2)
        end
    end
    return O.SlotBinding(O.SlotRegion(slot), O.SlotValueVariants(out))
end

local function as_switch_stmt_arm(session, v, site, i)
    local Tr = session.T.MoonTree
    if pvm.classof(v) == Tr.SwitchStmtArm then return v end
    if type(v) == "table" and v.raw_key ~= nil and type(v.body) == "table" then
        return Tr.SwitchStmtArm(tostring(v.raw_key), v.body)
    end
    error((site or "splice") .. "[" .. i .. "]: expected switch statement arm (SwitchStmtArm or {raw_key, body}), got " .. M.kind_of(v), 2)
end

local function as_switch_expr_arm(session, v, site, i)
    local Tr = session.T.MoonTree
    if pvm.classof(v) == Tr.SwitchExprArm then return v end
    if type(v) == "table" and v.raw_key ~= nil and type(v.body) == "table" then
        return Tr.SwitchExprArm(tostring(v.raw_key), v.body, v.result)
    end
    error((site or "splice") .. "[" .. i .. "]: expected switch expression arm (SwitchExprArm or {raw_key, body, result?}), got " .. M.kind_of(v), 2)
end

function M.fill_switch_stmt_arm_list(session, slot, value, site)
    local O = session.T.MoonOpen
    local xs = as_array(value, site, "switch_stmt_arm_list")
    local out = {}
    for i = 1, #xs do
        out[#out + 1] = as_switch_stmt_arm(session, xs[i], site, i)
    end
    return O.SlotBinding(O.SlotRegion(slot), O.SlotValueSwitchStmtArms(out))
end

function M.fill_switch_expr_arm_list(session, slot, value, site)
    local O = session.T.MoonOpen
    local xs = as_array(value, site, "switch_expr_arm_list")
    local out = {}
    for i = 1, #xs do
        out[#out + 1] = as_switch_expr_arm(session, xs[i], site, i)
    end
    return O.SlotBinding(O.SlotRegion(slot), O.SlotValueSwitchExprArms(out))
end

local function param_decl(session, v, site)
    local Ty = session.T.MoonType
    if type(v) == "table" and v.decl and pvm.classof(v.decl) == Ty.Param then return v.decl end
    if pvm.classof(v) == Ty.Param then return v end
    error((site or "splice") .. ": expected parameter value, got " .. M.kind_of(v), 3)
end

local function block_param_decl(session, v, site)
    local Tr = session.T.MoonTree
    if type(v) == "table" and v.decl and pvm.classof(v.decl) == Tr.BlockParam then return v.decl end
    if pvm.classof(v) == Tr.BlockParam then return v end
    local p = param_decl(session, v, site)
    return Tr.BlockParam(p.name, p.ty)
end

function M.fill_open_param_list(session, slot, value, site)
    local O = session.T.MoonOpen
    local xs = as_array(value, site, "open_param_list")
    local out = {}
    for i = 1, #xs do
        local v = xs[i]
        if pvm.classof(v) == O.OpenParam then
            out[#out + 1] = v
        else
            local p = param_decl(session, v, (site or "splice") .. "[" .. i .. "]")
            out[#out + 1] = O.OpenParam(session:symbol_key("open_param_splice", p.name), p.name, p.ty)
        end
    end
    return O.SlotBinding(O.SlotRegion(slot), O.SlotValueOpenParams(out))
end

function M.fill_block_param_list(session, slot, value, site)
    local O = session.T.MoonOpen
    local xs = as_array(value, site, "block_param_list")
    local out = {}
    for i = 1, #xs do out[#out + 1] = block_param_decl(session, xs[i], (site or "splice") .. "[" .. i .. "]") end
    return O.SlotBinding(O.SlotRegion(slot), O.SlotValueBlockParams(out))
end

function M.fill_entry_param_list(session, slot, value, site)
    local O, Tr = session.T.MoonOpen, session.T.MoonTree
    local xs = as_array(value, site, "entry_param_list")
    local out = {}
    for i = 1, #xs do
        local v = xs[i]
        if type(v) == "table" and v.decl and pvm.classof(v.decl) == Tr.EntryBlockParam then out[#out + 1] = v.decl
        elseif pvm.classof(v) == Tr.EntryBlockParam then out[#out + 1] = v
        else error((site or "splice") .. "[" .. i .. "]: expected entry parameter value, got " .. M.kind_of(v), 2) end
    end
    return O.SlotBinding(O.SlotRegion(slot), O.SlotValueEntryParams(out))
end

function M.fill_cont_slot_list(session, slot, value, site)
    local O = session.T.MoonOpen
    local xs = as_array(value, site, "cont_slot_list")
    local out = {}
    for i = 1, #xs do
        local v = xs[i]
        if pvm.classof(v) == O.ContSlot then
            out[#out + 1] = v
        elseif type(v) == "table" and v.name then
            local params = {}
            local src = v.block_params or (v.cont and v.cont.block_params) or v.params or {}
            for j = 1, #src do params[j] = block_param_decl(session, src[j], (site or "splice") .. "[" .. i .. "].params[" .. j .. "]") end
            out[#out + 1] = O.ContSlot(session:symbol_key("cont_splice", v.name), v.name, params)
        else
            error((site or "splice") .. "[" .. i .. "]: expected continuation slot or {name=..., params=...}, got " .. M.kind_of(v), 2)
        end
    end
    return O.SlotBinding(O.SlotRegion(slot), O.SlotValueContSlots(out))
end

function M.fill_control_block_list(session, slot, value, site)
    local O, Tr = session.T.MoonOpen, session.T.MoonTree
    local xs = as_array(value, site, "control_block_list")
    local out = {}
    for i = 1, #xs do
        local v = xs[i]
        if pvm.classof(v) == Tr.ControlBlock then out[#out + 1] = v
        elseif type(v) == "table" and v.kind == "block" and v.label then out[#out + 1] = Tr.ControlBlock(v.label, v.params or {}, v.body or {})
        else error((site or "splice") .. "[" .. i .. "]: expected control block value, got " .. M.kind_of(v), 2) end
    end
    return O.SlotBinding(O.SlotRegion(slot), O.SlotValueControlBlocks(out))
end

-- ── Region body slot (inline statement list) ──────────────────────────────────

function M.fill_region_body(session, slot, value, site)
    local O = session.T.MoonOpen

    local stmts = nil

    local p = protocol(value, "region_body", session, site)
    if p ~= nil then stmts = p end

    if not stmts and type(value) == "table" then
        stmts = value
    end

    if not stmts then
        error((site or "splice") .. ": expected statement list for region_body splice, got " .. M.kind_of(value), 2)
    end

    return O.SlotBinding(O.SlotRegion(slot), O.SlotValueRegion(stmts))
end

-- ── Region fragment slot (emit @{frag}(...) target) ───────────────────────────

-- Accepted:  canonical RegionFragValue, direct MoonOpen.RegionFrag ASDL node.
function M.fill_region_frag(session, slot, value, site)
    local O = session.T.MoonOpen

    local frag = nil

    local p = protocol(value, "region_frag", session, site)
    if p ~= nil then frag = p end

    if not frag and type(value) == "table" then
        if pvm.classof(value) == O.RegionFrag then
            frag = value
        elseif rawget(value, "moonlift_quote_kind") == "region_frag"
            or rawget(value, "kind") == "region_frag" then
            frag = value.frag
        end
    end

    if not frag then
        error((site or "splice") .. ": expected region fragment for emit target splice, got " .. M.kind_of(value), 2)
    end

    return O.SlotBinding(O.SlotRegionFrag(slot), O.SlotValueRegionFrag(frag))
end

-- ── Expression fragment slot (emit expr @{frag}(...) target) ─────────────────

-- Accepted:  canonical ExprFragValue, direct MoonOpen.ExprFrag ASDL node.
function M.fill_expr_frag(session, slot, value, site)
    local O = session.T.MoonOpen

    local frag = nil

    local p = protocol(value, "expr_frag", session, site)
    if p ~= nil then frag = p end

    if not frag and type(value) == "table" then
        if pvm.classof(value) == O.ExprFrag then
            frag = value
        elseif rawget(value, "moonlift_quote_kind") == "expr_frag"
            or rawget(value, "kind") == "expr_frag" then
            frag = value.frag
        end
    end

    if not frag then
        error((site or "splice") .. ": expected expression fragment for emit-expr target splice, got " .. M.kind_of(value), 2)
    end

    return O.SlotBinding(O.SlotExprFrag(slot), O.SlotValueExprFrag(frag))
end

-- ── Name slot (identifier splice) ─────────────────────────────────────────────

local ident_pat = "^[_%a][_%w]*$"

-- Accepted:  plain Lua string that is a valid Moonlift identifier.
function M.fill_name(session, slot, value, site)
    local O = session.T.MoonOpen

    local name = nil

    local p = protocol(value, "name", session, site)
    if p ~= nil then name = tostring(p) end

    if not name and type(value) == "string" then name = value end

    if not name then
        error((site or "splice") .. ": expected identifier string for name splice, got " .. M.kind_of(value), 2)
    end
    if not name:match(ident_pat) then
        error((site or "splice") .. ": invalid Moonlift identifier: " .. string.format("%q", name), 2)
    end

    return O.SlotBinding(O.SlotName(slot), O.SlotValueName(name))
end

return M
