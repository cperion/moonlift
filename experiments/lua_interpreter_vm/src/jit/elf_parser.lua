-- ELF object file parser for extracting function bytes and relocations.
--
-- This module parses x86-64 ELF files produced by Moonlift's emit_object()
-- to extract:
--   - Function symbols (name, offset, size)
--   - Raw function code bytes
--   - Relocation entries (offset, type, symbol)

local M = {}

local function read_u8(data, offset)
    return string.byte(data, offset)
end

local function read_u16_le(data, offset)
    local b1, b2 = string.byte(data, offset, offset + 1)
    return b1 + b2 * 256
end

local function read_u32_le(data, offset)
    local b1, b2, b3, b4 = string.byte(data, offset, offset + 3)
    return b1 + b2 * 256 + b3 * 65536 + b4 * 16777216
end

local function read_u64_le(data, offset)
    local lo = read_u32_le(data, offset)
    local hi = read_u32_le(data, offset + 4)
    return lo + hi * 4294967296
end

local function read_cstring(data, offset)
    local i = offset
    while i <= #data and string.byte(data, i) ~= 0 do
        i = i + 1
    end
    return string.sub(data, offset, i - 1)
end

function M.parse(data)
    if type(data) ~= "string" then
        return nil, "data must be a string (bytes)"
    end

    if #data < 64 then
        return nil, "data too small for ELF header"
    end

    -- ELF header
    local magic = string.sub(data, 1, 4)
    if magic ~= "\x7fELF" then
        return nil, "invalid ELF magic"
    end

    local ei_class = read_u8(data, 5)      -- 1=32-bit, 2=64-bit
    local ei_data = read_u8(data, 6)       -- 1=LE, 2=BE
    local ei_version = read_u8(data, 7)    -- should be 1
    local ei_osabi = read_u8(data, 8)

    if ei_class ~= 2 then
        return nil, "only 64-bit ELF supported"
    end

    if ei_data ~= 1 then
        return nil, "only little-endian ELF supported"
    end

    local e_type = read_u16_le(data, 17)       -- 1=REL, 2=EXEC, 3=DYN, 4=CORE
    local e_machine = read_u16_le(data, 19)    -- 0x3E=x86-64
    local e_version = read_u32_le(data, 21)
    local e_entry = read_u64_le(data, 25)
    local e_phoff = read_u64_le(data, 33)
    local e_shoff = read_u64_le(data, 41)
    local e_flags = read_u32_le(data, 49)
    local e_ehsize = read_u16_le(data, 53)
    local e_phentsize = read_u16_le(data, 55)
    local e_phnum = read_u16_le(data, 57)
    local e_shentsize = read_u16_le(data, 59)
    local e_shnum = read_u16_le(data, 61)
    local e_shstrndx = read_u16_le(data, 63)

    -- Read section headers
    local sections = {}
    for i = 0, e_shnum - 1 do
        local sh_offset = e_shoff + i * e_shentsize
        if sh_offset + 64 > #data then
            return nil, "truncated section header"
        end

        local sh_name = read_u32_le(data, sh_offset + 1)
        local sh_type = read_u32_le(data, sh_offset + 5)
        local sh_flags = read_u64_le(data, sh_offset + 9)
        local sh_addr = read_u64_le(data, sh_offset + 17)
        local sh_offset_real = read_u64_le(data, sh_offset + 25)
        local sh_size = read_u64_le(data, sh_offset + 33)
        local sh_link = read_u32_le(data, sh_offset + 41)
        local sh_info = read_u32_le(data, sh_offset + 45)
        local sh_addralign = read_u64_le(data, sh_offset + 49)
        local sh_entsize = read_u64_le(data, sh_offset + 57)

        sections[i] = {
            name_offset = sh_name,
            type = sh_type,
            flags = sh_flags,
            addr = sh_addr,
            offset = sh_offset_real,
            size = sh_size,
            link = sh_link,
            info = sh_info,
            addralign = sh_addralign,
            entsize = sh_entsize,
            index = i,
        }
    end

    -- Read string table for section names
    local shstrtab_sec = sections[e_shstrndx]
    local section_names = {}
    if shstrtab_sec and shstrtab_sec.offset + shstrtab_sec.size <= #data then
        local strtab_data = string.sub(data, shstrtab_sec.offset + 1,
                                       shstrtab_sec.offset + shstrtab_sec.size)
        for i, sec in ipairs(sections) do
            if sec.name_offset + 1 <= #strtab_data then
                local name_end = sec.name_offset
                while name_end < #strtab_data and string.byte(strtab_data, name_end + 1) ~= 0 do
                    name_end = name_end + 1
                end
                sec.name = string.sub(strtab_data, sec.name_offset + 1, name_end)
            end
        end
    end

    -- Find key sections
    local text_sec, symtab_sec, strtab_sec, rel_secs = nil, nil, nil, {}
    for i, sec in ipairs(sections) do
        if sec.name == ".text" then text_sec = sec
        elseif sec.name == ".symtab" then symtab_sec = sec
        elseif sec.name == ".strtab" then strtab_sec = sec
        elseif sec.name and string.match(sec.name, "^%.rel%.") then
            rel_secs[#rel_secs + 1] = sec
        elseif sec.name and string.match(sec.name, "^%.rela%.") then
            rel_secs[#rel_secs + 1] = sec
        end
    end

    -- Read string table
    local strings = {}
    if strtab_sec and strtab_sec.offset + strtab_sec.size <= #data then
        local strtab_data = string.sub(data, strtab_sec.offset + 1,
                                       strtab_sec.offset + strtab_sec.size)
        local i = 1
        while i <= #strtab_data do
            local j = i
            while j <= #strtab_data and string.byte(strtab_data, j) ~= 0 do
                j = j + 1
            end
            strings[i - 1] = string.sub(strtab_data, i, j - 1)
            i = j + 1
        end
    end

    -- Read symbol table
    local symbols = {}
    if symtab_sec and symtab_sec.offset + symtab_sec.size <= #data then
        local symtab_data = string.sub(data, symtab_sec.offset + 1,
                                       symtab_sec.offset + symtab_sec.size)
        local sym_count = math.floor(symtab_sec.size / symtab_sec.entsize)

        for i = 0, sym_count - 1 do
            local sym_offset = i * symtab_sec.entsize
            if sym_offset + 16 <= #symtab_data then
                local st_name = read_u32_le(symtab_data, sym_offset + 1)
                local st_info = read_u8(symtab_data, sym_offset + 5)
                local st_other = read_u8(symtab_data, sym_offset + 6)
                local st_shndx = read_u16_le(symtab_data, sym_offset + 7)
                local st_value = read_u64_le(symtab_data, sym_offset + 9)
                local st_size = read_u64_le(symtab_data, sym_offset + 17)

                local st_bind = math.floor(st_info / 16)      -- upper 4 bits
                local st_type = st_info % 16                  -- lower 4 bits

                symbols[i] = {
                    name_offset = st_name,
                    name = strings[st_name] or "",
                    bind = st_bind,                           -- 0=local, 1=global, 2=weak
                    type = st_type,                           -- 0=notype, 1=object, 2=func, ...
                    shndx = st_shndx,                         -- section index
                    value = st_value,                         -- offset in section
                    size = st_size,
                    index = i,
                }
            end
        end
    end

    -- Read relocations
    local relocs_by_name = {}
    for _, rel_sec in ipairs(rel_secs) do
        if rel_sec.offset + rel_sec.size <= #data then
            local rel_data = string.sub(data, rel_sec.offset + 1,
                                       rel_sec.offset + rel_sec.size)
            local rel_count = math.floor(rel_sec.size / rel_sec.entsize)

            for i = 0, rel_count - 1 do
                local rel_offset = i * rel_sec.entsize
                local r_offset, r_info, r_addend = 0, 0, 0

                -- RELA format: offset(8) info(8) addend(8)
                -- REL format: offset(8) info(8)
                if string.match(rel_sec.name, "^%.rela%.") then
                    if rel_offset + 24 <= #rel_data then
                        r_offset = read_u64_le(rel_data, rel_offset + 1)
                        r_info = read_u64_le(rel_data, rel_offset + 9)
                        r_addend = read_u64_le(rel_data, rel_offset + 17)
                    end
                else
                    if rel_offset + 16 <= #rel_data then
                        r_offset = read_u64_le(rel_data, rel_offset + 1)
                        r_info = read_u64_le(rel_data, rel_offset + 9)
                    end
                end

                local r_sym = math.floor(r_info / 256)
                local r_type = r_info % 256

                relocs_by_name[#relocs_by_name + 1] = {
                    offset = r_offset,
                    sym_index = r_sym,
                    sym_name = (symbols[r_sym] and symbols[r_sym].name) or "",
                    type = r_type,
                    addend = r_addend,
                }
            end
        end
    end

    -- Extract functions
    local functions = {}
    if text_sec then
        local text_data = string.sub(data, text_sec.offset + 1,
                                     text_sec.offset + text_sec.size)

        for _, sym in ipairs(symbols) do
            -- Only include function symbols in .text
            if sym.type == 2 and sym.shndx == text_sec.index and
               sym.name ~= "" and sym.size > 0 then
                local start_offset = sym.value + 1
                local end_offset = start_offset + sym.size - 1

                if end_offset <= #text_data then
                    local func_bytes = string.sub(text_data, start_offset, end_offset)

                    -- Find relocations for this function
                    local func_relocs = {}
                    for _, rel in ipairs(relocs_by_name) do
                        if rel.offset >= sym.value and rel.offset < sym.value + sym.size then
                            func_relocs[#func_relocs + 1] = {
                                offset = rel.offset - sym.value,
                                sym_name = rel.sym_name,
                                type = rel.type,
                                addend = rel.addend,
                            }
                        end
                    end

                    functions[#functions + 1] = {
                        name = sym.name,
                        offset = sym.value,
                        size = sym.size,
                        bytes = func_bytes,
                        relocations = func_relocs,
                    }
                end
            end
        end
    end

    return {
        header = {
            machine = e_machine,
            type = e_type,
        },
        sections = sections,
        symbols = symbols,
        functions = functions,
        raw_data = data,
    }
end

-- Utility to convert bytes to hex string (for JSON)
function M.bytes_to_hex(bytes, sep)
    sep = sep or " "
    local out = {}
    for i = 1, #bytes do
        out[#out + 1] = string.format("%02x", string.byte(bytes, i))
    end
    return table.concat(out, sep)
end

-- Utility to describe relocation type (x86-64)
function M.reloc_type_name(rel_type)
    local types = {
        [0] = "R_X86_64_NONE",
        [1] = "R_X86_64_64",
        [2] = "R_X86_64_PC32",
        [3] = "R_X86_64_GOT32",
        [4] = "R_X86_64_PLT32",
        [5] = "R_X86_64_COPY",
        [6] = "R_X86_64_GLOB_DAT",
        [7] = "R_X86_64_JUMP_SLOT",
        [8] = "R_X86_64_RELATIVE",
        [9] = "R_X86_64_GOTPCREL",
        [10] = "R_X86_64_32",
        [11] = "R_X86_64_32S",
        [12] = "R_X86_64_16",
        [13] = "R_X86_64_PC16",
        [14] = "R_X86_64_8",
        [15] = "R_X86_64_PC8",
    }
    return types[rel_type] or string.format("UNKNOWN(%d)", rel_type)
end

return M
