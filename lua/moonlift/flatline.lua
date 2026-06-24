-- Flatline backend image ABI.
--
-- FlatlineImage is the typed compiler boundary between MoonBack.Program and
-- flat backend command consumers. The payload is the Flatline v4 binary
-- image documented in docs/BACK_WIRE_FORMAT.md.

local pvm = require("moonlift.pvm")

local M = {}

M.FORMAT = "flatline"
M.VERSION = 4
M.MAGIC = 0x4D4C

local function class_name(v)
    local cls = pvm.classof(v)
    return cls and (tostring(cls):match("Class%((.-)%)") or tostring(cls)) or type(v)
end

local function u32le(bytes, offset)
    local a, b, c, d = bytes:byte(offset, offset + 3)
    if not d then return nil end
    return a + b * 256 + c * 65536 + d * 16777216
end

local function bind_context(T)
    require("moonlift.compiler_model")(T)

    T._moonlift_api_cache = T._moonlift_api_cache or {}
    if T._moonlift_api_cache.flatline ~= nil then return T._moonlift_api_cache.flatline end

    local Compiler = T.MoonCompiler
    local Back = T.MoonBack
    local Binary = require("moonlift.back_command_binary")(T)

    local api = {}

    local function add(issues, issue)
        issues[#issues + 1] = issue
    end

    function api.image(bytes)
        return Compiler.FlatlineImage(M.FORMAT, M.VERSION, bytes)
    end

    function api.encode_back_program(program)
        assert(pvm.classof(program) == Back.BackProgram, "moonlift.flatline encode_back_program expects MoonBack.BackProgram")
        return api.image(Binary.encode(program))
    end

    function api.validate_image(image)
        local issues = {}
        if pvm.classof(image) ~= Compiler.FlatlineImage then
            add(issues, Compiler.FlatlineImageIssueWrongClass("MoonCompiler.FlatlineImage", class_name(image)))
            return Compiler.FlatlineImageReport(issues)
        end
        if image.format ~= M.FORMAT then
            add(issues, Compiler.FlatlineImageIssueBadHeader("expected format `" .. M.FORMAT .. "`, got `" .. tostring(image.format) .. "`"))
        end
        if image.version ~= M.VERSION then
            add(issues, Compiler.FlatlineImageIssueBadVersion(M.VERSION, tonumber(image.version) or -1))
        end
        local bytes = image.bytes
        if type(bytes) ~= "string" then
            add(issues, Compiler.FlatlineImageIssueBadHeader("bytes field is not a Lua string"))
            return Compiler.FlatlineImageReport(issues)
        end
        if #bytes < 28 then
            add(issues, Compiler.FlatlineImageIssueBadHeader("image is shorter than the 28-byte header"))
            return Compiler.FlatlineImageReport(issues)
        end
        local magic = u32le(bytes, 1)
        local version = u32le(bytes, 5)
        local n_funcs = u32le(bytes, 9)
        local decl_offset = u32le(bytes, 13)
        local decl_len = u32le(bytes, 17)
        local body_tbl_offset = u32le(bytes, 21)
        local body_tbl_len = u32le(bytes, 25)
        if magic ~= M.MAGIC then add(issues, Compiler.FlatlineImageIssueBadMagic(magic or -1)) end
        if version ~= M.VERSION then add(issues, Compiler.FlatlineImageIssueBadVersion(M.VERSION, version or -1)) end
        if decl_offset ~= 28 then add(issues, Compiler.FlatlineImageIssueBadSection("decl_offset", "expected declaration section to start at byte 28")) end
        if decl_offset + decl_len ~= body_tbl_offset then
            add(issues, Compiler.FlatlineImageIssueBadSection("body_tbl_offset", "body table must start immediately after declarations"))
        end
        if body_tbl_len ~= n_funcs * 12 then
            add(issues, Compiler.FlatlineImageIssueBadSection("body_tbl_len", "body table must contain one 12-byte row per function body"))
        end
        if body_tbl_offset + body_tbl_len > #bytes then
            add(issues, Compiler.FlatlineImageIssueBadSection("body_table", "body table extends past image length"))
        end
        return Compiler.FlatlineImageReport(issues)
    end

    function api.issue_text(issue)
        local cls = pvm.classof(issue)
        if cls == Compiler.FlatlineImageIssueWrongClass then
            return "expected " .. tostring(issue.expected) .. ", got " .. tostring(issue.actual)
        elseif cls == Compiler.FlatlineImageIssueBadHeader then
            return tostring(issue.reason)
        elseif cls == Compiler.FlatlineImageIssueBadMagic then
            return "bad Flatline magic " .. tostring(issue.actual)
        elseif cls == Compiler.FlatlineImageIssueBadVersion then
            return "expected Flatline v" .. tostring(issue.expected) .. ", got v" .. tostring(issue.actual)
        elseif cls == Compiler.FlatlineImageIssueBadSection then
            return "bad Flatline section " .. tostring(issue.name) .. ": " .. tostring(issue.reason)
        end
        return tostring(issue)
    end

    function api.assert_valid_image(image)
        local report = api.validate_image(image)
        if #report.issues == 0 then return report end
        local messages = {}
        for i = 1, #report.issues do messages[#messages + 1] = api.issue_text(report.issues[i]) end
        error("moonlift Flatline image validation failed:\n" .. table.concat(messages, "\n"), 2)
    end

    api.validate = api.validate_image

    T._moonlift_api_cache.flatline = api
    return api
end

return setmetatable(M, {
    __call = function(_, ...)
        return bind_context(...)
    end,
})
