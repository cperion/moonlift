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

local function mkdir_parent(path)
    local dir = tostring(path):match("^(.*)/[^/]+$")
    if dir ~= nil and dir ~= "" then os.execute("mkdir -p " .. shell_quote(dir)) end
end

local function capture(cmd)
    local f = assert(io.popen(cmd .. " 2>&1", "r"))
    local out = f:read("*a")
    local ok, _, code = f:close()
    if ok == true or ok == 0 then return out end
    return nil, out, code
end

local function mmap_install(bytes, opts)
    opts = opts or {}
    local ffi = require("ffi")
    local bit = require("bit")
    pcall(ffi.cdef, [[
typedef signed char int8_t;
typedef unsigned char uint8_t;
typedef short int16_t;
typedef unsigned short uint16_t;
typedef unsigned int uint32_t;
typedef int int32_t;
typedef long long int64_t;
typedef unsigned long uint64_t;
typedef unsigned long size_t;
typedef long intptr_t;
typedef unsigned long uintptr_t;
void *mmap(void *addr, size_t length, int prot, int flags, int fd, intptr_t offset);
int mprotect(void *addr, size_t len, int prot);
]])
    local PROT_READ, PROT_WRITE, PROT_EXEC = 1, 2, 4
    local MAP_PRIVATE, MAP_ANON = 2, 32
    local MAP_FAILED = ffi.cast("void *", -1)
    local policy = opts.install_policy or "write_exec"
    local prot = policy == "rwx" and bit.bor(PROT_READ, PROT_WRITE, PROT_EXEC) or bit.bor(PROT_READ, PROT_WRITE)
    local mem = ffi.C.mmap(nil, #bytes, prot, bit.bor(MAP_PRIVATE, MAP_ANON), -1, 0)
    if mem == MAP_FAILED then error("stencil_bank: mmap failed while installing binary stencil", 3) end
    ffi.copy(mem, bytes, #bytes)
    return mem, ffi.cast("uint8_t *", mem), policy
end

local function lua_string(s)
    return string.format("%q", tostring(s))
end

local function bytes_literal(bytes)
    local out = {}
    for i = 1, #bytes do out[#out + 1] = tostring(bytes:byte(i)) end
    return "string.char(" .. table.concat(out, ",") .. ")"
end

local function number_map_literal(values)
    if values == nil then return "{}" end
    local out = { "{" }
    for k, v in pairs(values) do
        if type(v) == "number" then
            if type(k) == "number" then
                out[#out + 1] = "[" .. tostring(k) .. "] = " .. tostring(v) .. ","
            else
                out[#out + 1] = "[" .. lua_string(k) .. "] = " .. tostring(v) .. ","
            end
        end
    end
    out[#out + 1] = "}"
    return table.concat(out, " ")
end

local function target_guard_source(target)
    target = target or {}
    local arch = target.arch or "unknown"
    local os_name = target.os or "unknown"
    local abi = target.abi or "c"
    local pointer_bits = target.pointer_bits or 0
    local endian = target.endian or "unknown"
    return table.concat({
        "local __ml_stencil_target = {",
        "  arch = " .. lua_string(arch) .. ",",
        "  os = " .. lua_string(os_name) .. ",",
        "  abi = " .. lua_string(abi) .. ",",
        "  pointer_bits = " .. tostring(pointer_bits) .. ",",
        "  endian = " .. lua_string(endian) .. ",",
        "}",
        "local function __ml_check_stencil_target()",
        "  local runtime_pointer_bits = ffi.abi('64bit') and 64 or 32",
        "  local runtime_endian = ffi.abi('le') and 'little' or 'big'",
        "  if ffi.arch ~= __ml_stencil_target.arch or ffi.os ~= __ml_stencil_target.os or runtime_pointer_bits ~= __ml_stencil_target.pointer_bits or runtime_endian ~= __ml_stencil_target.endian then",
        "    error('moonlift luajit artifact target mismatch: built for '",
        "      .. __ml_stencil_target.os .. '/' .. __ml_stencil_target.arch .. '/' .. tostring(__ml_stencil_target.pointer_bits) .. '/' .. __ml_stencil_target.endian",
        "      .. ', loaded on '",
        "      .. tostring(ffi.os) .. '/' .. tostring(ffi.arch) .. '/' .. tostring(runtime_pointer_bits) .. '/' .. tostring(runtime_endian), 0)",
        "  end",
        "end",
        "__ml_check_stencil_target()",
    }, "\n")
end

local function symbol_ordinal(symbol)
    symbol = tostring(symbol or "")
    return tonumber(symbol:match("[Pp][Aa][Tt][Cc][Hh]_?(%d+)$"))
        or tonumber(symbol:match("[Hh][Oo][Ll][Ee]_?(%d+)$"))
        or tonumber(symbol:match("__ml_patch_?(%d+)$"))
end

local runtime_symbol_cdef_done = false

local function runtime_symbol_value(symbol)
    symbol = tostring(symbol or "")
    if symbol ~= "memmove" and symbol ~= "memcpy" and symbol ~= "memset" then return nil end
    local ffi = require("ffi")
    if not runtime_symbol_cdef_done then
        pcall(ffi.cdef, [[
typedef unsigned long size_t;
void *memmove(void *dst, const void *src, size_t n);
void *memcpy(void *dst, const void *src, size_t n);
void *memset(void *dst, int c, size_t n);
]])
        runtime_symbol_cdef_done = true
    end
    local ok, fn = pcall(function() return ffi.C[symbol] end)
    if not ok or fn == nil then return nil end
    return tonumber(ffi.cast("uintptr_t", fn))
end

local function patch_value(record, values)
    if record.value ~= nil then return record.value end
    if record.ordinal ~= nil then
        local v = values and values[record.ordinal]
        if v == nil then error("stencil_bank: missing patch ordinal " .. tostring(record.ordinal), 4) end
        return v
    end
    if record.symbol ~= nil and values ~= nil and values[record.symbol] ~= nil then return values[record.symbol] end
    if record.symbol ~= nil then
        local value = runtime_symbol_value(record.symbol)
        if value ~= nil then return value end
    end
    if record.symbol ~= nil then
        error("stencil_bank: missing patch symbol " .. tostring(record.symbol), 4)
    end
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
    local LJ = T.MoonLuaJIT

    local api = {}
    local ffi_preambles = {}

    local function patch_kind_name(kind)
        if kind == LJ.LJPatchAbs32 then return "abs32" end
        if kind == LJ.LJPatchAbs64 then return "abs64" end
        if kind == LJ.LJPatchSymbol32 then return "symbol32" end
        if kind == LJ.LJPatchSymbol64 then return "symbol64" end
        if kind == LJ.LJPatchPc32 then return "pc32" end
        if kind == LJ.LJPatchRel32 then return "rel32" end
        return tostring(kind)
    end

    local function patch_kind(kind)
        if kind == "abs32" then return LJ.LJPatchAbs32 end
        if kind == "abs64" then return LJ.LJPatchAbs64 end
        if kind == "symbol32" then return LJ.LJPatchSymbol32 end
        if kind == "symbol64" then return LJ.LJPatchSymbol64 end
        if kind == "pc32" then return LJ.LJPatchPc32 end
        if kind == "rel32" then return LJ.LJPatchRel32 end
        error("stencil_bank: unknown binary patch kind " .. tostring(kind), 3)
    end

    local function target_for(opts)
        opts = opts or {}
        local ffi = require("ffi")
        return LJ.LJBinaryTarget(
            opts.arch or ffi.arch,
            opts.os or ffi.os,
            opts.abi or "c",
            opts.pointer_bits or (ffi.abi("64bit") and 64 or 32),
            opts.endian or (ffi.abi("le") and "little" or "big")
        )
    end

    local function bank_id(stem)
        return LJ.LJBinaryBankId("ljbank:" .. tostring(stem))
    end

    local function as_patch_record(record)
        if pvm.classof(record) == LJ.LJBinaryPatchRecord then return record end
        return LJ.LJBinaryPatchRecord(
            assert(record.offset, "patch record requires offset"),
            patch_kind(assert(record.kind, "patch record requires kind")),
            record.reloc_type,
            record.symbol,
            record.ordinal,
            record.addend or 0
        )
    end

    local function patch_record_kind(record)
        return patch_kind_name(record.kind)
    end

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

    function api.build_binary_bank(artifacts, opts)
        opts = opts or {}
        artifacts = unique_artifacts(artifacts)
        local dir = opts.dir or "target/stencil_bank"
        os.execute("mkdir -p " .. shell_quote(dir))
        local stem = opts.stem or ("moonlift_stencil_binary_bank_" .. tostring(os.time()) .. "_" .. sanitize(tostring(os.clock())))
        local c_path = dir .. "/" .. stem .. ".c"
        local o_path = dir .. "/" .. stem .. ".o"
        local source = StencilC.source(artifacts, { preamble = opts.preamble })
        write_file(c_path, source)
        local cc = opts.cc or os.getenv("CC") or "gcc"
        local cflags = opts.cflags or "-std=c99 -O3 -march=native -fno-tree-vectorize -fno-builtin -fno-builtin-memmove -fno-builtin-memcpy -fno-builtin-memset -ffunction-sections -fno-pic -fno-stack-protector -fno-asynchronous-unwind-tables -fno-unwind-tables -c"
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
            local raw_entry = {
                symbol = symbol,
                section = section,
                binary = binary,
                c_signature = function_pointer_signature(artifact_signature(artifact), symbol),
                patches = relocs[".rela" .. section] or relocs[".rel" .. section] or {},
                artifact = artifact,
            }
            local patches = {}
            for i, patch in ipairs(raw_entry.patches) do patches[i] = as_patch_record(patch) end
            entries[#entries + 1] = LJ.LJBinaryStencilEntry(
                raw_entry.symbol,
                raw_entry.section,
                raw_entry.binary,
                raw_entry.c_signature,
                patches,
                raw_entry.artifact
            )
        end
        return LJ.LJBinaryStencilBank(
            bank_id(stem),
            target_for(opts),
            c_path,
            o_path,
            source,
            cmd,
            opts.preamble,
            entries
        ), nil, source
    end

    function api.entry_for(bank, symbol)
        symbol = tostring(symbol)
        for _, entry in ipairs(bank.entries or {}) do
            if entry.symbol == symbol then return entry end
        end
        return nil
    end

    function api.install_binary_stencil(entry, values, opts)
        opts = opts or {}
        assert(type(entry) == "table", "stencil_bank.install_binary_stencil expects an entry")
        assert(type(entry.binary) == "string", "binary stencil entry requires binary bytes")
        assert(type(entry.c_signature) == "string", "binary stencil entry requires c_signature")
        local ffi = require("ffi")
        local mem, base, policy = mmap_install(entry.binary, opts)
        local base_addr = tonumber(ffi.cast("uintptr_t", mem))
        for _, record in ipairs(entry.patches or {}) do
            local offset = assert(record.offset, "patch record requires offset")
            local kind = patch_record_kind(record)
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
        if policy ~= "rwx" then
            local ok = ffi.C.mprotect(mem, #entry.binary, 5)
            if ok ~= 0 then error("stencil_bank: mprotect failed while sealing binary stencil", 3) end
        end
        local fn = ffi.cast(entry.c_signature, mem)
        return { kind = "InstalledBinaryStencil", entry = entry, memory = mem, code = base, size = #entry.binary, fn = fn }
    end

    function api.realize_binary_artifacts(artifacts, opts)
        opts = opts or {}
        local bank = assert(opts.bank, "stencil_bank.realize_binary_artifacts requires opts.bank")
        local ffi_preamble = opts.ffi_preamble or opts.preamble or bank.preamble
        if ffi_preamble ~= nil and ffi_preamble ~= "" and not ffi_preambles[ffi_preamble] then
            require("ffi").cdef(ffi_preamble)
            ffi_preambles[ffi_preamble] = true
        end
        local symbols, installed = {}, {}
        for _, artifact in ipairs(artifacts or {}) do
            local symbol = artifact_symbol(artifact)
            local entry = api.entry_for(bank, symbol)
            if entry == nil then return nil, "stencil_bank: missing binary stencil entry " .. symbol end
            local values = opts.patch_values and (opts.patch_values[symbol] or opts.patch_values[artifact]) or nil
            local inst = api.install_binary_stencil(entry, values or {}, {
                install_policy = opts.install_policy,
            })
            installed[#installed + 1] = inst
            symbols[symbol] = inst.fn
        end
        return { kind = "BinaryStencilBankRealization", bank = bank, symbols = symbols, installed = installed }
    end

    function api.emit_lua_bank_source(bank, opts)
        opts = opts or {}
        local out = {}
        out[#out + 1] = "local ffi = require('ffi')"
        out[#out + 1] = "local bit = require('bit')"
        out[#out + 1] = "pcall(ffi.cdef, [["
        out[#out + 1] = "typedef signed char int8_t;"
        out[#out + 1] = "typedef unsigned char uint8_t;"
        out[#out + 1] = "typedef short int16_t;"
        out[#out + 1] = "typedef unsigned short uint16_t;"
        out[#out + 1] = "typedef int int32_t;"
        out[#out + 1] = "typedef unsigned int uint32_t;"
        out[#out + 1] = "typedef long long int64_t;"
        out[#out + 1] = "typedef unsigned long uint64_t;"
        out[#out + 1] = "typedef unsigned long size_t;"
        out[#out + 1] = "typedef long intptr_t;"
        out[#out + 1] = "typedef unsigned long uintptr_t;"
        out[#out + 1] = "void *mmap(void *addr, size_t length, int prot, int flags, int fd, intptr_t offset);"
        out[#out + 1] = "int mprotect(void *addr, size_t len, int prot);"
        out[#out + 1] = "void *memmove(void *dst, const void *src, size_t n);"
        out[#out + 1] = "void *memcpy(void *dst, const void *src, size_t n);"
        out[#out + 1] = "void *memset(void *dst, int c, size_t n);"
        out[#out + 1] = "]])"
        if bank.preamble ~= nil and bank.preamble ~= "" then
            out[#out + 1] = "pcall(ffi.cdef, " .. lua_string(bank.preamble) .. ")"
        end
        out[#out + 1] = target_guard_source(bank.target)
        out[#out + 1] = "local function __ml_runtime_symbol(name)"
        out[#out + 1] = "  if name ~= 'memmove' and name ~= 'memcpy' and name ~= 'memset' then return nil end"
        out[#out + 1] = "  local ok, fn = pcall(function() return ffi.C[name] end)"
        out[#out + 1] = "  if not ok or fn == nil then return nil end"
        out[#out + 1] = "  return tonumber(ffi.cast('uintptr_t', fn))"
        out[#out + 1] = "end"
        out[#out + 1] = "local PROT_READ, PROT_WRITE, PROT_EXEC = 1, 2, 4"
        out[#out + 1] = "local MAP_PRIVATE, MAP_ANON = 2, 32"
        out[#out + 1] = "local MAP_FAILED = ffi.cast('void *', -1)"
        out[#out + 1] = "local function __ml_install(entry, values)"
        out[#out + 1] = "  local mem = ffi.C.mmap(nil, #entry.binary, bit.bor(PROT_READ, PROT_WRITE), bit.bor(MAP_PRIVATE, MAP_ANON), -1, 0)"
        out[#out + 1] = "  if mem == MAP_FAILED then error('moonlift artifact: mmap failed while installing stencil') end"
        out[#out + 1] = "  ffi.copy(mem, entry.binary, #entry.binary)"
        out[#out + 1] = "  local base = ffi.cast('uint8_t *', mem)"
        out[#out + 1] = "  local base_addr = tonumber(ffi.cast('uintptr_t', mem))"
        out[#out + 1] = "  values = values or {}"
        out[#out + 1] = "  for _, r in ipairs(entry.patches or {}) do"
        out[#out + 1] = "    local v = r.value"
        out[#out + 1] = "    if v == nil and r.ordinal then v = values[r.ordinal] end"
        out[#out + 1] = "    if v == nil and r.symbol then v = values[r.symbol] end"
        out[#out + 1] = "    if v == nil and r.symbol then v = __ml_runtime_symbol(r.symbol) end"
        out[#out + 1] = "    if v == nil and (r.ordinal or r.symbol) then error('moonlift artifact: missing patch value for '..tostring(r.symbol or r.ordinal)) end"
        out[#out + 1] = "    v = v or 0"
        out[#out + 1] = "    local addend = r.addend or 0"
        out[#out + 1] = "    if r.kind == 'abs32' or r.kind == 'symbol32' then ffi.cast('uint32_t *', base + r.offset)[0] = ffi.cast('uint32_t *', base + r.offset)[0] + v + addend"
        out[#out + 1] = "    elseif r.kind == 'abs64' or r.kind == 'symbol64' then ffi.cast('uint64_t *', base + r.offset)[0] = ffi.cast('uint64_t', v + addend)"
        out[#out + 1] = "    elseif r.kind == 'pc32' then ffi.cast('uint32_t *', base + r.offset)[0] = ffi.cast('uint32_t *', base + r.offset)[0] - base_addr + addend"
        out[#out + 1] = "    elseif r.kind == 'rel32' then ffi.cast('int32_t *', base + r.offset)[0] = v + addend - (base_addr + r.offset + 4)"
        out[#out + 1] = "    else error('moonlift artifact: unknown patch kind '..tostring(r.kind)) end"
        out[#out + 1] = "  end"
        out[#out + 1] = "  if ffi.C.mprotect(mem, #entry.binary, bit.bor(PROT_READ, PROT_EXEC)) ~= 0 then error('moonlift artifact: mprotect failed while sealing stencil') end"
        out[#out + 1] = "  return ffi.cast(entry.c_signature, mem)"
        out[#out + 1] = "end"
        out[#out + 1] = "local __moonlift_luajit_stencil_symbols = {}"
        for _, entry in ipairs(bank.entries or {}) do
            local patch_values = opts.patch_values and opts.patch_values[entry.symbol] or nil
            out[#out + 1] = "do"
            out[#out + 1] = "  local entry = {"
            out[#out + 1] = "    symbol = " .. lua_string(entry.symbol) .. ","
            out[#out + 1] = "    c_signature = " .. lua_string(entry.c_signature) .. ","
            out[#out + 1] = "    binary = " .. bytes_literal(entry.binary) .. ","
            out[#out + 1] = "    patches = {"
            for _, patch in ipairs(entry.patches or {}) do
                out[#out + 1] = "      { offset = " .. tostring(patch.offset) .. ", kind = " .. lua_string(patch_record_kind(patch)) .. ", reloc_type = " .. lua_string(patch.reloc_type or "") .. ", symbol = " .. (patch.symbol and lua_string(patch.symbol) or "nil") .. ", ordinal = " .. (patch.ordinal and tostring(patch.ordinal) or "nil") .. ", addend = " .. tostring(patch.addend or 0) .. " },"
            end
            out[#out + 1] = "    },"
            out[#out + 1] = "    patch_values = " .. number_map_literal(patch_values) .. ","
            out[#out + 1] = "  }"
            out[#out + 1] = "  __moonlift_luajit_stencil_symbols[entry.symbol] = __ml_install(entry, entry.patch_values)"
            out[#out + 1] = "end"
        end
        return table.concat(out, "\n") .. "\n"
    end

    function api.write_lua_bank(bank, path, opts)
        local source = api.emit_lua_bank_source(bank, opts or {})
        mkdir_parent(path)
        write_file(path, source)
        return source
    end

    T._moonlift_api_cache.stencil_bank = api
    return api
end

return bind_context
