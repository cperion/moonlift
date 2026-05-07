-- ASDL → Moonlift type declarations and TypeValue exports.
--
--   local Types = require("moonlift.schema_types")
--   local blob   = Types.declarations   -- string: all ASDL types as Moonlift struct/enum/union
--   local tags   = Types.tags           -- { MoonCore = { Scalar_ScalarI32 = 5, ... }, ... }
--   local tv     = Types.types          -- { MoonTree = { Expr = TypeValue, ... }, ... }
--
-- In a .mlua host step:
--   @{Types.declarations}            -- inject all type declarations
--   ptr(MoonTree_Expr)               -- all names are flat — no splice needed
--
-- Type values use MoonType.TNamed so they work with or without a runtime session.

local pvm = require("moonlift.pvm")

local M = {}

-- ── Context ─────────────────────────────────────────────────────────────────────

local ctx = pvm.context()
require("moonlift.asdl").Define(ctx)

local A      = ctx.MoonAsdl
local Ty     = ctx.MoonType
local schema = require("moonlift.schema").schema(ctx)

-- ── Flat naming ────────────────────────────────────────────────────────────────

local function fname(mod, decl)
    return mod .. "_" .. decl
end

-- ── Declarations blob ─────────────────────────────────────────────────────────

M.declarations = require("moonlift.asdl_emit_types").emit_all(ctx)

-- ── Tags ───────────────────────────────────────────────────────────────────────

M.tags = {}
for _, mod in ipairs(schema.modules or {}) do
    local mt = {}
    M.tags[mod.name] = mt
    for _, decl in ipairs(mod.decls or {}) do
        if pvm.classof(decl) == A.SumDecl then
            for vi, v in ipairs(decl.variants or {}) do
                mt[decl.name .. "_" .. v.name] = vi - 1
            end
        end
    end
end

-- ── Type values ────────────────────────────────────────────────────────────────

M.types = {}
for _, mod in ipairs(schema.modules or {}) do
    local mt = {}
    M.types[mod.name] = mt
    for _, decl in ipairs(mod.decls or {}) do
        local cls = pvm.classof(decl)
        if cls == A.ProductDecl or cls == A.SumDecl then
            local name = fname(mod.name, decl.name)
            mt[decl.name] = {
                moonlift_quote_kind = "type",
                source_hint = name,
                as_type_value = function(self)
                    return { ty = Ty.TNamed(name, {}) }
                end,
                moonlift_splice = function(self, role, session, site)
                    if role == "type" then return Ty.TNamed(name, {}) end
                    error((site or "splice") .. ": schema type cannot splice as " .. role, 2)
                end,
                moonlift_splice_source = function(self) return name end,
            }
        end
    end
end

return M
