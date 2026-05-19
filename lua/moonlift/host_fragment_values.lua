-- ExprFragValue class (builder form removed; quote via moon.expr_frag[[]]).
--
-- The ExprFragValue metatable and splice protocol are still needed for
-- internal composition (host_splice, region_compose).  The builder class
-- ExprFragBuilder and api.expr_frag() constructor have been removed.

local M = {}

local ExprFragValue = {}
ExprFragValue.__index = ExprFragValue

function ExprFragValue:moonlift_splice_source()
    return self.name
end

function ExprFragValue:moonlift_splice(role, session, site)
    if role == "expr_frag" then return self.frag end
    error((site or "splice") .. ": expression fragment value cannot splice as " .. role, 2)
end

function ExprFragValue:__tostring()
    return "MoonExprFragValue(" .. self.name .. ")"
end

function M.Install(api, session)
    api.ExprFragValue = ExprFragValue
end

return M
