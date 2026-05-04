local pvm = require("moonlift.pvm")

local M = {}

local function is_identifier(name)
    return type(name) == "string" and name:match("^[_%a][_%w]*$") ~= nil
end

local function seq_or_empty(xs)
    if #xs == 0 then return pvm.empty() end
    return pvm.T.seq(xs)
end

local function is_power_of_two(n)
    if type(n) ~= "number" or n < 1 or n % 1 ~= 0 then return false end
    while n > 1 do
        if n % 2 ~= 0 then return false end
        n = n / 2
    end
    return true
end

function M.Define(T)
    local H = T.MoonHost
    local Ty = T.MoonType
    local C = T.MoonCore

    local function scalar_bool_ty(ty)
        return pvm.classof(ty) == Ty.TScalar and ty.scalar == C.ScalarBool
    end

    local field_issue_phase = pvm.phase("moonlift_host_field_decl_validate", {
        [H.HostFieldDecl] = function(self, owner_name)
            local issues = {}
            if not is_identifier(self.name) then
                issues[#issues + 1] = H.HostIssueInvalidName(owner_name .. ".field", tostring(self.name))
            end
            if scalar_bool_ty(self.expose_ty) and self.storage == H.HostStorageSame then
                issues[#issues + 1] = H.HostIssueBareBoolInBoundaryStruct(owner_name, self.name)
            end
            return seq_or_empty(issues)
        end,
    }, { args_cache = "full" })

    local struct_issue_phase = pvm.phase("moonlift_host_struct_decl_validate", {
        [H.HostStructDecl] = function(self)
            local issues = {}
            if not is_identifier(self.name) then
                issues[#issues + 1] = H.HostIssueInvalidName("struct", tostring(self.name))
            end
            if pvm.classof(self.repr) == H.HostReprPacked and not is_power_of_two(self.repr.align) then
                issues[#issues + 1] = H.HostIssueInvalidPackedAlign(self.name, self.repr.align)
            end
            local seen = {}
            for i = 1, #self.fields do
                local field = self.fields[i]
                if seen[field.name] then
                    issues[#issues + 1] = H.HostIssueDuplicateField(self.name, field.name)
                else
                    seen[field.name] = true
                end
                local fg, fp, fc = field_issue_phase(field, self.name)
                pvm.drain_into(fg, fp, fc, issues)
            end
            return seq_or_empty(issues)
        end,
    })

    local expose_issue_phase = pvm.phase("moonlift_host_expose_decl_validate", {
        [H.HostExposeDecl] = function(self)
            local issues = {}
            if not is_identifier(self.public_name) then
                issues[#issues + 1] = H.HostIssueInvalidName("expose", tostring(self.public_name))
            end
            return seq_or_empty(issues)
        end,
    })

    local accessor_issue_phase = pvm.phase("moonlift_host_accessor_decl_validate", {
        [H.HostAccessorField] = function(self)
            local issues = {}
            if not is_identifier(self.owner_name) then issues[#issues + 1] = H.HostIssueInvalidName("accessor.owner", tostring(self.owner_name)) end
            if not is_identifier(self.name) then issues[#issues + 1] = H.HostIssueInvalidName("accessor", tostring(self.name)) end
            if not is_identifier(self.field_name) then issues[#issues + 1] = H.HostIssueInvalidName("accessor.field", tostring(self.field_name)) end
            return seq_or_empty(issues)
        end,
        [H.HostAccessorLua] = function(self)
            local issues = {}
            if not is_identifier(self.owner_name) then issues[#issues + 1] = H.HostIssueInvalidName("accessor.owner", tostring(self.owner_name)) end
            if not is_identifier(self.name) then issues[#issues + 1] = H.HostIssueInvalidName("accessor", tostring(self.name)) end
            if not is_identifier(self.lua_symbol) then issues[#issues + 1] = H.HostIssueInvalidName("accessor.lua_symbol", tostring(self.lua_symbol)) end
            return seq_or_empty(issues)
        end,
        [H.HostAccessorMoonlift] = function(self)
            local issues = {}
            if not is_identifier(self.owner_name) then issues[#issues + 1] = H.HostIssueInvalidName("accessor.owner", tostring(self.owner_name)) end
            if not is_identifier(self.name) then issues[#issues + 1] = H.HostIssueInvalidName("accessor", tostring(self.name)) end
            return seq_or_empty(issues)
        end,
    })

    local decl_issue_phase = pvm.phase("moonlift_host_decl_validate", {
        [H.HostDeclStruct] = function(self)
            return struct_issue_phase(self.decl)
        end,
        [H.HostDeclExpose] = function(self)
            return expose_issue_phase(self.decl)
        end,
        [H.HostDeclAccessor] = function(self)
            return accessor_issue_phase(self.decl)
        end,
    })

    local decl_set_issue_phase = pvm.phase("moonlift_host_decl_set_validate", {
        [H.HostDeclSet] = function(self)
            local issues = {}
            local seen = {}
            for i = 1, #self.decls do
                local decl = self.decls[i]
                local cls = pvm.classof(decl)
                local key
                if cls == H.HostDeclStruct then
                    key = "type:" .. decl.decl.name
                elseif cls == H.HostDeclExpose then
                    key = "expose:" .. decl.decl.public_name
                elseif cls == H.HostDeclAccessor then
                    key = "accessor:" .. decl.decl.owner_name .. "." .. decl.decl.name
                end
                if key ~= nil then
                    if seen[key] then issues[#issues + 1] = H.HostIssueDuplicateDecl(key) end
                    seen[key] = true
                end
                local dg, dp, dc = decl_issue_phase(decl)
                pvm.drain_into(dg, dp, dc, issues)
            end
            return seq_or_empty(issues)
        end,
    })

    local function validate(decls)
        local issues = pvm.drain(decl_set_issue_phase(decls))
        return H.HostReport(issues)
    end

    return {
        validate = validate,
        decl_set_issue_phase = decl_set_issue_phase,
        decl_issue_phase = decl_issue_phase,
        struct_issue_phase = struct_issue_phase,
        field_issue_phase = field_issue_phase,
        expose_issue_phase = expose_issue_phase,
        accessor_issue_phase = accessor_issue_phase,
    }
end

return M
