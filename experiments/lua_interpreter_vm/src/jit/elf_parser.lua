-- Minimal ELF/object parser for Lua VM JIT stencil mining.
-- Uses host binutils for function byte extraction while keeping a Lua-facing API.

local M = {}

local function u16le(s, off)
    local a, b = s:byte(off + 1, off + 2)
    return (a or 0) + 256 * (b or 0)
end

local function shell_quote(s)
    return "'" .. tostring(s):gsub("'", [['"'"']]) .. "'"
end

local function run(cmd)
    local p = io.popen(cmd .. " 2>&1", "r")
    if not p then return nil, "popen failed" end
    local out = p:read("*a")
    local ok, why, code = p:close()
    if ok == true or ok == 0 then return out end
    return nil, out .. tostring(why or "") .. tostring(code or "")
end

local function tmp_object(bytes)
    local path = os.tmpname() .. ".o"
    local f, err = io.open(path, "wb")
    if not f then return nil, err end
    f:write(bytes)
    f:close()
    return path
end

local function parse_symbols(path)
    local out = run("nm -S --defined-only " .. shell_quote(path)) or ""
    local syms = {}
    for line in out:gmatch("[^\n]+") do
        local addr, size, typ, name = line:match("^%s*([0-9a-fA-F]+)%s+([0-9a-fA-F]+)%s+([%a])%s+(.+)$")
        if addr and size and (typ == "T" or typ == "t") then
            syms[name] = { name = name, addr = tonumber(addr, 16) or 0, size = tonumber(size, 16) or 0 }
        end
    end
    return syms
end

local function parse_disassembly(path, syms)
    local out = run("objdump -d -r " .. shell_quote(path)) or ""
    local current
    for line in out:gmatch("[^\n]+") do
        local addr, name = line:match("^%s*([0-9a-fA-F]+)%s+<([^>]+)>:")
        if addr and name then
            current = syms[name]
            if current then current.offset = tonumber(addr, 16) or current.addr; current.bytes_parts = {}; current.relocations = {} end
        elseif current then
            local off, hex = line:match("^%s*([0-9a-fA-F]+):%s*([0-9a-fA-F ]+)%s+")
            if off and hex then
                for byte in hex:gmatch("%x%x") do current.bytes_parts[#current.bytes_parts + 1] = string.char(tonumber(byte, 16)) end
            else
                local roff, rtype, rsym = line:match("^%s*([0-9a-fA-F]+):?%s+([%w_%-]+)%s+(.+)$")
                if roff and rtype and rsym and rtype:match("^R_") then
                    current.relocations[#current.relocations + 1] = { offset = tonumber(roff, 16) or 0, type = rtype, sym_name = rsym:gsub("%s+$", "") }
                end
            end
        end
    end
end

function M.parse(bytes)
    if type(bytes) ~= "string" or #bytes < 20 then return nil, "not enough bytes" end
    if bytes:sub(1, 4) ~= "\127ELF" then return nil, "not an ELF object" end
    local path, err = tmp_object(bytes)
    if not path then return nil, err end
    local syms = parse_symbols(path)
    parse_disassembly(path, syms)
    os.remove(path)

    local functions = {}
    for _, sym in pairs(syms) do
        sym.bytes = table.concat(sym.bytes_parts or {})
        sym.bytes_parts = nil
        sym.offset = sym.offset or sym.addr
        sym.relocations = sym.relocations or {}
        table.insert(functions, sym)
    end
    table.sort(functions, function(a, b) return a.offset < b.offset end)

    return {
        header = { class = bytes:byte(5), endian = bytes:byte(6), type = u16le(bytes, 16), machine = u16le(bytes, 18) },
        functions = functions,
    }
end

function M.bytes_to_hex(bytes)
    local out = {}
    for i = 1, #bytes do out[#out + 1] = string.format("%02x", bytes:byte(i)) end
    return table.concat(out, " ")
end

function M.reloc_type_name(t)
    return tostring(t)
end

return M
