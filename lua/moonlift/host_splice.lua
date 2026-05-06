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

-- True when value is a moon.source(...) explicit source escape.
function M.is_source(value)
    return type(value) == "table"
        and (rawget(value, "moonlift_quote_kind") == "source"
             or rawget(value, "kind") == "source")
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

-- Fill a slot with a Lua value.  `slot` may be a Slot sum wrapper (primary
-- path from the parser's splice_slots array) or a direct slot product
-- (convenience / test path).
function M.fill(session, slot, value, site)
    local O = session.T.MoonOpen
    local cls = pvm.classof(slot)

    -- Slot sum wrappers (from parser splice_slots)
    if cls == O.SlotType       then return M.fill_type(session, slot.slot, value, site) end
    if cls == O.SlotExpr       then return M.fill_expr(session, slot.slot, value, site) end
    if cls == O.SlotRegion     then return M.fill_region_body(session, slot.slot, value, site) end
    if cls == O.SlotRegionFrag then return M.fill_region_frag(session, slot.slot, value, site) end
    if cls == O.SlotExprFrag   then return M.fill_expr_frag(session, slot.slot, value, site) end
    if cls == O.SlotName       then return M.fill_name(session, slot.slot, value, site) end
    if cls == O.SlotItems      then return M.fill_items(session, slot.slot, value, site) end
    if cls == O.SlotModule     then return M.fill_module(session, slot.slot, value, site) end
    if cls == O.SlotTypeDecl   then return M.fill_type_decl(session, slot.slot, value, site) end
    if cls == O.SlotFunc       then return M.fill_func(session, slot.slot, value, site) end
    if cls == O.SlotConst      then return M.fill_const(session, slot.slot, value, site) end
    if cls == O.SlotStatic     then return M.fill_static(session, slot.slot, value, site) end
    if cls == O.SlotCont       then return M.fill_cont(session, slot.slot, value, site) end

    -- Direct slot products (tests / programmatic use)
    if cls == O.TypeSlot       then return M.fill_type(session, slot, value, site) end
    if cls == O.ExprSlot       then return M.fill_expr(session, slot, value, site) end
    if cls == O.RegionSlot     then return M.fill_region_body(session, slot, value, site) end
    if cls == O.RegionFragSlot then return M.fill_region_frag(session, slot, value, site) end
    if cls == O.ExprFragSlot   then return M.fill_expr_frag(session, slot, value, site) end
    if cls == O.NameSlot       then return M.fill_name(session, slot, value, site) end
    if cls == O.ItemsSlot      then return M.fill_items(session, slot, value, site) end

    error((site or "splice") .. ": unsupported splice slot class " .. tostring(cls), 2)
end

-- ── Type slot ─────────────────────────────────────────────────────────────────

-- Accepted:  host TypeValue (as_type_value()),  direct MoonType ASDL node,
--            moon.source("...") escape.
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

    -- 4. Source escape: parse the source string as a type.
    if not ty and M.is_source(value) then
        local ok, result = pcall(function()
            return require("moonlift.parse").parse_type_string(session.T, value.source)
        end)
        if ok then ty = result
        else error((site or "splice") .. ": moon.source type parse error: " .. tostring(result), 2) end
    end

    if not ty then
        error((site or "splice") .. ": expected type value for @{} type splice, got " .. M.kind_of(value), 2)
    end

    -- 5. Cross-context compatibility: if ty comes from a different ASDL context
    --    (e.g. require('moonlift.host') vs the eval session), translate via
    --    the source hint string.  Try constructing SlotValueType; on failure,
    --    fall back to re-parsing the type's string representation.
    local ok, binding = pcall(function()
        return O.SlotBinding(O.SlotType(slot), O.SlotValueType(ty))
    end)
    if ok then return binding end

    -- Context mismatch: look for a source hint or string representation.
    local src_hint = nil
    if type(value) == "table" then
        src_hint = rawget(value, "source_hint")
        if not src_hint and type(value.moonlift_splice_source) == "function" then
            src_hint = value:moonlift_splice_source()
        end
    end
    if src_hint then
        local reparse_ok, translated = pcall(function()
            local T = session.T
            local retyped = require("moonlift.parse").parse_type_string(T, src_hint)
            return O.SlotBinding(O.SlotType(slot), O.SlotValueType(retyped))
        end)
        if reparse_ok then return translated end
    end

    error((site or "splice") .. ": type value context mismatch; use the session's moon.* API instead of require('moonlift.host')", 2)
end

-- ── Expression slot ───────────────────────────────────────────────────────────

-- Accepted:  number (int/float lit), boolean (bool lit), nil (nil lit),
--            string (string literal — NOT raw source),
--            host ExprValue (as_expr_value()),  direct Expr ASDL node,
--            moon.source("...") escape.
function M.fill_expr(session, slot, value, site)
    local T  = session.T
    local C, Tr, O = T.MoonCore, T.MoonTree, T.MoonOpen

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
            -- Plain string in expression position → Moonlift string literal.
            -- Use moon.source("...") for raw source injection.
            expr = Tr.ExprLit(Tr.ExprSurface, C.LitString(value))
        end
    end

    -- 3. Host ExprValue, direct ASDL Expr node, or source escape.
    if not expr and type(value) == "table" then
        if type(value.as_expr_value) == "function" then
            expr = value:as_expr_value().expr
        elseif pvm.classof(value) ~= false then
            -- Raw ASDL node — trust the caller
            expr = value
        elseif M.is_source(value) then
            local ok, result = pcall(function()
                local T = session.T
                local Parse = require("moonlift.parse")
                local wrapped = "func __expr__() -> void\n    return " .. value.source .. "\nend"
                local parsed = Parse.parse_module(T, wrapped)
                if #parsed.issues > 0 then
                    error("parse error: " .. tostring(parsed.issues[1]), 2)
                end
                for _, item in ipairs(parsed.module.items) do
                    if pvm.classof(item) == Tr.ItemFunc then
                        for _, stmt in ipairs(item.func.body) do
                            if pvm.classof(stmt) == Tr.StmtReturnValue then
                                return stmt.value
                            end
                        end
                    end
                end
                error("could not extract expression", 2)
            end)
            if ok then expr = result
            else error((site or "splice") .. ": moon.source expr parse error: " .. tostring(result), 2) end
        end
    end

    if not expr then
        error((site or "splice") .. ": expected expression value for @{} expr splice, got " .. M.kind_of(value), 2)
    end

    return O.SlotBinding(O.SlotExpr(slot), O.SlotValueExpr(expr))
end

-- ── Region body slot (inline statement list) ──────────────────────────────────

function M.fill_region_body(session, slot, value, site)
    local O = session.T.MoonOpen

    local stmts = nil

    local p = protocol(value, "region_body", session, site)
    if p ~= nil then stmts = p end

    if not stmts and type(value) == "table" then
        -- Source escape
        if M.is_source(value) then
            local ok, result = pcall(function()
                local T = session.T
                local Parse = require("moonlift.parse")
                local stmts_out, issues = Parse.parse_stmt_list(T, value.source)
                if #issues > 0 then
                    error("parse error: " .. tostring(issues[1]), 2)
                end
                return stmts_out
            end)
            if ok then stmts = result
            else error((site or "splice") .. ": moon.source region_body parse error: " .. tostring(result), 2) end
        else
            -- Accept any Lua array (we trust the contents are Stmt nodes)
            stmts = value
        end
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

-- ── Module items slot ─────────────────────────────────────────────────────────

-- Accepted:  Lua array (trusted as Item nodes), ModuleValue with .module.items,
--            empty table (zero items).
function M.fill_items(session, slot, value, site)
    local O = session.T.MoonOpen

    local items = nil

    local p = protocol(value, "module_items", session, site)
    if p ~= nil and type(p) == "table" then items = p end

    if not items and type(value) == "table" then
        -- Module value with .module.items
        if type(value.module) == "table" and value.module.items then
            items = value.module.items
        -- Source escape
        elseif M.is_source(value) then
            local ok, result = pcall(function()
                local T = session.T
                local Parse = require("moonlift.parse")
                local parsed = Parse.parse_module(T, value.source)
                if #parsed.issues > 0 then
                    error("parse error: " .. tostring(parsed.issues[1]), 2)
                end
                return parsed.module.items
            end)
            if ok then items = result
            else error((site or "splice") .. ": moon.source module_items parse error: " .. tostring(result), 2) end
        else
            items = value
        end
    end

    if not items then
        error((site or "splice") .. ": expected module item array for module_items splice, got " .. M.kind_of(value), 2)
    end

    return O.SlotBinding(O.SlotItems(slot), O.SlotValueItems(items))
end

-- ── Module slot ───────────────────────────────────────────────────────────────

function M.fill_module(session, slot, value, site)
    local O  = session.T.MoonOpen
    local Tr = session.T.MoonTree

    local mod = nil

    if type(value) == "table" then
        if pvm.classof(value) == Tr.Module then
            mod = value
        elseif type(value.module) == "table"
               and pvm.classof(value.module) == Tr.Module then
            mod = value.module
        end
    end

    if not mod then
        error((site or "splice") .. ": expected module value for module splice, got " .. M.kind_of(value), 2)
    end

    return O.SlotBinding(O.SlotModule(slot), O.SlotValueModule(mod))
end

-- ── Stub fillers for less common slot types ───────────────────────────────────

function M.fill_type_decl(session, slot, value, site)
    local O  = session.T.MoonOpen
    if pvm.classof(value) ~= false then
        return O.SlotBinding(O.SlotTypeDecl(slot), O.SlotValueTypeDecl(value))
    end
    error((site or "splice") .. ": expected type declaration for type_decl splice, got " .. M.kind_of(value), 2)
end

function M.fill_func(session, slot, value, site)
    local O  = session.T.MoonOpen
    if pvm.classof(value) ~= false then
        return O.SlotBinding(O.SlotFunc(slot), O.SlotValueFunc(value))
    end
    error((site or "splice") .. ": expected function value for func splice, got " .. M.kind_of(value), 2)
end

function M.fill_const(session, slot, value, site)
    local O  = session.T.MoonOpen
    if pvm.classof(value) ~= false then
        return O.SlotBinding(O.SlotConst(slot), O.SlotValueConst(value))
    end
    error((site or "splice") .. ": expected const item for const splice, got " .. M.kind_of(value), 2)
end

function M.fill_static(session, slot, value, site)
    local O  = session.T.MoonOpen
    if pvm.classof(value) ~= false then
        return O.SlotBinding(O.SlotStatic(slot), O.SlotValueStatic(value))
    end
    error((site or "splice") .. ": expected static item for static splice, got " .. M.kind_of(value), 2)
end

function M.fill_cont(session, slot, value, site)
    local O  = session.T.MoonOpen
    if pvm.classof(value) ~= false then
        return O.SlotBinding(O.SlotCont(slot), O.SlotValueCont(value))
    end
    error((site or "splice") .. ": expected block label for cont splice, got " .. M.kind_of(value), 2)
end

return M
