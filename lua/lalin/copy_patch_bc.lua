local pvm = require("lalin.pvm")

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

    local function find_exact_once(blob, needle, label)
        if needle == "" then return nil, "copy_patch_bc: empty patch hole " .. tostring(label) end
        local first = blob:find(needle, 1, true)
        if first == nil then
            return nil, "copy_patch_bc: patch hole not found: " .. tostring(label)
        end
        local second = blob:find(needle, first + 1, true)
        if second ~= nil then
            return nil, "copy_patch_bc: patch hole is not unique: " .. tostring(label)
        end
        return first
    end

    local function patch_kind(kind)
        if kind == nil or kind == "string" or kind == LJ.LJBCPatchStringConstantExact then
            return LJ.LJBCPatchStringConstantExact
        end
        if kind == "bytes" or kind == LJ.LJBCPatchBytesExact then
            return LJ.LJBCPatchBytesExact
        end
        error("copy_patch_bc: unknown patch kind " .. tostring(kind), 3)
    end

    local function patch_value_bytes(value)
        if type(value) == "string" then return value end
        if type(value) ~= "table" then
            error("copy_patch_bc: patch value must be string or LJBCPatchValue", 3)
        end
        if value == LJ.LJBCPatchBytesExact then
            error("copy_patch_bc: patch value cannot be a patch kind", 3)
        end
        local cls = pvm.classof(value)
        if cls == LJ.LJBCPatchBytes then return value.bytes end
        if cls == LJ.LJBCPatchString then return value.text end
        if value.bytes ~= nil then return value.bytes end
        if value.text ~= nil then return value.text end
        error("copy_patch_bc: unsupported patch value", 3)
    end

    local function normalize_bindings(bindings)
        local by_name = {}
        for _, binding in ipairs(bindings or {}) do
            if type(binding) == "table" and binding.name ~= nil and binding.value ~= nil then
                by_name[binding.name] = patch_value_bytes(binding.value)
            elseif type(binding) == "table" then
                for k, v in pairs(binding) do by_name[k] = patch_value_bytes(v) end
            else
                error("copy_patch_bc: invalid patch binding", 3)
            end
        end
        return by_name
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
        local patches = {}
        for _, hole in ipairs(opts.holes or {}) do
            local name = assert(hole.name, "copy_patch_bc: patch hole requires name")
            local expected = assert(hole.expected, "copy_patch_bc: patch hole requires expected")
            local pos, err = find_exact_once(bytecode, expected, name)
            if pos == nil then return nil, err end
            patches[#patches + 1] = LJ.LJBCPatchRecord(
                name,
                pos - 1,
                #expected,
                patch_kind(hole.kind),
                expected,
                tostring(hole.reason or "BC copy-patch hole")
            )
        end
        return LJ.LJBCStencilEntry(
            LJ.LJBCStencilId(tostring(opts.id or opts.symbol or chunk_name)),
            tostring(opts.symbol or opts.id or "stencil"),
            chunk_name,
            source,
            bytecode,
            patches,
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

    function api.patch_bytecode(entry, bindings)
        local by_name = normalize_bindings(bindings)
        local patches = {}
        for i, patch in ipairs(entry.patches or {}) do patches[i] = patch end
        table.sort(patches, function(a, b) return a.offset < b.offset end)

        local out = {}
        local cursor = 1
        local bytecode = entry.bytecode
        for _, patch in ipairs(patches) do
            local start = patch.offset + 1
            local stop = start + patch.width - 1
            local expected = patch.expected
            if bytecode:sub(start, stop) ~= expected then
                return nil, "copy_patch_bc: bytecode patch preimage mismatch for " .. tostring(patch.name)
            end
            local replacement = by_name[patch.name]
            if replacement == nil then
                replacement = expected
            end
            if #replacement ~= patch.width then
                return nil, "copy_patch_bc: replacement width mismatch for " .. tostring(patch.name)
            end
            out[#out + 1] = bytecode:sub(cursor, start - 1)
            out[#out + 1] = replacement
            cursor = stop + 1
        end
        out[#out + 1] = bytecode:sub(cursor)
        return table.concat(out)
    end

    function api.load_entry(entry, bindings, opts)
        if type(opts) == "string" then opts = { chunk_name = opts } end
        opts = opts or {}
        local patched, patch_err = api.patch_bytecode(entry, bindings or {})
        if patched == nil then return nil, patch_err end
        local fn, load_err = loadstring(patched, opts.chunk_name or entry.chunk_name)
        if fn == nil then return nil, load_err end
        if opts.env ~= nil then setfenv(fn, opts.env) end
        return fn
    end

    function api.load_symbol(bank, symbol, bindings, opts)
        if not api.target_matches(bank.target) then
            return nil, "copy_patch_bc: LuaJIT BC bank target does not match current LuaJIT runtime"
        end
        local entry = entry_by_symbol(bank, symbol)
        if entry == nil then return nil, "copy_patch_bc: unknown BC stencil symbol " .. tostring(symbol) end
        return api.load_entry(entry, bindings, opts)
    end

    T._lalin_api_cache.copy_patch_bc = api
    return api
end

return bind_context
