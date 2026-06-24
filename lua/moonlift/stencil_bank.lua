local pvm = require("moonlift.pvm")

local function shell_quote(s)
    s = tostring(s)
    return "'" .. s:gsub("'", "'\\''") .. "'"
end

local function sanitize(s)
    s = tostring(s or "x"):gsub("[^%w_]", "_")
    if s == "" then s = "x" end
    if s:match("^%d") then s = "_" .. s end
    return s
end

local function read_file(path)
    local f = assert(io.open(path, "rb"))
    local s = f:read("*a")
    f:close()
    return s
end

local function write_file(path, source)
    local f = assert(io.open(path, "wb"))
    f:write(source)
    f:close()
end

local function capture(cmd)
    local f = assert(io.popen(cmd .. " 2>&1", "r"))
    local out = f:read("*a")
    local ok, _, code = f:close()
    if ok == true or ok == 0 then return out end
    return nil, out, code
end

local function mmap_install(bytes)
    local ffi = require("ffi")
    local bit = require("bit")
    pcall(ffi.cdef, [[
typedef unsigned int uint32_t;
typedef unsigned long uint64_t;
typedef int int32_t;
typedef unsigned long size_t;
typedef long intptr_t;
typedef unsigned long uintptr_t;
void *mmap(void *addr, size_t length, int prot, int flags, int fd, intptr_t offset);
]])
    local PROT_READ, PROT_WRITE, PROT_EXEC = 1, 2, 4
    local MAP_PRIVATE, MAP_ANON = 2, 32
    local MAP_FAILED = ffi.cast("void *", -1)
    local mem = ffi.C.mmap(nil, #bytes, bit.bor(PROT_READ, PROT_WRITE, PROT_EXEC), bit.bor(MAP_PRIVATE, MAP_ANON), -1, 0)
    if mem == MAP_FAILED then error("stencil_bank: mmap failed while installing binary stencil", 3) end
    ffi.copy(mem, bytes, #bytes)
    return mem, ffi.cast("uint8_t *", mem)
end

local function symbol_ordinal(symbol)
    symbol = tostring(symbol or "")
    return tonumber(symbol:match("[Pp][Aa][Tt][Cc][Hh]_?(%d+)$"))
        or tonumber(symbol:match("[Hh][Oo][Ll][Ee]_?(%d+)$"))
        or tonumber(symbol:match("__ml_patch_?(%d+)$"))
end

local function patch_value(record, values)
    if record.value ~= nil then return record.value end
    if record.ordinal ~= nil then
        local v = values and values[record.ordinal]
        if v == nil then error("stencil_bank: missing patch ordinal " .. tostring(record.ordinal), 4) end
        return v
    end
    if record.symbol ~= nil and values ~= nil and values[record.symbol] ~= nil then return values[record.symbol] end
    return 0
end

local function parse_int(s)
    if s == nil then return 0 end
    s = tostring(s)
    local sign = 1
    if s:sub(1, 1) == "-" then sign = -1; s = s:sub(2) end
    if s:match("^0x") or s:match("^0X") then return sign * tonumber(s) end
    if s:match("^[0-9a-fA-F]+$") and s:match("[a-fA-F]") then return sign * tonumber(s, 16) end
    return sign * tonumber(s)
end

local function map_reloc_type(typ, symbol)
    if typ == "R_X86_64_64" then return "symbol64" end
    if typ == "R_X86_64_32" or typ == "R_X86_64_32S" then return "symbol32" end
    if typ == "R_X86_64_PC32" or typ == "R_X86_64_PLT32" then return symbol and "rel32" or "pc32" end
    return nil
end

local function pattern_escape(s)
    return (tostring(s):gsub("([^%w])", "%%%1"))
end

local function function_pointer_signature(decl, symbol)
    decl = tostring(decl or ""):gsub("\n", " ")
    symbol = tostring(symbol or "")
    local ret, args = decl:match("^%s*(.-)%s+" .. pattern_escape(symbol) .. "%s*%((.*)%)%s*;?%s*$")
    if ret == nil then error("stencil_bank: cannot derive function pointer signature for " .. symbol .. " from " .. decl, 3) end
    return ret .. " (*)(" .. args .. ")"
end

local function parse_relocations(readelf_output)
    local current
    local by_section = {}
    for line in tostring(readelf_output or ""):gmatch("[^\n]+") do
        local sec = line:match("Relocation section '([^']+)'")
        if sec ~= nil then
            current = sec
            by_section[current] = by_section[current] or {}
        else
            local off, typ, rest = line:match("^%s*([0-9a-fA-F]+)%s+[%x]+%s+(R_%S+)%s+(.+)$")
            if current ~= nil and off ~= nil then
                local fields = {}
                for f in rest:gmatch("%S+") do fields[#fields + 1] = f end
                local symbol, addend
                if #fields >= 2 then
                    local last = fields[#fields]
                    local before = fields[#fields - 1]
                    if before == "+" or before == "-" then
                        addend = (before == "-" and -1 or 1) * parse_int(last)
                        symbol = fields[#fields - 2]
                    else
                        symbol = before
                        addend = 0
                    end
                end
                if symbol == "0" or symbol == "0000000000000000" then symbol = nil end
                local kind = map_reloc_type(typ, symbol)
                if kind ~= nil then
                    by_section[current][#by_section[current] + 1] = {
                        offset = tonumber(off, 16),
                        kind = kind,
                        reloc_type = typ,
                        symbol = symbol,
                        ordinal = symbol_ordinal(symbol),
                        addend = addend or 0,
                    }
                end
            end
        end
    end
    return by_section
end

local function bind_context(T)
    T._moonlift_api_cache = T._moonlift_api_cache or {}
    if T._moonlift_api_cache.stencil_bank ~= nil then return T._moonlift_api_cache.stencil_bank end

    local StencilC = require("moonlift.stencil_c")(T)

    local api = {}

    local function artifact_symbol(artifact)
        assert(artifact and artifact.symbol and artifact.symbol.text, "stencil_bank: artifact missing symbol")
        return artifact.symbol.text
    end

    local function artifact_signature(artifact)
        assert(artifact and artifact.c_signature, "stencil_bank: artifact missing C signature")
        return artifact.c_signature
    end

    local function unique_artifacts(artifacts)
        local out, seen = {}, {}
        for _, artifact in ipairs(artifacts or {}) do
            local symbol = artifact_symbol(artifact)
            if not seen[symbol] then
                out[#out + 1] = artifact
                seen[symbol] = true
            end
        end
        return out
    end

    function api.build_bank(artifacts, opts)
        opts = opts or {}
        artifacts = unique_artifacts(artifacts)
        local dir = opts.dir or "target/stencil_bank"
        os.execute("mkdir -p " .. shell_quote(dir))
        local stem = opts.stem or ("moonlift_stencil_bank_" .. tostring(os.time()) .. "_" .. sanitize(tostring(os.clock())))
        local c_path = dir .. "/" .. stem .. ".c"
        local so_path = dir .. "/" .. stem .. ".so"
        local source = StencilC.source(artifacts)
        write_file(c_path, source)
        local cc = opts.cc or os.getenv("CC") or "gcc"
        local cflags = opts.cflags or "-std=c99 -O3 -march=native -fPIC -shared"
        local cmd = table.concat({ shell_quote(cc), cflags, shell_quote(c_path), "-o", shell_quote(so_path) }, " ")
        local ok = os.execute(cmd)
        if not (ok == true or ok == 0) then return nil, "stencil_bank: build failed: " .. cmd, source end
        local entries = {}
        for _, artifact in ipairs(artifacts) do
            local symbol = artifact_symbol(artifact)
            entries[symbol] = { symbol = symbol, signature = artifact_signature(artifact), artifact = artifact }
        end
        return {
            kind = "StencilBank",
            c_path = c_path,
            so_path = so_path,
            source = source,
            command = cmd,
            entries = entries,
            lib = nil,
            symbols = nil,
        }, nil, source
    end

    function api.build_binary_bank(artifacts, opts)
        opts = opts or {}
        artifacts = unique_artifacts(artifacts)
        local dir = opts.dir or "target/stencil_bank"
        os.execute("mkdir -p " .. shell_quote(dir))
        local stem = opts.stem or ("moonlift_stencil_binary_bank_" .. tostring(os.time()) .. "_" .. sanitize(tostring(os.clock())))
        local c_path = dir .. "/" .. stem .. ".c"
        local o_path = dir .. "/" .. stem .. ".o"
        local source = StencilC.source(artifacts)
        write_file(c_path, source)
        local cc = opts.cc or os.getenv("CC") or "gcc"
        local cflags = opts.cflags or "-std=c99 -O3 -march=native -ffunction-sections -fno-pic -fno-stack-protector -fno-asynchronous-unwind-tables -fno-unwind-tables -c"
        local cmd = table.concat({ shell_quote(cc), cflags, shell_quote(c_path), "-o", shell_quote(o_path) }, " ")
        local ok = os.execute(cmd)
        if not (ok == true or ok == 0) then return nil, "stencil_bank: binary bank object build failed: " .. cmd, source end
        local reloc_out, reloc_err = capture("readelf -Wr " .. shell_quote(o_path))
        if reloc_out == nil then return nil, "stencil_bank: readelf relocations failed: " .. tostring(reloc_err), source end
        local relocs = parse_relocations(reloc_out)
        local entries = {}
        for _, artifact in ipairs(artifacts) do
            local symbol = artifact_symbol(artifact)
            local section = ".text." .. symbol
            local bin_path = dir .. "/" .. stem .. "." .. sanitize(symbol) .. ".bin"
            local dump_cmd = "objcopy --dump-section " .. shell_quote(section .. "=" .. bin_path) .. " " .. shell_quote(o_path)
            local dump_ok = os.execute(dump_cmd)
            if not (dump_ok == true or dump_ok == 0) then
                return nil, "stencil_bank: failed to dump section " .. section .. " for " .. symbol, source
            end
            local binary = read_file(bin_path)
            entries[symbol] = {
                kind = "BinaryStencilEntry",
                symbol = symbol,
                section = section,
                binary = binary,
                c_signature = function_pointer_signature(artifact_signature(artifact), symbol),
                patches = relocs[".rela" .. section] or relocs[".rel" .. section] or {},
                artifact = artifact,
            }
        end
        return {
            kind = "BinaryStencilBank",
            c_path = c_path,
            o_path = o_path,
            source = source,
            command = cmd,
            entries = entries,
        }, nil, source
    end

    function api.load_bank(bank)
        assert(type(bank) == "table", "stencil_bank.load_bank expects a bank")
        if bank.lib ~= nil then return bank end
        local ffi = require("ffi")
        local decls, seen = {}, {}
        for symbol, entry in pairs(bank.entries or {}) do
            if not seen[symbol] then decls[#decls + 1] = entry.signature; seen[symbol] = true end
        end
        if #decls > 0 then pcall(ffi.cdef, table.concat(decls, "\n")) end
        bank.lib = ffi.load(bank.so_path)
        bank.symbols = {}
        for symbol, _entry in pairs(bank.entries or {}) do bank.symbols[symbol] = bank.lib[symbol] end
        return bank
    end

    function api.realize_artifacts(artifacts, opts)
        opts = opts or {}
        local bank = assert(opts.bank, "stencil_bank.realize_artifacts requires opts.bank")
        api.load_bank(bank)
        local symbols = {}
        for _, artifact in ipairs(artifacts or {}) do
            local symbol = artifact_symbol(artifact)
            local fn = bank.symbols and bank.symbols[symbol]
            if fn == nil then return nil, "stencil_bank: missing prebuilt stencil symbol " .. symbol end
            symbols[symbol] = fn
        end
        return { kind = "StencilBankRealization", bank = bank, symbols = symbols }
    end

    function api.realize_or_build(artifacts, opts)
        opts = opts or {}
        if opts.bank ~= nil then return api.realize_artifacts(artifacts, opts) end
        local bank, err, source = api.build_bank(artifacts, opts)
        if bank == nil then return nil, err, source end
        return api.realize_artifacts(artifacts, { bank = bank })
    end

    function api.install_binary_stencil(entry, values, opts)
        opts = opts or {}
        assert(type(entry) == "table", "stencil_bank.install_binary_stencil expects an entry")
        assert(type(entry.binary) == "string", "binary stencil entry requires binary bytes")
        assert(type(entry.c_signature) == "string", "binary stencil entry requires c_signature")
        local ffi = require("ffi")
        local mem, base = mmap_install(entry.binary)
        local base_addr = tonumber(ffi.cast("uintptr_t", mem))
        for _, record in ipairs(entry.patches or {}) do
            local offset = assert(record.offset, "patch record requires offset")
            local kind = assert(record.kind, "patch record requires kind")
            local addend = record.addend or 0
            local value = patch_value(record, values or {})
            if kind == "abs32" or kind == "symbol32" then
                local p = ffi.cast("uint32_t *", base + offset)
                p[0] = p[0] + value + addend
            elseif kind == "abs64" or kind == "symbol64" then
                local p = ffi.cast("uint64_t *", base + offset)
                p[0] = p[0] + ffi.cast("uint64_t", value + addend)
            elseif kind == "pc32" then
                local p = ffi.cast("uint32_t *", base + offset)
                p[0] = p[0] - base_addr + addend
            elseif kind == "rel32" then
                local p = ffi.cast("int32_t *", base + offset)
                local at = base_addr + offset + 4
                p[0] = value + addend - at
            else
                error("stencil_bank: unknown patch kind " .. tostring(kind), 3)
            end
        end
        local fn = ffi.cast(entry.c_signature, mem)
        return { kind = "InstalledBinaryStencil", entry = entry, memory = mem, code = base, size = #entry.binary, fn = fn }
    end

    function api.realize_binary_artifacts(artifacts, opts)
        opts = opts or {}
        local bank = assert(opts.bank, "stencil_bank.realize_binary_artifacts requires opts.bank")
        local symbols, installed = {}, {}
        for _, artifact in ipairs(artifacts or {}) do
            local symbol = artifact_symbol(artifact)
            local entry = bank.entries and bank.entries[symbol]
            if entry == nil then return nil, "stencil_bank: missing binary stencil entry " .. symbol end
            local values = opts.patch_values and (opts.patch_values[symbol] or opts.patch_values[artifact]) or nil
            local inst = api.install_binary_stencil(entry, values or {}, opts)
            installed[#installed + 1] = inst
            symbols[symbol] = inst.fn
        end
        return { kind = "BinaryStencilBankRealization", bank = bank, symbols = symbols, installed = installed }
    end

    function api.realize_binary_or_build(artifacts, opts)
        opts = opts or {}
        local bank = opts.bank
        if bank == nil then
            local err, source
            bank, err, source = api.build_binary_bank(artifacts, opts)
            if bank == nil then return nil, err, source end
        end
        return api.realize_binary_artifacts(artifacts, { bank = bank, patch_values = opts.patch_values })
    end

    T._moonlift_api_cache.stencil_bank = api
    return api
end

return bind_context
