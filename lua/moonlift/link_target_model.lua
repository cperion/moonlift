local ffi = require("ffi")

local M = {}

function M.Define(T)
    local Link = T.Moon2Link
    local BackTarget = require("moonlift.back_target_model").Define(T)
    assert(Link, "moonlift.link_target_model.Define expects moonlift.asdl in the context")

    local api = {}

    local function platform()
        if ffi.os == "Linux" then return Link.LinkPlatformLinux end
        if ffi.os == "OSX" then return Link.LinkPlatformMacOS end
        if ffi.os == "Windows" then return Link.LinkPlatformWindows end
        return Link.LinkPlatformUnknown(ffi.os or "unknown")
    end

    local function arch()
        if jit and jit.arch == "x64" then return Link.LinkArchX86_64 end
        if jit and jit.arch == "arm64" then return Link.LinkArchAArch64 end
        if jit and jit.arch == "x86" then return Link.LinkArchX86 end
        if jit and jit.arch == "arm" then return Link.LinkArchArm end
        return Link.LinkArchUnknown((jit and jit.arch) or "unknown")
    end

    local function object_format(p)
        if p == Link.LinkPlatformLinux then return Link.LinkFormatElf end
        if p == Link.LinkPlatformMacOS then return Link.LinkFormatMachO end
        if p == Link.LinkPlatformWindows then return Link.LinkFormatCoff end
        return Link.LinkFormatUnknown((p and p.kind) or "unknown")
    end

    function api.default(relocation)
        local p = platform()
        return Link.LinkTargetModel(
            BackTarget.default_native(),
            p,
            arch(),
            object_format(p),
            relocation or Link.LinkRelocPic
        )
    end

    function api.default_object()
        return api.default(Link.LinkRelocPic)
    end

    return api
end

return M
