package.path = table.concat({
    "./?.lua",
    "./?/init.lua",
    "./lua/?.lua",
    "./lua/?/init.lua",
    package.path,
}, ";")

local out_c = assert(arg[1], "usage: luajit tools/gen_lalin_mc_bank.lua OUT_C OUT_H")
local out_h = assert(arg[2], "usage: luajit tools/gen_lalin_mc_bank.lua OUT_C OUT_H")
local script_path = arg[0] or "tools/gen_lalin_mc_bank.lua"

local pvm = require("lalin.pvm")
local Schema = require("lalin.schema")

local T = pvm.context()
Schema(T)

local LJ = T.LalinLuaJIT
local InternSet = require("lalin.copy_patch_mc_intern_set")(T)
local Bank = require("lalin.copy_patch_mc")(T)

local embedded_mc_cflags = os.getenv("LALIN_MC_BANK_CFLAGS")
    or "-std=c99 -O3 -march=native -fno-builtin -fno-builtin-memmove -fno-builtin-memcpy -fno-builtin-memset -ffunction-sections -fno-pic -fno-stack-protector -fno-asynchronous-unwind-tables -fno-unwind-tables -c"

local function shell_quote(s)
    return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

local function command_ok(cmd)
    local ok = os.execute(cmd)
    return ok == true or ok == 0
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

local function append_text(path, text)
    mkdir_parent(path)
    local f = assert(io.open(path, "ab"))
    f:write(text)
    f:close()
end

local function append_file(dst, src_path)
    local src = assert(io.open(src_path, "rb"))
    while true do
        local chunk = src:read(1024 * 1024)
        if chunk == nil or chunk == "" then break end
        dst:write(chunk)
    end
    src:close()
end

local function read_file(path)
    local f = assert(io.open(path, "rb"))
    local s = f:read("*a")
    f:close()
    return s
end

local function basename(path)
    return tostring(path):match("([^/]+)$") or tostring(path)
end

local function sanitize(s)
    s = tostring(s or "x"):gsub("[^%w_]", "_")
    if s == "" then s = "x" end
    if s:match("^%d") then s = "_" .. s end
    return s
end

local function bounded_text(s, limit)
    s = tostring(s or "")
    limit = limit or 12000
    if #s <= limit then return s end
    local half = math.floor(limit / 2)
    return s:sub(1, half) .. "\n... truncated " .. tostring(#s - limit) .. " bytes ...\n" .. s:sub(#s - half + 1)
end

local function bytes_array(bytes)
    local out, line = {}, {}
    for i = 1, #bytes do
        line[#line + 1] = string.format("0x%02x", bytes:byte(i))
        if #line == 12 then
            out[#out + 1] = "  " .. table.concat(line, ", ") .. ","
            line = {}
        end
    end
    if #line > 0 then out[#out + 1] = "  " .. table.concat(line, ", ") .. "," end
    if #out == 0 then out[1] = "  0x00," end
    return table.concat(out, "\n")
end

local function c_string(s)
    if s == nil then return "NULL" end
    return string.format("%q", tostring(s))
end

local function patch_kind(kind)
    if kind == LJ.LJMCPatchAbs32 then return "abs32" end
    if kind == LJ.LJMCPatchAbs64 then return "abs64" end
    if kind == LJ.LJMCPatchSymbol32 then return "symbol32" end
    if kind == LJ.LJMCPatchSymbol64 then return "symbol64" end
    if kind == LJ.LJMCPatchPc32 then return "pc32" end
    if kind == LJ.LJMCPatchRel32 then return "rel32" end
    if kind == LJ.LJMCPatchLocalAbs32 then return "local_abs32" end
    if kind == LJ.LJMCPatchLocalAbs64 then return "local_abs64" end
    return tostring(kind)
end

local function emit_header()
    return table.concat({
        "#ifndef LALIN_EMBEDDED_MC_BANK_H",
        "#define LALIN_EMBEDDED_MC_BANK_H",
        "",
        "#include <stddef.h>",
        "#include \"lua.h\"",
        "",
        "typedef struct LalinEmbeddedMCPatch {",
        "  size_t offset;",
        "  const char *kind;",
        "  const char *reloc_type;",
        "  const char *symbol;",
        "  int ordinal;",
        "  long long addend;",
        "} LalinEmbeddedMCPatch;",
        "",
        "typedef struct LalinEmbeddedMCEntry {",
        "  const char *symbol;",
        "  const char *c_signature;",
        "  const unsigned char *data;",
        "  size_t size;",
        "  const LalinEmbeddedMCPatch *patches;",
        "  size_t patch_count;",
        "} LalinEmbeddedMCEntry;",
        "",
        "typedef const LalinEmbeddedMCEntry *(*LalinEmbeddedMCShardEntriesFn)(void);",
        "typedef size_t (*LalinEmbeddedMCShardCountFn)(void);",
        "",
        "typedef struct LalinEmbeddedMCShard {",
        "  LalinEmbeddedMCShardEntriesFn entries;",
        "  LalinEmbeddedMCShardCountFn count;",
        "} LalinEmbeddedMCShard;",
        "",
        "const LalinEmbeddedMCShard *lalin_embedded_mc_bank_shards(void);",
        "size_t lalin_embedded_mc_bank_shard_count(void);",
        "size_t lalin_embedded_mc_bank_count(void);",
        "int lalin_install_embedded_mc_bank(lua_State *L);",
        "",
        "#endif",
        "",
    }, "\n")
end

local function bank_fragments(mc_bank)
    local arrays = {}
    local entries = {}
    local payload_bytes = 0
    local patch_count = 0
    for _, entry in ipairs(mc_bank.entries or {}) do
        local sym = "lalin_mc_" .. sanitize(entry.symbol)
        payload_bytes = payload_bytes + #(entry.binary or "")
        patch_count = patch_count + #(entry.patches or {})
        arrays[#arrays + 1] = "static const unsigned char " .. sym .. "_bytes[] = {"
        arrays[#arrays + 1] = bytes_array(entry.binary)
        arrays[#arrays + 1] = "};"
        arrays[#arrays + 1] = "static const LalinEmbeddedMCPatch " .. sym .. "_patches[] = {"
        for _, patch in ipairs(entry.patches or {}) do
            arrays[#arrays + 1] = string.format(
                "  { %d, %s, %s, %s, %d, %d },",
                tonumber(patch.offset) or 0,
                c_string(patch_kind(patch.kind)),
                c_string(patch.reloc_type),
                c_string(patch.symbol),
                tonumber(patch.ordinal) or -1,
                tonumber(patch.addend) or 0
            )
        end
        arrays[#arrays + 1] = "};"
        arrays[#arrays + 1] = ""
        entries[#entries + 1] = string.format(
            "  { %s, %s, %s_bytes, sizeof(%s_bytes), %s_patches, sizeof(%s_patches) / sizeof(%s_patches[0]) },",
            c_string(entry.symbol),
            c_string(entry.c_signature),
            sym,
            sym,
            sym,
            sym,
            sym
        )
    end
    return table.concat(arrays, "\n"), table.concat(entries, "\n"), #(mc_bank.entries or {}), payload_bytes, patch_count
end

local function build_bank(artifacts, stem, dir)
    if #artifacts == 0 then
        return { entries = {} }
    end
    local mc_bank, err, source = Bank.build_mc_bank(artifacts, {
        stem = stem,
        dir = dir,
        c_decls = InternSet.c_decls(),
        ffi_preamble = InternSet.ffi_preamble(),
        cflags = embedded_mc_cflags,
    })
    if mc_bank == nil then
        error(tostring(err) .. "\n" .. bounded_text(source), 0)
    end
    return mc_bank
end

local function shard_prefix_base()
    local dir = tostring(out_c):match("^(.*)/[^/]+$") or "target/lalin_binary"
    local stem = sanitize((basename(out_c):gsub("%.[^.]*$", "")))
    return dir .. "/mc_bank_build/" .. stem
end

local function output_c_stem()
    local dir = tostring(out_c):match("^(.*)/[^/]+$")
    local stem = sanitize((basename(out_c):gsub("%.[^.]*$", "")))
    if dir == nil or dir == "" then return stem end
    return dir .. "/" .. stem
end

local function shard_source_path(i)
    return output_c_stem() .. "_shard_" .. tostring(i) .. ".c"
end

local function build_shard_fragments(shard_index, shard_count, prefix)
    local arrays_path = prefix .. ".arrays.cfrag"
    local entries_path = prefix .. ".entries.cfrag"
    write_file(arrays_path, "")
    write_file(entries_path, "")
    local total = 0
    local payload_bytes = 0
    local patch_count = 0
    InternSet.artifact_batches({
        shard_index = shard_index,
        shard_count = shard_count,
    }, function(artifacts, batch_index)
        local mc_bank = build_bank(
            artifacts,
            "lalin_embedded_mc_bank_shard_" .. tostring(shard_index) .. "_batch_" .. tostring(batch_index),
            prefix .. ".build/batch_" .. tostring(batch_index)
        )
        local arrays, entries, count, batch_payload_bytes, batch_patch_count = bank_fragments(mc_bank)
        append_text(arrays_path, arrays)
        append_text(arrays_path, "\n")
        append_text(entries_path, entries)
        append_text(entries_path, "\n")
        total = total + count
        payload_bytes = payload_bytes + batch_payload_bytes
        patch_count = patch_count + batch_patch_count
        collectgarbage("collect")
        return true
    end)
    write_file(prefix .. ".count", tostring(total) .. "\n")
    write_file(prefix .. ".payload_bytes", tostring(payload_bytes) .. "\n")
    write_file(prefix .. ".patch_count", tostring(patch_count) .. "\n")
    io.stderr:write(
        "embedded shard ", tostring(shard_index), "/", tostring(shard_count),
        ": ", tostring(total), " Lalin MC bank entries, ",
        tostring(payload_bytes), " payload bytes, ",
        tostring(patch_count), " patches\n"
    )
    return {
        prefix = prefix,
        arrays_path = arrays_path,
        entries_path = entries_path,
        count = total,
        payload_bytes = payload_bytes,
        patch_count = patch_count,
    }
end

local function run_worker()
    local shard_index = assert(tonumber(os.getenv("LALIN_MC_BANK_SHARD_INDEX")), "worker missing LALIN_MC_BANK_SHARD_INDEX")
    local shard_count = assert(tonumber(os.getenv("LALIN_MC_BANK_SHARD_COUNT")), "worker missing LALIN_MC_BANK_SHARD_COUNT")
    local prefix = assert(os.getenv("LALIN_MC_BANK_SHARD_PREFIX"), "worker missing LALIN_MC_BANK_SHARD_PREFIX")
    build_shard_fragments(shard_index, shard_count, prefix)
end

local function build_sharded(jobs)
    local prefix = shard_prefix_base()
    mkdir_parent(prefix .. ".sentinel")
    os.execute("rm -f " .. shell_quote(prefix) .. ".shard_" .. "*.cfrag " .. shell_quote(prefix) .. ".shard_" .. "*.count " .. shell_quote(prefix) .. ".shard_" .. "*.payload_bytes " .. shell_quote(prefix) .. ".shard_" .. "*.patch_count " .. shell_quote(prefix) .. ".shard_" .. "*.status " .. shell_quote(prefix) .. ".shard_" .. "*.log " .. shell_quote(prefix) .. ".shard_" .. "*.out")
    local total = 0
    local payload_bytes = 0
    local patch_count = 0
    local shard_prefixes = {}
    local launches = {}
    for i = 1, jobs do
        local shard_prefix = prefix .. ".shard_" .. tostring(i)
        shard_prefixes[#shard_prefixes + 1] = shard_prefix
        local cmd = table.concat({
            "LALIN_MC_BANK_WORKER=1",
            "LALIN_MC_BANK_SHARD_INDEX=" .. tostring(i),
            "LALIN_MC_BANK_SHARD_COUNT=" .. tostring(jobs),
            "LALIN_MC_BANK_SHARD_PREFIX=" .. shell_quote(shard_prefix),
            "luajit",
            shell_quote(script_path),
            shell_quote(out_c),
            shell_quote(out_h),
            ">",
            shell_quote(shard_prefix .. ".out"),
            "2>",
            shell_quote(shard_prefix .. ".log"),
            "&& echo 0 >",
            shell_quote(shard_prefix .. ".status"),
            "|| echo $? >",
            shell_quote(shard_prefix .. ".status"),
        }, " ")
        launches[#launches + 1] = "(" .. cmd .. ") &"
    end
    launches[#launches + 1] = "wait"
    if not command_ok(table.concat(launches, " ")) then
        error("embedded MC bank worker wait failed", 0)
    end
    for i, shard_prefix in ipairs(shard_prefixes) do
        local status = tonumber((read_file(shard_prefix .. ".status"):match("%d+")))
        if status ~= 0 then
            error(
                "embedded MC bank shard " .. tostring(i) .. " failed with status " .. tostring(status) ..
                "\n" .. bounded_text(read_file(shard_prefix .. ".log")),
                0
            )
        end
        total = total + (tonumber(read_file(shard_prefix .. ".count"):match("%d+")) or 0)
        payload_bytes = payload_bytes + (tonumber(read_file(shard_prefix .. ".payload_bytes"):match("%d+")) or 0)
        patch_count = patch_count + (tonumber(read_file(shard_prefix .. ".patch_count"):match("%d+")) or 0)
    end
    return shard_prefixes, total, payload_bytes, patch_count
end

local function detected_jobs()
    local f = io.popen("getconf _NPROCESSORS_ONLN 2>/dev/null", "r")
    if f ~= nil then
        local n = tonumber((f:read("*a") or ""):match("%d+"))
        f:close()
        if n ~= nil and n > 0 then return math.min(n, 16) end
    end
    return 1
end

local function write_shard_source(path, index, arrays_path, entries_path, count)
    mkdir_parent(path)
    local f = assert(io.open(path, "wb"))
    f:write("#include <stddef.h>\n#include \"lua.h\"\n#include \"", basename(out_h), "\"\n\n")
    append_file(f, arrays_path)
    f:write("\n")
    f:write("static const LalinEmbeddedMCEntry lalin_mc_shard_", tostring(index), "_entries[] = {\n")
    append_file(f, entries_path)
    f:write("\n")
    f:write("  { NULL, NULL, NULL, 0, NULL, 0 },\n};\n\n")
    f:write("const LalinEmbeddedMCEntry *lalin_embedded_mc_bank_shard_", tostring(index), "(void) {\n")
    f:write("  return lalin_mc_shard_", tostring(index), "_entries;\n}\n\n")
    f:write("size_t lalin_embedded_mc_bank_shard_", tostring(index), "_count(void) {\n")
    f:write("  return ", tostring(count), ";\n}\n")
    f:close()
end

local function write_index_source(path, shard_count)
    mkdir_parent(path)
    local f = assert(io.open(path, "wb"))
    f:write("#include <stddef.h>\n#include \"lua.h\"\n#include \"", basename(out_h), "\"\n\n")
    for i = 1, shard_count do
        f:write("const LalinEmbeddedMCEntry *lalin_embedded_mc_bank_shard_", tostring(i), "(void);\n")
        f:write("size_t lalin_embedded_mc_bank_shard_", tostring(i), "_count(void);\n")
    end
    f:write("\nstatic const LalinEmbeddedMCShard lalin_mc_shards[] = {\n")
    for i = 1, shard_count do
        f:write("  { lalin_embedded_mc_bank_shard_", tostring(i), ", lalin_embedded_mc_bank_shard_", tostring(i), "_count },\n")
    end
    f:write("};\n\n")
    f:write("const LalinEmbeddedMCShard *lalin_embedded_mc_bank_shards(void) {\n  return lalin_mc_shards;\n}\n\n")
    f:write("size_t lalin_embedded_mc_bank_shard_count(void) {\n  return ", tostring(shard_count), ";\n}\n\n")
    f:write("size_t lalin_embedded_mc_bank_count(void) {\n")
    f:write("  size_t total = 0;\n")
    f:write("  size_t i;\n")
    f:write("  for (i = 0; i < lalin_embedded_mc_bank_shard_count(); ++i) {\n")
    f:write("    total += lalin_mc_shards[i].count();\n")
    f:write("  }\n")
    f:write("  return total;\n")
    f:write("}\n\n")
    f:write("int lalin_install_embedded_mc_bank(lua_State *L) {\n")
    f:write("  lua_pushinteger(L, (lua_Integer)lalin_embedded_mc_bank_count());\n")
    f:write("  lua_setfield(L, LUA_REGISTRYINDEX, \"lalin.embedded_mc_bank.count\");\n")
    f:write("  return 0;\n}\n")
    f:close()
end

local function write_source_from_shards(path, shard_prefixes)
    for i, shard_prefix in ipairs(shard_prefixes or {}) do
        write_shard_source(
            shard_source_path(i),
            i,
            shard_prefix .. ".arrays.cfrag",
            shard_prefix .. ".entries.cfrag",
            tonumber(read_file(shard_prefix .. ".count"):match("%d+")) or 0
        )
    end
    write_index_source(path, #(shard_prefixes or {}))
end

if os.getenv("LALIN_MC_BANK_WORKER") == "1" then
    run_worker()
    return
end

local jobs = tonumber(os.getenv("LALIN_MC_BANK_JOBS")) or detected_jobs()
if jobs < 1 then jobs = 1 end
jobs = math.floor(jobs)
os.execute("rm -f " .. shell_quote(output_c_stem()) .. "_shard_" .. "*.c")

local shard_prefixes, count, payload_bytes, patch_count = build_sharded(jobs)

write_file(out_h, emit_header())
write_source_from_shards(out_c, shard_prefixes)
io.stderr:write(
    "embedded ", tostring(count), " Lalin MC bank entries, ",
    tostring(payload_bytes or 0), " payload bytes, ",
    tostring(patch_count or 0), " patches"
)
if jobs > 1 then io.stderr:write(" using ", tostring(jobs), " jobs") end
io.stderr:write("\n")
