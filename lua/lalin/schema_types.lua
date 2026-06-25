-- ASDL → Lalin type declarations and TypeValue exports.
--
--   local Types = require("lalin.schema_types")
--   local blob   = Types.declarations   -- string: all ASDL types as Lalin struct/enum/union
--   local tags   = Types.tags           -- { LalinCore = { Scalar_ScalarI32 = 5, ... }, ... }
--   local tv     = Types.types          -- { LalinTree = { Expr = TypeValue, ... }, ... }
--
-- In a .mlua host step:
--   @{Types.declarations}            -- inject all type declarations
--   ptr(LalinTree_Expr)               -- all names are flat — no splice needed
--
-- Type values use LalinType.TNamed so they work with or without a runtime session.

local pvm = require("lalin.pvm")

local M = {}

-- ── Context ─────────────────────────────────────────────────────────────────────

local ctx = pvm.context()
require("lalin.schema_projection")(ctx)

local A      = ctx.LalinAsdl
local Ty     = ctx.LalinType
local schema = require("lalin.schema").schema(ctx)

-- ── Flat naming ────────────────────────────────────────────────────────────────

local function fname(mod, decl)
    return mod .. "_" .. decl
end

-- ── Declarations blob ─────────────────────────────────────────────────────────

M.declarations = require("lalin.schema_emit_types").emit_all(ctx)

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
                lalin_quote_kind = "type",
                source_hint = name,
                as_type_value = function(self)
                    return { ty = Ty.TNamed(name, {}) }
                end,
                lalin_splice = function(self, role, session, site)
                    if role == "type" then return Ty.TNamed(name, {}) end
                    error((site or "splice") .. ": schema type cannot splice as " .. role, 2)
                end,
                lalin_splice_source = function(self) return name end,
            }
        end
    end
end

return M
