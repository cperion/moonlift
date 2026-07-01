local asdl = require("lalin.asdl")

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
    local MAP_PRIVATE, MAP_ANON, MAP_32BIT = 2, 32, 64
    local MAP_FAILED = ffi.cast("void *", -1)
    local install = opts.install or {}
    local low32 = install.low32 == true
    if low32 and not (ffi.os == "Linux" and ffi.arch == "x64") then
        error("residual_mc: low32 mc stencil installation requires Linux/x64", 3)
    end
    local policy = install.rwx and "rwx" or "write_exec"
    local prot = install.rwx and bit.bor(PROT_READ, PROT_WRITE, PROT_EXEC) or bit.bor(PROT_READ, PROT_WRITE)
    local flags = bit.bor(MAP_PRIVATE, MAP_ANON, low32 and MAP_32BIT or 0)
    local mem = ffi.C.mmap(nil, #bytes, prot, flags, -1, 0)
    if mem == MAP_FAILED then error("residual_mc: mmap failed while installing mc stencil", 3) end
    local base_addr = tonumber(ffi.cast("uintptr_t", mem))
    if low32 and base_addr + #bytes - 1 > 2147483647 then
        error("residual_mc: low32 mc stencil installation returned out-of-range address", 3)
    end
    ffi.copy(mem, bytes, #bytes)
    return mem, ffi.cast("uint8_t *", mem), policy
end

local function lua_string(s)
    return string.format("%q", tostring(s))
end

local function bytes_literal(bytes)
    if #bytes == 0 then return "\"\"" end
    local out = {}
    local chunk = {}
    for i = 1, #bytes do
        chunk[#chunk + 1] = tostring(bytes:byte(i))
        if #chunk == 128 then
            out[#out + 1] = "string.char(" .. table.concat(chunk, ",") .. ")"
            chunk = {}
        end
    end
    if #chunk > 0 then out[#out + 1] = "string.char(" .. table.concat(chunk, ",") .. ")" end
    if #out == 1 then return out[1] end
    return table.concat(out, " .. ")
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
        "    error('lalin luajit artifact target mismatch: built for '",
        "      .. __ml_stencil_target.os .. '/' .. __ml_stencil_target.arch .. '/' .. tostring(__ml_stencil_target.pointer_bits) .. '/' .. __ml_stencil_target.endian",
        "      .. ', loaded on '",
        "      .. tostring(ffi.os) .. '/' .. tostring(ffi.arch) .. '/' .. tostring(runtime_pointer_bits) .. '/' .. tostring(runtime_endian), 0)",
        "  end",
        "end",
        "__ml_check_stencil_target()",
    }, "\n")
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

local function parse_reloc_addend(s)
    if s == nil then return 0 end
    s = tostring(s)
    local sign = 1
    if s:sub(1, 1) == "-" then sign = -1; s = s:sub(2) end
    if s:match("^0x") or s:match("^0X") then return sign * tonumber(s) end
    return sign * (tonumber(s, 16) or tonumber(s) or 0)
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
    if ret == nil then error("residual_mc: cannot derive function pointer signature for " .. symbol .. " from " .. decl, 3) end
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
                        addend = (before == "-" and -1 or 1) * parse_reloc_addend(last)
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
                        reloc_role = kind,
                        reloc_type = typ,
                        symbol = symbol,
                        addend = addend or 0,
                    }
                end
            end
        end
    end
    return by_section
end

local function parse_sections(readelf_output)
    local by_index = {}
    local by_name = {}
    for line in tostring(readelf_output or ""):gmatch("[^\n]+") do
        local idx, name, typ, _addr, off, size, _es, flags, _link, _info, align =
            line:match("^%s*%[%s*(%d+)%]%s+(%S+)%s+(%S+)%s+([0-9a-fA-F]+)%s+([0-9a-fA-F]+)%s+([0-9a-fA-F]+)%s+([0-9a-fA-F]+)%s+(%S*)%s+(%d+)%s+(%d+)%s+(%d+)%s*$")
        if idx ~= nil and name ~= "" then
            local section = {
                index = tonumber(idx),
                name = name,
                typ = typ,
                offset = tonumber(off, 16) or 0,
                size = tonumber(size, 16) or 0,
                flags = flags or "",
                align = tonumber(align) or 1,
            }
            by_index[section.index] = section
            by_name[section.name] = section
        end
    end
    return by_index, by_name
end

local function parse_symbols(readelf_output, sections)
    local by_name = {}
    for line in tostring(readelf_output or ""):gmatch("[^\n]+") do
        local _num, value, size, typ, bind, _vis, ndx, name =
            line:match("^%s*(%d+):%s+([0-9a-fA-F]+)%s+(%d+)%s+(%S+)%s+(%S+)%s+(%S+)%s+(%S+)%s+(.+)%s*$")
        if name ~= nil and name ~= "" and ndx:match("^%d+$") then
            local section = sections[tonumber(ndx)]
            by_name[name] = {
                name = name,
                value = tonumber(value, 16) or 0,
                size = tonumber(size) or 0,
                typ = typ,
                bind = bind,
                section_index = tonumber(ndx),
                section = section and section.name or nil,
                section_flags = section and section.flags or "",
                section_align = section and section.align or 1,
            }
        end
    end
    return by_name
end

local function align_up(n, align)
    align = tonumber(align) or 1
    if align <= 1 then return n end
    local rem = n % align
    if rem == 0 then return n end
    return n + align - rem
end

local function patch_u32le(bytes, offset, value)
    if value < -2147483648 or value > 4294967295 then
        error("residual_mc: local relocation value out of 32-bit range: " .. tostring(value), 3)
    end
    if value < 0 then value = 4294967296 + value end
    local b0 = value % 256
    value = math.floor(value / 256)
    local b1 = value % 256
    value = math.floor(value / 256)
    local b2 = value % 256
    value = math.floor(value / 256)
    local b3 = value % 256
    local i = offset + 1
    return bytes:sub(1, i - 1) .. string.char(b0, b1, b2, b3) .. bytes:sub(i + 4)
end

local function bind_context(T)
    T._lalin_api_cache = T._lalin_api_cache or {}
    if T._lalin_api_cache.residual_mc ~= nil then return T._lalin_api_cache.residual_mc end

    local StencilC = require("lalin.stencil_c")(T)
    local ArtifactPlan = require("lalin.stencil_artifact_plan")(T)
    local Meta = require("lalin.stencil_metastencil")(T)
    local Code = T.LalinCode
    local Value = T.LalinValue
    local Stencil = T.LalinStencil
    local LJ = T.LalinLuaJIT
    local Residual = T.LalinResidual

    local api = {}
    local ffi_preambles = {}

    local function typed_reloc_patch(raw)
        if raw.reloc_role == "rel32" and raw.symbol ~= nil then
            return Residual.ResidualRelocPatchRel32(raw.offset, raw.reloc_type, raw.symbol, raw.addend or 0)
        end
        return Residual.ResidualRelocPatchUnsupported(
            raw.offset or 0,
            raw.reloc_type or "unknown",
            raw.symbol,
            raw.addend or 0,
            raw.reloc_role or "unsupported_relocation"
        )
    end

    local function typed_relocation_sections(raw_relocs)
        local out = {}
        for section, patches in pairs(raw_relocs or {}) do
            local typed = {}
            for _, patch in ipairs(patches or {}) do
                typed[#typed + 1] = typed_reloc_patch(patch)
            end
            out[section] = typed
        end
        return out
    end

    function Residual.ResidualRelocPatch:materialize_local_relocation(_blob, _site, _target_addr)
        error("residual_mc: unsupported local relocation", 3)
    end

    function Residual.ResidualRelocPatchRel32:materialize_local_relocation(blob, site, target_addr)
        return patch_u32le(blob, site, target_addr + (self.addend or 0) - site)
    end

    function Residual.ResidualRelocPatchUnsupported:materialize_local_relocation(_blob, _site, _target_addr)
        error("residual_mc: non-relative local relocation " .. tostring(self.reloc_type) .. " to " .. tostring(self.symbol) .. " cannot be represented in a no-patch MC bank", 3)
    end

    local function install_policy(opts, low32)
        opts = opts or {}
        local protection = opts.install_policy == "rwx" and LJ.LJMCInstallReadWriteExec or LJ.LJMCInstallWriteThenExec
        local address = (low32 or opts.low32 == true) and LJ.LJMCInstallLow32Address or LJ.LJMCInstallAnyAddress
        return LJ.LJMCInstallPolicy(address, protection)
    end

    local function install_opts(policy)
        policy = policy or install_policy()
        return {
            low32 = policy.address == LJ.LJMCInstallLow32Address,
            rwx = policy.protection == LJ.LJMCInstallReadWriteExec,
        }
    end

    local function requested_install(opts, bank)
        if opts and opts.install then return opts.install end
        if opts and opts.install_policy ~= nil then return install_policy(opts, bank and bank.install and bank.install.address == LJ.LJMCInstallLow32Address) end
        return bank and bank.install or install_policy()
    end

    local function target_for(opts)
        opts = opts or {}
        local ffi = require("ffi")
        return LJ.LJMCTarget(
            opts.arch or ffi.arch,
            opts.os or ffi.os,
            opts.abi or "c",
            opts.pointer_bits or (ffi.abi("64bit") and 64 or 32),
            opts.endian or (ffi.abi("le") and "little" or "big")
        )
    end

    local function bank_id(stem)
        return LJ.LJMCBankId("ljbank:" .. tostring(stem))
    end

    local function artifact_symbol(artifact)
        assert(artifact and artifact.symbol and artifact.symbol.text, "residual_mc: artifact missing symbol")
        return artifact.symbol.text
    end

    local function artifact_signature(artifact)
        assert(artifact and artifact.c_signature, "residual_mc: artifact missing C signature")
        return artifact.c_signature
    end

    local function is_i32(ty)
        return asdl.classof(ty) == Code.CodeTyInt and tonumber(ty.bits) == 32 and ty.signedness == Code.CodeSigned
    end

    function Stencil.StencilReduceExecutionScope:residual_mc_is_domain_reduce()
        return false
    end

    function Stencil.StencilReduceExecDomain:residual_mc_is_domain_reduce()
        return true
    end

    function Stencil.StencilArtifactShape:residual_mc_explicit_vector_path()
        return false
    end

    function Stencil.StencilArtifactReduceN:residual_mc_explicit_vector_path(artifact)
        if not self.reduce_scope:residual_mc_is_domain_reduce() then return false end
        if self.reduction ~= Value.ReductionAdd then return false end
        if not is_i32(self.item_ty) or not is_i32(self.result_ty) then return false end
        if tonumber(self.stride) ~= 1 then return false end
        local xs = ArtifactPlan.access_named(artifact.instance.descriptor, "xs")
        local top = asdl.classof(xs.layout)
        return top == Stencil.StencilLayoutContiguous or top == Stencil.StencilLayoutSliceDescriptor
    end

    local function explicit_vector_mc_path(artifact)
        local schedule = artifact.instance and artifact.instance.schedule
        if asdl.classof(schedule) ~= Stencil.StencilScheduleVector then return false end
        local shape = ArtifactPlan.artifact_shape(artifact)
        return shape:residual_mc_explicit_vector_path(artifact)
    end

    local function realized_mc_schedule(artifact, cflags)
        local schedule = artifact.instance and artifact.instance.schedule
        local evidence = {
            Stencil.StencilRealizedByConstruction("MC copy+compile residual materializer built object code"),
        }
        if cflags ~= nil and cflags ~= "" then
            evidence[#evidence + 1] = Stencil.StencilRealizedCompilerRemark("cflags: " .. tostring(cflags))
        end
        if explicit_vector_mc_path(artifact) then
            local lanes = assert(ArtifactPlan.schedule_lane_count(schedule), "residual_mc: vector schedule requires fixed lane policy for realized MC schedule")
            return Stencil.StencilRealizedVector(
                schedule.feature,
                lanes,
                schedule.vector_unroll,
                schedule.interleave,
                schedule.tail,
                Stencil.StencilMaterializerResidualMC,
                evidence
            )
        end
        if asdl.classof(schedule) == Stencil.StencilScheduleUnrolled then
            return Stencil.StencilRealizedUnrolled(schedule.factor, Stencil.StencilMaterializerResidualMC, evidence)
        end
        return Stencil.StencilRealizedScalar(Stencil.StencilMaterializerResidualMC, evidence)
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

    function api.build_mc_bank(artifacts, opts)
        opts = opts or {}
        local metastencil_covers
        artifacts, metastencil_covers = Meta.normalize_artifact_inputs(artifacts or {})
        artifacts = unique_artifacts(artifacts)
        local dir = opts.dir or "target/residual_mc"
        os.execute("mkdir -p " .. shell_quote(dir))
        local stem = opts.stem or ("lalin_stencil_mc_bank_" .. tostring(os.time()) .. "_" .. sanitize(tostring(os.clock())))
        local c_path = dir .. "/" .. stem .. ".c"
        local o_path = dir .. "/" .. stem .. ".o"
        local source = StencilC.source(artifacts, { c_decls = opts.c_decls or opts.decls })
        write_file(c_path, source)
        local cc = opts.cc or os.getenv("CC") or "gcc"
        local cflags = opts.cflags or "-std=c99 -O3 -march=native -fno-builtin -fno-builtin-memmove -fno-builtin-memcpy -fno-builtin-memset -ffunction-sections -fno-pic -fno-jump-tables -fno-stack-protector -fno-asynchronous-unwind-tables -fno-unwind-tables -c"
        local cmd = table.concat({ shell_quote(cc), cflags, shell_quote(c_path), "-o", shell_quote(o_path) }, " ")
        local ok = os.execute(cmd)
        if not (ok == true or ok == 0) then return nil, "residual_mc: MC bank object build failed: " .. cmd, source end
        local reloc_out, reloc_err = capture("readelf -Wr " .. shell_quote(o_path))
        if reloc_out == nil then return nil, "residual_mc: readelf relocations failed: " .. tostring(reloc_err), source end
        local relocs = typed_relocation_sections(parse_relocations(reloc_out))
        local section_out, section_err = capture("readelf -SW " .. shell_quote(o_path))
        if section_out == nil then return nil, "residual_mc: readelf sections failed: " .. tostring(section_err), source end
        local sections, sections_by_name = parse_sections(section_out)
        local symbol_out, symbol_err = capture("readelf -Ws " .. shell_quote(o_path))
        if symbol_out == nil then return nil, "residual_mc: readelf symbols failed: " .. tostring(symbol_err), source end
        local symbols = parse_symbols(symbol_out, sections)
        local dumped_sections = {}
        local object_bytes

        local function dump_section(section)
            local cached = dumped_sections[section]
            if cached ~= nil then return cached end
            local meta = sections_by_name[section]
            if meta == nil then error("residual_mc: missing object section " .. tostring(section), 3) end
            if object_bytes == nil then object_bytes = read_file(o_path) end
            cached = object_bytes:sub(meta.offset + 1, meta.offset + meta.size)
            dumped_sections[section] = cached
            return cached
        end

        local function local_symbol_target(symbol)
            if symbol == nil then return nil end
            local sym = symbols[symbol]
            if sym ~= nil and sym.section ~= nil and sym.section ~= "UND" then
                return { section = sym.section, offset = sym.value or 0, align = sym.section_align or 1 }
            end
            local sec = sections_by_name[symbol]
            if sec ~= nil then return { section = sec.name, offset = 0, align = sec.align or 1 } end
            return nil
        end

        local function materialize_local_sections(text_section, binary, patches)
            local blob = binary
            local local_offsets = { [text_section] = { offset = 0, align = 1 } }
            local processing = {}

            local function section_offset(section, align)
                local existing = local_offsets[section]
                if existing ~= nil then return existing.offset end
                local aligned = align_up(#blob, align)
                if aligned > #blob then blob = blob .. string.rep("\0", aligned - #blob) end
                local offset = #blob
                blob = blob .. dump_section(section)
                local_offsets[section] = { offset = offset, align = align or 1 }
                return offset
            end

            local function process_patches(section, section_patches)
                local section_base = section_offset(section, 1)
                for _, patch in ipairs(section_patches or {}) do
                    local site = section_base + patch.offset
                    local target = local_symbol_target(patch.symbol)
                    if target ~= nil then
                        local base = section_offset(target.section, target.align)
                        local target_addr = base + target.offset
                        if target.section ~= section and not processing[target.section] then
                            processing[target.section] = true
	                            process_patches(target.section, relocs[".rela" .. target.section] or relocs[".rel" .. target.section] or {})
	                            processing[target.section] = nil
	                        end
                        blob = patch:materialize_local_relocation(blob, site, target_addr)
                    else
                        error("residual_mc: unresolved relocation " .. tostring(patch.reloc_type) .. " to " .. tostring(patch.symbol) .. " cannot be represented in a no-patch MC bank", 3)
                    end
                end
            end

            processing[text_section] = true
            process_patches(text_section, patches)
            processing[text_section] = nil
            return blob
        end

        local entries = {}
        for _, artifact in ipairs(artifacts) do
            local symbol = artifact_symbol(artifact)
            local section = ".text." .. symbol
            local section_meta = sections_by_name[section]
            if section_meta == nil then
                return nil, "residual_mc: missing section " .. section .. " for " .. symbol, source
            end
            local binary = dump_section(section)
            local raw_patches = relocs[".rela" .. section] or relocs[".rel" .. section] or {}
            binary = materialize_local_sections(section, binary, raw_patches)
            local realized_artifact = ArtifactPlan.artifact_with_realized(artifact, Stencil.StencilProviderC, realized_mc_schedule(artifact, cflags))
            entries[#entries + 1] = LJ.LJMCStencilEntry(
                symbol,
                section,
                binary,
                function_pointer_signature(artifact_signature(artifact), symbol),
                realized_artifact
            )
        end
        local bank = LJ.LJMCStencilBank(
            bank_id(stem),
            target_for(opts),
            install_policy(opts, false),
            c_path,
            o_path,
            source,
            cmd,
            opts.ffi_preamble,
            entries,
            metastencil_covers
        )
        return bank, nil, source
    end

    function api.embedded_mc_bank_for(artifacts, opts)
        opts = opts or {}
        local metastencil_covers
        artifacts, metastencil_covers = Meta.normalize_artifact_inputs(artifacts or {})
        artifacts = unique_artifacts(artifacts)
        if #artifacts == 0 then
            return LJ.LJMCStencilBank(
                bank_id("embedded"),
                target_for(opts),
                install_policy(opts, false),
                "<embedded>",
                "<embedded>",
                "",
                "",
                opts.ffi_preamble,
                {},
                metastencil_covers or {}
            )
        end
        return nil, "residual_mc: embedded exact MC stencil bank was removed; use the patch-template bank path"
    end

    function api.entry_for(bank, symbol)
        symbol = tostring(symbol)
        for _, entry in ipairs(bank.entries or {}) do
            if entry.symbol == symbol then return entry end
        end
        return nil
    end

    function api.install_mc_stencil(entry, opts)
        opts = opts or {}
        assert(type(entry) == "table", "residual_mc.install_mc_stencil expects an entry")
        assert(type(entry.binary) == "string", "mc stencil entry requires binary bytes")
        assert(type(entry.c_signature) == "string", "mc stencil entry requires c_signature")
        local ffi = require("ffi")
        local mem, base, policy = mmap_install(entry.binary, opts)
        if policy ~= "rwx" then
            local ok = ffi.C.mprotect(mem, #entry.binary, 5)
            if ok ~= 0 then error("residual_mc: mprotect failed while sealing mc stencil", 3) end
        end
        local fn = ffi.cast(entry.c_signature, mem)
        return { kind = "InstalledMCStencil", entry = entry, memory = mem, code = base, size = #entry.binary, fn = fn }
    end

    function api.realize_mc_artifacts(artifacts, opts)
        opts = opts or {}
        local metastencil_covers
        artifacts, metastencil_covers = Meta.normalize_artifact_inputs(artifacts or {})
        local bank = assert(opts.mc_bank, "residual_mc.realize_mc_artifacts requires opts.mc_bank")
        local ffi_preamble = opts.ffi_preamble or bank.ffi_preamble
        if type(ffi_preamble) ~= "string" then ffi_preamble = nil end
        if ffi_preamble ~= nil and ffi_preamble ~= "" and not ffi_preambles[ffi_preamble] then
            require("ffi").cdef(ffi_preamble)
            ffi_preambles[ffi_preamble] = true
        end
        local symbols, installed = {}, {}
        for _, artifact in ipairs(artifacts or {}) do
            local symbol = artifact_symbol(artifact)
            local entry = api.entry_for(bank, symbol)
            if entry == nil then return nil, "residual_mc: missing mc stencil entry " .. symbol end
            if entry.artifact == nil or entry.artifact.fingerprint == nil or entry.artifact.fingerprint.text == nil then
                return nil, "residual_mc: bank entry missing artifact fingerprint for " .. symbol
            end
            if artifact.fingerprint == nil or artifact.fingerprint.text == nil then
                return nil, "residual_mc: requested artifact missing fingerprint for " .. symbol
            end
            if entry.artifact.fingerprint.text ~= artifact.fingerprint.text then
                return nil, "residual_mc: artifact fingerprint mismatch for " .. symbol
            end
            local inst = api.install_mc_stencil(entry, {
                install = install_opts(requested_install(opts, bank)),
            })
            installed[#installed + 1] = inst
            symbols[symbol] = inst.fn
        end
        return {
            kind = "MCStencilBankRealization",
            mc_bank = bank,
            symbols = symbols,
            installed = installed,
            metastencil_covers = metastencil_covers or bank.metastencil_covers or {},
        }
    end

    function api.emit_mc_bank_source(bank, opts)
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
        out[#out + 1] = "]])"
        if bank.ffi_preamble ~= nil and bank.ffi_preamble ~= "" then
            out[#out + 1] = "pcall(ffi.cdef, " .. lua_string(bank.ffi_preamble) .. ")"
        end
        out[#out + 1] = target_guard_source(bank.target)
        out[#out + 1] = "local PROT_READ, PROT_WRITE, PROT_EXEC = 1, 2, 4"
        out[#out + 1] = "local MAP_PRIVATE, MAP_ANON, MAP_32BIT = 2, 32, 64"
        out[#out + 1] = "local MAP_FAILED = ffi.cast('void *', -1)"
        local install = install_opts(bank.install)
        out[#out + 1] = "local __ml_install_policy = { low32 = " .. tostring(install.low32) .. ", rwx = " .. tostring(install.rwx) .. " }"
        out[#out + 1] = "local function __ml_install(entry)"
        out[#out + 1] = "  if __ml_install_policy.low32 and not (ffi.os == 'Linux' and ffi.arch == 'x64') then error('lalin artifact: low32 stencil installation requires Linux/x64') end"
        out[#out + 1] = "  local prot = __ml_install_policy.rwx and bit.bor(PROT_READ, PROT_WRITE, PROT_EXEC) or bit.bor(PROT_READ, PROT_WRITE)"
        out[#out + 1] = "  local flags = bit.bor(MAP_PRIVATE, MAP_ANON, __ml_install_policy.low32 and MAP_32BIT or 0)"
        out[#out + 1] = "  local mem = ffi.C.mmap(nil, #entry.binary, prot, flags, -1, 0)"
        out[#out + 1] = "  if mem == MAP_FAILED then error('lalin artifact: mmap failed while installing stencil') end"
        out[#out + 1] = "  ffi.copy(mem, entry.binary, #entry.binary)"
        out[#out + 1] = "  local base_addr = tonumber(ffi.cast('uintptr_t', mem))"
        out[#out + 1] = "  if __ml_install_policy.low32 and base_addr + #entry.binary - 1 > 2147483647 then error('lalin artifact: low32 stencil installation returned out-of-range address') end"
        out[#out + 1] = "  if not __ml_install_policy.rwx and ffi.C.mprotect(mem, #entry.binary, bit.bor(PROT_READ, PROT_EXEC)) ~= 0 then error('lalin artifact: mprotect failed while sealing stencil') end"
        out[#out + 1] = "  return ffi.cast(entry.c_signature, mem)"
        out[#out + 1] = "end"
        out[#out + 1] = "local __lalin_luajit_stencil_symbols = {}"
        for _, entry in ipairs(bank.entries or {}) do
            out[#out + 1] = "do"
            out[#out + 1] = "  local entry = {"
            out[#out + 1] = "    symbol = " .. lua_string(entry.symbol) .. ","
            out[#out + 1] = "    c_signature = " .. lua_string(entry.c_signature) .. ","
            out[#out + 1] = "    binary = " .. bytes_literal(entry.binary) .. ","
            out[#out + 1] = "  }"
            out[#out + 1] = "  __lalin_luajit_stencil_symbols[entry.symbol] = __ml_install(entry)"
            out[#out + 1] = "end"
        end
        return table.concat(out, "\n") .. "\n"
    end

    function api.write_lua_bank(bank, path, opts)
        local source = api.emit_mc_bank_source(bank, opts or {})
        mkdir_parent(path)
        write_file(path, source)
        return source
    end

    T._lalin_api_cache.residual_mc = api
    return api
end

return bind_context
