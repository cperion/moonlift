package.path = table.concat({
    "./?.lua",
    "./?/init.lua",
    "./lua/?.lua",
    "./lua/?/init.lua",
    package.path,
}, ";")

local out_c = assert(arg[1], "usage: luajit tools/gen_lalin_mc_bank.lua OUT_C OUT_H")
local out_h = assert(arg[2], "usage: luajit tools/gen_lalin_mc_bank.lua OUT_C OUT_H")

local asdl = require("lalin.asdl")
local Schema = require("lalin.schema")

local T = asdl.context()
Schema(T)

local InternSet = require("lalin.residual_mc_intern_set")(T)

local function shell_quote(s)
    return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

local function mkdir_parent(path)
    local dir = tostring(path):match("^(.*)/[^/]+$")
    if dir ~= nil and dir ~= "" then os.execute("mkdir -p " .. shell_quote(dir)) end
end

local function write_file(path, text)
    mkdir_parent(path)
    local f = assert(io.open(path, "wb"))
    f:write(text)
    f:close()
end

local function c_string(s)
    if s == nil then return "NULL" end
    return string.format("%q", tostring(s))
end

local function emit_header()
    return table.concat({
        "#ifndef LALIN_EMBEDDED_MC_BANK_H",
        "#define LALIN_EMBEDDED_MC_BANK_H",
        "",
        "#include <stddef.h>",
        "#include \"lua.h\"",
        "",
        "typedef struct LalinEmbeddedMCTemplateEntry {",
        "  const char *family_key;",
        "  const char *instance_id;",
        "  size_t estimated_template_bytes;",
        "  size_t coordinate_count;",
        "} LalinEmbeddedMCTemplateEntry;",
        "",
        "const LalinEmbeddedMCTemplateEntry *lalin_embedded_mc_template_bank_entries(void);",
        "size_t lalin_embedded_mc_template_bank_count(void);",
        "size_t lalin_embedded_mc_template_bank_estimated_bytes(void);",
        "size_t lalin_embedded_mc_template_bank_coordinate_count(void);",
        "int lalin_install_embedded_mc_bank(lua_State *L);",
        "",
        "#endif",
        "",
    }, "\n")
end

local function template_bank()
    local request = InternSet.request({
        max_templates = tonumber(os.getenv("LALIN_MC_BANK_MAX_TEMPLATES") or ""),
        input_count_max = tonumber(os.getenv("LALIN_MC_BANK_INPUT_MAX") or "") or 3,
    })
    return request:template_bank()
end

local function emit_source(bank)
    local out = {
        "#include <stddef.h>",
        "#include \"lua.h\"",
        "#include \"lauxlib.h\"",
        "#include \"" .. tostring(out_h):match("([^/]+)$") .. "\"",
        "",
        "static const LalinEmbeddedMCTemplateEntry lalin_mc_template_entries[] = {",
    }
    for _, entry in ipairs(bank.entries or {}) do
        out[#out + 1] = string.format(
            "  { %s, %s, %u, %u },",
            c_string(entry.family:patch_template_key()),
            c_string(entry.template_instance.id.text),
            entry.estimated_template_bytes,
            entry.coordinate_count
        )
    end
    out[#out + 1] = "  { NULL, NULL, 0, 0 },"
    out[#out + 1] = "};"
    out[#out + 1] = ""
    out[#out + 1] = "const LalinEmbeddedMCTemplateEntry *lalin_embedded_mc_template_bank_entries(void) {"
    out[#out + 1] = "  return lalin_mc_template_entries;"
    out[#out + 1] = "}"
    out[#out + 1] = ""
    out[#out + 1] = "size_t lalin_embedded_mc_template_bank_count(void) {"
    out[#out + 1] = "  return " .. tostring(bank.template_count) .. ";"
    out[#out + 1] = "}"
    out[#out + 1] = ""
    out[#out + 1] = "size_t lalin_embedded_mc_template_bank_estimated_bytes(void) {"
    out[#out + 1] = "  return " .. tostring(bank.estimated_template_bytes) .. ";"
    out[#out + 1] = "}"
    out[#out + 1] = ""
    out[#out + 1] = "size_t lalin_embedded_mc_template_bank_coordinate_count(void) {"
    out[#out + 1] = "  return " .. tostring(bank.coordinate_count) .. ";"
    out[#out + 1] = "}"
    out[#out + 1] = ""
    out[#out + 1] = "int lalin_install_embedded_mc_bank(lua_State *L) {"
    out[#out + 1] = "  lua_pushinteger(L, (lua_Integer)lalin_embedded_mc_template_bank_count());"
    out[#out + 1] = "  lua_setfield(L, LUA_REGISTRYINDEX, \"lalin.embedded_mc_bank.count\");"
    out[#out + 1] = "  lua_pushinteger(L, (lua_Integer)lalin_embedded_mc_template_bank_estimated_bytes());"
    out[#out + 1] = "  lua_setfield(L, LUA_REGISTRYINDEX, \"lalin.embedded_mc_template_bank.estimated_bytes\");"
    out[#out + 1] = "  lua_pushinteger(L, (lua_Integer)lalin_embedded_mc_template_bank_coordinate_count());"
    out[#out + 1] = "  lua_setfield(L, LUA_REGISTRYINDEX, \"lalin.embedded_mc_template_bank.coordinate_count\");"
    out[#out + 1] = "  return 0;"
    out[#out + 1] = "}"
    out[#out + 1] = ""
    return table.concat(out, "\n")
end

local bank = template_bank()
write_file(out_h, emit_header())
write_file(out_c, emit_source(bank))
io.stderr:write(
    "embedded ", tostring(bank.template_count),
    " Lalin MC patch-template bank entries, ",
    tostring(bank.estimated_template_bytes),
    " estimated template bytes, ",
    tostring(bank.coordinate_count),
    " patch coordinates\n"
)
