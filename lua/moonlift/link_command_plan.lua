local pvm = require("moonlift.pvm")

local M = {}

function M.Define(T)
    local Link = T.MoonLink
    assert(Link, "moonlift.link_command_plan.Define expects moonlift.asdl in the context")

    local function tool_path(tool)
        if tool.path and tool.path.text ~= "" then return tool.path.text end
        local kind = tool.kind
        if kind == Link.LinkerClang then return "clang" end
        if kind == Link.LinkerGcc then return "gcc" end
        if kind == Link.LinkerLd then return "ld" end
        if kind == Link.LinkerLld then return "ld.lld" end
        if kind == Link.LinkerAr then return "ar" end
        if kind == Link.LinkerLibtool then return "libtool" end
        if pvm.classof(kind) == Link.LinkerCustom then return kind.name end
        return "cc"
    end

    local function append_input(args, input)
        local cls = pvm.classof(input)
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
        local cls = pvm.classof(option)
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
        if pvm.classof(plan.exports) == Link.LinkExportVersionScript then
            args[#args + 1] = "-Wl,--version-script," .. plan.exports.path.text
        elseif pvm.classof(plan.exports) == Link.LinkExportSymbols then
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
        if plan.kind == Link.LinkArtifactStaticArchive then
            args[#args + 1] = "rcs"
            args[#args + 1] = plan.output.text
            for i = 1, #plan.inputs do append_input(args, plan.inputs[i]) end
            return Link.LinkCommandPlan(plan, { Link.LinkCmdRun(Link.LinkTool(Link.LinkerAr, Link.LinkPath(tool_path(plan.tool) == "cc" and "ar" or tool_path(plan.tool))), args, {}) })
        end

        if plan.kind == Link.LinkArtifactSharedLibrary then
            if plan.target.platform == Link.LinkPlatformMacOS then args[#args + 1] = "-dynamiclib"
            else args[#args + 1] = "-shared" end
        elseif plan.kind == Link.LinkArtifactExecutable and plan.target.platform == Link.LinkPlatformWindows then
            -- cc default is executable; no flag needed.
        end

        if plan.externs == Link.LinkExternRequireResolved and plan.kind == Link.LinkArtifactSharedLibrary and plan.target.platform == Link.LinkPlatformLinux then
            args[#args + 1] = "-Wl,--no-undefined"
        end
        for i = 1, #plan.options do append_option(args, plan.target, plan.options[i]) end
        add_export_args(args, plan)
        for i = 1, #plan.inputs do append_input(args, plan.inputs[i]) end
        args[#args + 1] = "-o"
        args[#args + 1] = plan.output.text
        return Link.LinkCommandPlan(plan, { Link.LinkCmdRun(Link.LinkTool(plan.tool.kind, Link.LinkPath(tool_path(plan.tool))), args, {}) })
    end

    local phase = pvm.phase("moon2_link_command_plan", {
        [Link.LinkPlan] = function(self) return pvm.once(command_plan(self)) end,
    })

    return {
        phase = phase,
        plan = command_plan,
    }
end

return M
