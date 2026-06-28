local function bind_context(T)
    T._lalin_api_cache = T._lalin_api_cache or {}
    if T._lalin_api_cache.copy_patch_bc ~= nil then return T._lalin_api_cache.copy_patch_bc end

    local LJ = T.LalinLuaJIT

    local api = {}

    local function ffi_abi(name)
        local ok, ffi = pcall(require, "ffi")
        if not ok or ffi == nil or ffi.abi == nil then return false end
        local ok_abi, value = pcall(ffi.abi, name)
        return ok_abi and value or false
    end

    local function pointer_bits()
        if ffi_abi("64bit") then return 64 end
        return 32
    end

    local function endian()
        if ffi_abi("le") then return "little" end
        if ffi_abi("be") then return "big" end
        return "unknown"
    end

    function api.runtime_target()
        return LJ.LJBCTarget(
            tostring(jit and jit.version or "unknown"),
            tostring(jit and jit.arch or "unknown"),
            tostring(jit and jit.os or "unknown"),
            pointer_bits(),
            endian(),
            ffi_abi("gc64"),
            ffi_abi("dualnum"),
            pcall(require, "ffi")
        )
    end

    function api.target_matches(target, actual)
        actual = actual or api.runtime_target()
        return target ~= nil
            and target.luajit_version == actual.luajit_version
            and target.arch == actual.arch
            and target.os == actual.os
            and target.pointer_bits == actual.pointer_bits
            and target.endian == actual.endian
            and target.gc64 == actual.gc64
            and target.dualnum == actual.dualnum
            and target.ffi == actual.ffi
    end

    function api.compile_entry(opts)
        opts = opts or {}
        local source = assert(opts.source, "copy_patch_bc.compile_entry requires source")
        local chunk_name = opts.chunk_name or ("@llbl.codegen/luajit-bc/" .. tostring(opts.symbol or "stencil"))
        local loader, load_err = loadstring(source, chunk_name)
        if loader == nil then return nil, load_err end
        if opts.env ~= nil then setfenv(loader, opts.env) end
        local ok, fn_or_err = pcall(loader)
        if not ok then return nil, fn_or_err end
        if type(fn_or_err) ~= "function" then
            return nil, "copy_patch_bc: BC stencil source must return a function"
        end
        local bytecode = string.dump(fn_or_err)
        return LJ.LJBCStencilEntry(
            LJ.LJBCStencilId(tostring(opts.id or opts.symbol or chunk_name)),
            tostring(opts.symbol or opts.id or "stencil"),
            chunk_name,
            source,
            bytecode,
            opts.plan,
            opts.artifact
        )
    end

    function api.build_bank(entries, opts)
        opts = opts or {}
        return LJ.LJBCStencilBank(
            LJ.LJBCBankId(tostring(opts.id or "ljbc:bank")),
            opts.target or api.runtime_target(),
            entries or {},
            opts.metastencil_covers or {}
        )
    end

    local function entry_by_symbol(bank, symbol)
        for _, entry in ipairs(bank.entries or {}) do
            if entry.symbol == symbol then return entry end
        end
        return nil
    end

    api.entry_by_symbol = entry_by_symbol

    function api.load_entry(entry, opts)
        if type(opts) == "string" then opts = { chunk_name = opts } end
        opts = opts or {}
        local fn, load_err = loadstring(entry.bytecode, opts.chunk_name or entry.chunk_name)
        if fn == nil then return nil, load_err end
        if opts.env ~= nil then setfenv(fn, opts.env) end
        return fn
    end

    function api.load_symbol(bank, symbol, opts)
        if not api.target_matches(bank.target) then
            return nil, "copy_patch_bc: LuaJIT BC bank target does not match current LuaJIT runtime"
        end
        local entry = entry_by_symbol(bank, symbol)
        if entry == nil then return nil, "copy_patch_bc: unknown BC stencil symbol " .. tostring(symbol) end
        return api.load_entry(entry, opts)
    end

    T._lalin_api_cache.copy_patch_bc = api
    return api
end

return bind_context
