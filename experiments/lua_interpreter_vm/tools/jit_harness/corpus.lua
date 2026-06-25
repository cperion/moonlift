-- corpus.lua
-- Loads and normalizes corpus sources
-- Per LUA_STENCIL_HARNESS_DESIGN.md §4.2

local M = {}
local util = require("tools.jit_harness.util")

-- Generate a unique ID based on path
local function path_to_id(path)
    return string.gsub(path, "[^%w_]", "_")
end

-- Normalize a Lua file from the corpus
function M.normalize_lua_file(file_path, config)
    config = config or {}
    local content, err = util.read_file(file_path)
    if not content then
        return nil, "file not found: " .. file_path .. (err and (": " .. tostring(err)) or "")
    end

    -- Do not use LuaJIT syntax as the default corpus gate: the target corpus is
    -- PUC Lua 5.5 and must be accepted/rejected by the Lalin Lua VM compiler.
    if config.syntax_check == "luajit" then
        local chunk, syntax_err = load(content, file_path)
        if not chunk then
            return nil, "syntax error: " .. tostring(syntax_err)
        end
    end

    local unit = {
        id = path_to_id(file_path),
        path = file_path,
        name = util.basename(file_path),
        size_bytes = #content,
        source_hash = util.stable_hash(content),
        content_hash = M.simple_hash(content),
        lua_version = config.lua_version or "5.5",
        dialect = config.dialect or "puc",
        entry_kind = "file",
    }

    if config.store_source_copy then unit.source = content end
    return unit
end

-- Simple hash function for content
function M.simple_hash(content)
    -- Basic hash: just use length + first few chars
    local len = #content
    local sig = string.sub(content, 1, 20)
    return string.format("%d_%s", len, string.gsub(sig, "[^%w]", "_"))
end

-- Discover all Lua files in AWFY directory
function M.discover_awfy(awfy_root)
    local files = {}

    -- Look for a PUC Lua `testes` directory. Accept either the profiled AWFY
    -- copy or the canonical checkout at .vendor/Lua/testes.
    local testes_dir = awfy_root .. "/build/awfy_puc_profile/puc_lua_profiled/testes"
    if not util.path_exists(testes_dir) then
        if util.path_exists(awfy_root .. "/testes") then
            testes_dir = awfy_root .. "/testes"
        elseif util.path_exists(awfy_root .. "/.vendor/Lua/testes") then
            testes_dir = awfy_root .. "/.vendor/Lua/testes"
        end
    end

    -- Try lfs first if available
    local lfs_ok, lfs = pcall(require, "lfs")

    if lfs_ok and lfs and lfs.dir then
        for entry in lfs.dir(testes_dir) do
            if entry ~= "." and entry ~= ".." and string.match(entry, "%.lua$") then
                table.insert(files, {
                    path = testes_dir .. "/" .. entry,
                    name = entry,
                    size = nil,
                })
            end
        end
    else
        -- Fallback: read from a static list (AWFY files we know about)
        local awfy_files = {
            "all.lua", "api.lua", "attrib.lua", "big.lua", "bitwise.lua",
            "bwcoercion.lua", "calls.lua", "closure.lua", "code.lua",
            "constructs.lua", "coroutine.lua", "cstack.lua", "db.lua",
            "errors.lua", "events.lua", "files.lua", "gc.lua", "gengc.lua",
            "goto.lua", "heavy.lua", "literals.lua", "locals.lua", "main.lua", "math.lua",
            "memerr.lua", "nextvar.lua", "pm.lua", "sort.lua", "strings.lua",
            "tpack.lua", "tracegc.lua", "utf8.lua", "vararg.lua", "verybig.lua",
        }

        for _, name in ipairs(awfy_files) do
            local path = testes_dir .. "/" .. name
            if util.path_exists(path) then
                table.insert(files, {
                    path = path,
                    name = name,
                    size = nil,
                })
            end
        end
    end

    return files
end

-- Load and normalize an AWFY corpus
function M.load_awfy_corpus(awfy_root, config)
    config = config or {}
    print("\n=== Loading AWFY Corpus ===")

    local files = M.discover_awfy(awfy_root)
    print(string.format("Found %d AWFY test files", #files))

    local corpus = {
        kind = "AWFY",
        root = awfy_root,
        files = {},
        normalized_count = 0,
        error_count = 0,
    }

    for _, file_info in ipairs(files) do
        local unit, err = M.normalize_lua_file(file_info.path, config)

        if unit then
            table.insert(corpus.files, unit)
            corpus.normalized_count = corpus.normalized_count + 1
        else
            corpus.error_count = corpus.error_count + 1
            print(string.format("  ✗ %s: %s", file_info.name, err))
        end
    end

    print(string.format("  Normalized: %d", corpus.normalized_count))
    print(string.format("  Errors: %d", corpus.error_count))

    return corpus
end

-- Build corpus profile from normalized units
function M.build_corpus_profile(corpus)
    local profile = {
        kind = corpus.kind,
        total_files = #corpus.files,
        total_bytes = 0,
        files = {},
    }

    for _, unit in ipairs(corpus.files) do
        profile.total_bytes = profile.total_bytes + unit.size_bytes
        table.insert(profile.files, {
            id = unit.id,
            path = unit.path,
            size_bytes = unit.size_bytes,
        })
    end

    return profile
end

-- Write corpus database to file
function M.write_corpus_db(corpus, output_path)
    local db = {
        timestamp = os.time(),
        kind = corpus.kind,
        root = corpus.root,
        files = corpus.files,
    }

    return util.write_json(output_path, db)
end

-- Report corpus statistics
function M.report_corpus(corpus)
    print("\n=== Corpus Report ===")
    print(string.format("Kind: %s", corpus.kind))
    print(string.format("Root: %s", corpus.root))
    print(string.format("Files normalized: %d", corpus.normalized_count))
    print(string.format("Normalization errors: %d", corpus.error_count))

    local total_bytes = 0
    for _, file in ipairs(corpus.files) do
        total_bytes = total_bytes + file.size_bytes
    end
    print(string.format("Total bytecode: %d bytes", total_bytes))
end

return M
