local pvm = require("moonlift.pvm")

local M = {}

local function issue_range(L, issue)
    local line = math.max(0, tonumber(issue.line or 1) - 1)
    local col = math.max(0, tonumber(issue.col or 1) - 1)
    return L.Range(L.Position(line, col), L.Position(line, col + 1))
end

function M.Define(T)
    require("moonlift.lsp_asdl").Define(T)
    local L = T.MoonliftLsp
    local MluaParse = require("moonlift.mlua_parse").Define(T)
    local HostValidate = require("moonlift.host_decl_validate").Define(T)

    local phase = pvm.phase("moonlift_lsp_diagnostics", {
        [L.Document] = function(self)
            local out = {}
            local ok, parsed = pcall(function() return MluaParse.parse(self.text, self.uri) end)
            if not ok then
                out[#out + 1] = L.Diagnostic(L.Range(L.Position(0, 0), L.Position(0, 1)), L.DiagError, "moonlift", tostring(parsed))
                return pvm.T.seq(out)
            end
            for i = 1, #parsed.issues do
                local issue = parsed.issues[i]
                out[#out + 1] = L.Diagnostic(issue_range(L, issue), L.DiagError, "moonlift", tostring(issue.message or issue))
            end
            if #parsed.issues == 0 then
                local report = HostValidate.validate(parsed.decls)
                for i = 1, #report.issues do
                    out[#out + 1] = L.Diagnostic(L.Range(L.Position(0, 0), L.Position(0, 1)), L.DiagError, "moonlift", tostring(report.issues[i]))
                end
            end
            return pvm.T.seq(out)
        end,
    })

    return { phase = phase, diagnostics = function(doc) return pvm.drain(phase(doc)) end }
end

return M
