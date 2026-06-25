-- LalinCompiler ABI boundary validation.
--
-- CodeResult is the persisted hosted-code boundary between semantic LalinTree
-- and backend projections. Back/C consumers must validate this product before
-- deriving target-specific programs.

local pvm = require("lalin.pvm")

local function class_name(v)
    local cls = pvm.classof(v)
    return cls and (tostring(cls):match("Class%((.-)%)") or tostring(cls)) or type(v)
end

local function bind_context(T)
    require("lalin.compiler_model")(T)

    T._lalin_api_cache = T._lalin_api_cache or {}
    if T._lalin_api_cache.compiler_abi ~= nil then return T._lalin_api_cache.compiler_abi end

    local Compiler = T.LalinCompiler
    local Code = T.LalinCode
    local Sem = T.LalinSem
    local CodeValidate = require("lalin.code_validate")(T)

    local api = {}

    local function add(issues, issue)
        issues[#issues + 1] = issue
    end

    local function check_field(issues, value, field_name, expected_class, expected_name)
        if pvm.classof(value) ~= expected_class then
            add(issues, Compiler.CodeResultIssueInvalidField(field_name, expected_name, class_name(value)))
            return false
        end
        return true
    end

    function api.validate_code_result(code_result, opts)
        opts = opts or {}
        local issues = {}

        if pvm.classof(code_result) ~= Compiler.CodeResult then
            add(issues, Compiler.CodeResultIssueWrongClass("LalinCompiler.CodeResult", class_name(code_result)))
            return Compiler.CodeResultReport(issues)
        end

        local module_ok = check_field(issues, code_result.module, "module", Code.CodeModule, "LalinCode.CodeModule")
        check_field(issues, code_result.layout_env, "layout_env", Sem.LayoutEnv, "LalinSem.LayoutEnv")

        if type(code_result.contracts) ~= "table" or pvm.classof(code_result.contracts) then
            add(issues, Compiler.CodeResultIssueInvalidField("contracts", "LalinCode.CodeFuncContractFact[]", class_name(code_result.contracts)))
        else
            for i = 1, #code_result.contracts do
                if pvm.classof(code_result.contracts[i]) ~= Code.CodeFuncContractFact then
                    add(issues, Compiler.CodeResultIssueInvalidField("contracts[" .. tostring(i) .. "]", "LalinCode.CodeFuncContractFact", class_name(code_result.contracts[i])))
                end
            end
        end

        if module_ok then
            local code_report = CodeValidate.validate(code_result.module, opts.collector)
            for i = 1, #(code_report.issues or {}) do
                add(issues, Compiler.CodeResultIssueInvalidCode(code_report.issues[i]))
            end
        end

        return Compiler.CodeResultReport(issues)
    end

    function api.issue_text(issue)
        local cls = pvm.classof(issue)
        if cls == Compiler.CodeResultIssueWrongClass then
            return "expected " .. tostring(issue.expected) .. ", got " .. tostring(issue.actual)
        elseif cls == Compiler.CodeResultIssueInvalidField then
            return "field " .. tostring(issue.name) .. " expected " .. tostring(issue.expected) .. ", got " .. tostring(issue.actual)
        elseif cls == Compiler.CodeResultIssueInvalidCode then
            return "invalid code: " .. tostring(issue.issue)
        end
        return tostring(issue)
    end

    function api.assert_valid_code_result(code_result, opts)
        local report = api.validate_code_result(code_result, opts)
        if #report.issues == 0 then return report end
        local messages = {}
        for i = 1, #report.issues do messages[#messages + 1] = api.issue_text(report.issues[i]) end
        error("lalin compiler ABI CodeResult validation failed:\n" .. table.concat(messages, "\n"), 2)
    end

    api.validate = api.validate_code_result

    T._lalin_api_cache.compiler_abi = api
    return api
end

return bind_context