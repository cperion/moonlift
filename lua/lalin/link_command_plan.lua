local schema = require("lalin.schema_runtime")
local function single(value) return { value } end
local function as_list(values) return values end
local function only(values)
    if #values == 0 then error("phase output: expected exactly 1 value, got 0", 2) end
    if #values ~= 1 then error("phase output: expected exactly 1 value, got more", 2) end
    return values[1]
end
local function append_all(out, values)
    for i = 1, #(values or {}) do out[#out + 1] = values[i] end
    return out
end
local function concat_all(lists)
    local out = {}
    for i = 1, #(lists or {}) do append_all(out, lists[i]) end
    return out
end
local function concat2(a, b)
    local out = {}
    append_all(out, a)
    append_all(out, b)
    return out
end
local function concat3(a, b, c)
    local out = {}
    append_all(out, a)
    append_all(out, b)
    append_all(out, c)
    return out
end
local function flat_map(fn, values, n)
    local out = {}
    n = n or #(values or {})
    for i = 1, n do append_all(out, fn(values[i])) end
    return out
end

local function bind_context(T)
    local Link = T.LalinLink
    assert(Link, "lalin.link_command_plan(T) expects lalin.schema_projection in the context")

    local function tool_path(tool)
        if tool.path and tool.path.text ~= "" then return tool.path.text end
        local driver = tool.driver
        if driver == Link.LinkerClang then return "clang" end
        if driver == Link.LinkerGcc then return "gcc" end
        if driver == Link.LinkerLd then return "ld" end
        if driver == Link.LinkerLld then return "ld.lld" end
        if driver == Link.LinkerAr then return "ar" end
        if driver == Link.LinkerLibtool then return "libtool" end
        if schema.classof(driver) == Link.LinkerCustom then return driver.name end
        return "cc"
    end

    local function append_input(args, input)
        local cls = schema.classof(input)
        if cls == Link.LinkInputObject or cls == Link.LinkInputStaticArchive or cls == Link.LinkInputSharedLibrary then
            args[#args + 1] = input.path.text
        elseif cls == Link.LinkInputSystemLibrary then
            args[#args + 1] = "-l" .. input.name
        elseif cls == Link.LinkInputLibrarySearchPath then
            args[#args + 1] = "-L" .. input.path.text
        elseif cls == Link.LinkInputFramework then
            args[#args + 1] = "-framework"
            args[#args + 1] = input.name
        elseif cls == Link.LinkInputLinkerScript then
            args[#args + 1] = "-Wl,-T," .. input.path.text
        end
    end

    local function append_option(args, target, option)
        local cls = schema.classof(option)
        if cls == Link.LinkOptRuntimePath then
            args[#args + 1] = "-Wl,-rpath," .. option.path.path.text
        elseif cls == Link.LinkOptEntry then
            args[#args + 1] = "-Wl,-e," .. option.symbol.name
        elseif cls == Link.LinkOptSoname then
            if target.platform == Link.LinkPlatformLinux then args[#args + 1] = "-Wl,-soname," .. option.name end
        elseif cls == Link.LinkOptInstallName then
            if target.platform == Link.LinkPlatformMacOS then args[#args + 1] = "-Wl,-install_name," .. option.name end
        elseif cls == Link.LinkOptOutputImplib then
            if target.platform == Link.LinkPlatformWindows then args[#args + 1] = "-Wl,--out-implib," .. option.path.text end
        elseif cls == Link.LinkOptDebug then
            if option.policy == Link.LinkDebugStrip then args[#args + 1] = "-s" end
        elseif cls == Link.LinkOptWholeArchiveBegin then
            args[#args + 1] = "-Wl,--whole-archive"
        elseif cls == Link.LinkOptWholeArchiveEnd then
            args[#args + 1] = "-Wl,--no-whole-archive"
        elseif cls == Link.LinkOptNoDefaultLibs then
            args[#args + 1] = "-nodefaultlibs"
        elseif cls == Link.LinkOptStaticLibgcc then
            args[#args + 1] = "-static-libgcc"
        elseif cls == Link.LinkOptCustomArg then
            args[#args + 1] = option.arg
        end
    end

    local function add_export_args(args, plan)
        if schema.classof(plan.exports) == Link.LinkExportVersionScript then
            args[#args + 1] = "-Wl,--version-script," .. plan.exports.path.text
        elseif schema.classof(plan.exports) == Link.LinkExportSymbols then
            for i = 1, #plan.exports.symbols do
                if plan.target.platform == Link.LinkPlatformMacOS then
                    args[#args + 1] = "-Wl,-exported_symbol,_" .. plan.exports.symbols[i].name
                elseif plan.target.platform == Link.LinkPlatformLinux then
                    args[#args + 1] = "-Wl,--undefined," .. plan.exports.symbols[i].name
                end
            end
        end
    end

    local function command_plan(plan)
        local args = {}
        if plan.output_form == Link.LinkArtifactStaticArchive then
            args[#args + 1] = "rcs"
            args[#args + 1] = plan.output.text
            for i = 1, #plan.inputs do append_input(args, plan.inputs[i]) end
            return Link.LinkCommandPlan(plan, { Link.LinkCmdRun(Link.LinkTool(Link.LinkerAr, Link.LinkPath(tool_path(plan.tool) == "cc" and "ar" or tool_path(plan.tool))), args, {}) })
        end

        if plan.output_form == Link.LinkArtifactSharedLibrary then
            if plan.target.platform == Link.LinkPlatformMacOS then args[#args + 1] = "-dynamiclib"
            else args[#args + 1] = "-shared" end
        elseif plan.output_form == Link.LinkArtifactExecutable and plan.target.platform == Link.LinkPlatformWindows then
            -- cc default is executable; no flag needed.
        end

        if plan.externs == Link.LinkExternRequireResolved and plan.output_form == Link.LinkArtifactSharedLibrary and plan.target.platform == Link.LinkPlatformLinux then
            args[#args + 1] = "-Wl,--no-undefined"
        end
        for i = 1, #plan.options do append_option(args, plan.target, plan.options[i]) end
        add_export_args(args, plan)
        for i = 1, #plan.inputs do append_input(args, plan.inputs[i]) end
        args[#args + 1] = "-o"
        args[#args + 1] = plan.output.text
        return Link.LinkCommandPlan(plan, { Link.LinkCmdRun(Link.LinkTool(plan.tool.driver, Link.LinkPath(tool_path(plan.tool))), args, {}) })
    end

    local function phase(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, Link.LinkPlan) then
            return (function(self)
 return single(command_plan(self))
            end)(node, ...)
        else
            error("phase lalin_link_command_plan: no handler for " .. tostring(cls or type(node)), 2)
        end
    end

    return {
        phase = phase,
        plan = command_plan,
    }
end

return bind_context
