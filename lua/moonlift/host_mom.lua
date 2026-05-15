-- moonlift/host_mom.lua — moon.mom() API for the MOM frontend.
--
-- Compiles Moonlift source through the native MOM pipeline and returns a
-- compiled module (same interface as the Lua frontend's compiled modules).
--
-- Usage:
--   local moon = require("moonlift.host_mom")
--   local compiled = moon([[
--     func add(x: i32, y: i32) -> i32
--       return x + y
--     end
--   ]])
--   local add = ffi.cast("int32_t (*)(int32_t, int32_t)", compiled:get("add"))
--   print(add(3, 4))  -- 7
--   compiled:free()

local ffi = require("ffi")
local Host = require("moonlift.mlua_run")

ffi.cdef[[
typedef struct moonlift_bytes_t { uint8_t* data; size_t len; } moonlift_bytes_t;

const char* moonlift_last_error_message(void);
int moonlift_object_compile_binary(const uint8_t* data, size_t len, const char* module_name, moonlift_bytes_t* out);
void moonlift_bytes_free(uint8_t* data, size_t len);

typedef struct MomWireBuilder {
    uint8_t *data;
    size_t len;
    size_t cap;
    int32_t string_count;
    int32_t aux_count;
    int32_t error;
} MomWireBuilder;

typedef struct NativeParseOut {
    int32_t *state;
    int32_t *type_tag; int32_t *type_tok; int32_t *type_a; int32_t *type_b; int32_t *type_c;
    int32_t *expr_tag; int32_t *expr_tok; int32_t *expr_a; int32_t *expr_b; int32_t *expr_c; int32_t *expr_d;
    int32_t *stmt_tag; int32_t *stmt_tok; int32_t *stmt_a; int32_t *stmt_b; int32_t *stmt_c; int32_t *stmt_d; int32_t *stmt_e;
    int32_t *item_tag; int32_t *item_tok; int32_t *item_a; int32_t *item_b; int32_t *item_c; int32_t *item_d; int32_t *item_e;
    int32_t *param_name; int32_t *param_type;
    int32_t *field_name; int32_t *field_type;
    int32_t *jarg_name; int32_t *jarg_expr;
    int32_t *expr_list; int32_t *stmt_list; int32_t *type_list;
    int32_t *issue_tag; int32_t *issue_tok;
    size_t cap_nodes; size_t cap_lists;
} NativeParseOut;
]]

local MOM_DIR = "lua/moonlift/mom/"

local function load_mom(path)
    local full = MOM_DIR .. path
    local embedded = rawget(_G, "_MOONLIFT_EMBEDDED_MLUA")
    if embedded ~= nil and embedded[full] ~= nil then
        return Host.loadstring(embedded[full], full)()
    end
    return Host.dofile(full)
end

local function compile_mod(path)
    local mod = load_mom(path)
    local compiled, err = mod:compile()
    assert(compiled, "moonlift.host_mom: compile " .. path .. ": " .. tostring(err))
    return compiled
end

local function alloc_parse_out(cap)
    local out_c = ffi.new("NativeParseOut")
    local owner = { c = out_c }
    local function arr(name)
        local a = ffi.new("int32_t[?]", cap)
        owner[name] = a
        out_c[name] = a
    end
    arr("state")
    for _, name in ipairs({
        "type_tag", "type_tok", "type_a", "type_b", "type_c",
        "expr_tag", "expr_tok", "expr_a", "expr_b", "expr_c", "expr_d",
        "stmt_tag", "stmt_tok", "stmt_a", "stmt_b", "stmt_c", "stmt_d", "stmt_e",
        "item_tag", "item_tok", "item_a", "item_b", "item_c", "item_d", "item_e",
        "param_name", "param_type", "field_name", "field_type", "jarg_name", "jarg_expr",
        "expr_list", "stmt_list", "type_list", "issue_tag", "issue_tok",
    }) do arr(name) end
    out_c.cap_nodes = cap
    out_c.cap_lists = cap
    return owner
end

local function last_error()
    local ok, msg = pcall(function()
        local p = ffi.C.moonlift_last_error_message()
        return p ~= nil and ffi.string(p) or nil
    end)
    if ok and msg then return msg end
    local ok_lib, lib = pcall(ffi.load, "./target/release/libmoonlift.so")
    if ok_lib then
        local p = lib.moonlift_last_error_message()
        if p ~= nil then return ffi.string(p) end
    end
    return "unknown MOM backend error"
end

local function object_lib()
    local ok = pcall(function()
        local out = ffi.new("moonlift_bytes_t[1]")
        return ffi.C.moonlift_object_compile_binary(nil, 0, nil, out)
    end)
    if ok then return ffi.C end
    local ok_lib, lib = pcall(ffi.load, "./target/release/libmoonlift.so")
    assert(ok_lib, "moonlift.host_mom: object backend symbols are unavailable")
    return lib
end

-- Pre-compile MOM modules once at load time.
local lexer_mod = compile_mod("parser/native_lexer.mlua")
local parser_mod = compile_mod("parser/native_core.mlua")
local lower_mod = compile_mod("driver/lower_wire.mlua")
local backend_mod = compile_mod("driver/backend_ffi.mlua")

local mom_lex = lexer_mod:get("mom_lex_into")
local mom_parse = parser_mod:get("mom_parse_native_core")
local mom_lower_wire = lower_mod:get("mom_lower_native_core_to_wire")
local mom_compile_binary = backend_mod:get("mom_backend_compile_binary")
local mom_getpointer = backend_mod:get("mom_backend_getpointer")
local mom_free_artifact = backend_mod:get("mom_backend_free_artifact")

local function build_wire(source)
    source = tostring(source)

    local cap = math.max(#source * 2, 256)
    local src_buf = ffi.new("uint8_t[?]", #source + 1, source)
    local kinds = ffi.new("int32_t[?]", cap)
    local starts = ffi.new("int32_t[?]", cap)
    local stops = ffi.new("int32_t[?]", cap)
    local lines = ffi.new("int32_t[?]", cap)
    local cols = ffi.new("int32_t[?]", cap)
    local ntok = tonumber(mom_lex(src_buf, #source, kinds, starts, stops, lines, cols, cap))
    assert(ntok and ntok > 0 and ntok < cap, "lex failed")

    local out = alloc_parse_out(cap)
    local nitems = tonumber(mom_parse(src_buf, #source, kinds, starts, stops, ntok, out.c))
    assert(nitems and nitems > 0, "parse failed or produced no items")
    assert(out.c.state[5] == 0, "parse issues: state[5]=" .. tonumber(out.c.state[5]))

    local wire_cap = cap * 16
    local wire = ffi.new("uint8_t[?]", wire_cap)
    local wb = ffi.new("MomWireBuilder")
    local nwire = tonumber(mom_lower_wire(src_buf, starts, stops, out.c, nitems, wb, wire, wire_cap))
    assert(wb.error == 0, "wire error: " .. tonumber(wb.error))
    assert(nwire and nwire > 16, "wire produced no output")
    return wire, nwire
end

local function mom_compile(source)
    local wire, nwire = build_wire(source)
    local artifact = mom_compile_binary(wire, nwire)
    if artifact == nil or artifact == ffi.NULL then
        error("moonlift MOM compile failed: " .. (last_error()))
    end

    local compiled = {
        _artifact = artifact,
    }

    function compiled:get(name)
        local ptr = mom_getpointer(self._artifact, ffi.new("char[?]", #name + 1, name))
        assert(ptr ~= nil and ptr ~= ffi.NULL, "function '" .. name .. "' not found in compiled module")
        return ptr
    end

    function compiled:free()
        if self._artifact ~= nil and self._artifact ~= ffi.NULL then
            mom_free_artifact(self._artifact)
            self._artifact = ffi.NULL
        end
    end

    return compiled
end

local HostMom = {}

function HostMom.wire(source)
    return build_wire(source)
end

function HostMom.emit_object(source, path, module_name)
    local payload = build_wire(source)
    local buf = ffi.new("uint8_t[?]", #payload + 1, payload)
    local out = ffi.new("moonlift_bytes_t[1]")
    local lib = object_lib()
    local rc = lib.moonlift_object_compile_binary(buf, #payload, ffi.new("char[?]", #(module_name or "mom_object") + 1, module_name or "mom_object"), out)
    if rc == 0 then error("moonlift MOM object compile failed: " .. last_error()) end
    local bytes = ffi.string(out[0].data, tonumber(out[0].len))
    lib.moonlift_bytes_free(out[0].data, out[0].len)
    if path ~= nil then
        local f = assert(io.open(path, "wb"))
        f:write(bytes)
        f:close()
    end
    return bytes
end

return setmetatable(HostMom, {
    __call = function(_, source)
        return mom_compile(source)
    end,
})
