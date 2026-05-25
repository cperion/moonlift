-- corpus.lua
-- Loads and normalizes corpus sources
-- Per LUA_STENCIL_HARNESS_DESIGN.md §4.2

local M = {}

-- Generate a unique ID based on path
local function path_to_id(path)
    return string.gsub(path, "[^%w_]", "_")
end

-- Normalize a Lua file from the corpus
function M.normalize_lua_file(file_path)
    -- Check file exists
    local f = io.open(file_path, "r")
    if not f then
        return nil, "file not found: " .. file_path
    end

    local content = f:read("*a")
    f:close()

    -- Try to load as Lua to check syntax
    local chunk, err = load(content, file_path)
    if not chunk then
        return nil, "syntax error: " .. tostring(err)
    end

    -- Build normalized unit
    local unit = {
        id = path_to_id(file_path),
        path = file_path,
        size_bytes = #content,
        has_syntax_errors = false,
        has_runtime_errors = false,
        content_hash = M.simple_hash(content),
    }

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

    -- Look for testes directory
    local testes_dir = awfy_root .. "/build/awfy_puc_profile/puc_lua_profiled/testes"

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
            "goto.lua", "heavy.lua", "literals.lua", "locals.lua", "math.lua",
            "memerr.lua", "nextvar.lua", "pm.lua", "sort.lua", "strings.lua",
            "tpack.lua", "tracegc.lua", "utf8.lua", "vararg.lua", "verybig.lua",
        }

        for _, name in ipairs(awfy_files) do
            table.insert(files, {
                path = testes_dir .. "/" .. name,
                name = name,
                size = nil,
            })
        end
    end

    return files
end

-- Load and normalize an AWFY corpus
function M.load_awfy_corpus(awfy_root)
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
        local unit, err = M.normalize_lua_file(file_info.path)

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

    -- Simple JSON-like output
    local json_str = "{\n"
    json_str = json_str .. '  "timestamp": ' .. db.timestamp .. ",\n"
    json_str = json_str .. '  "kind": "' .. db.kind .. '",\n'
    json_str = json_str .. '  "root": "' .. db.root .. '",\n'
    json_str = json_str .. '  "file_count": ' .. #db.files .. ",\n"
    json_str = json_str .. '  "files": [\n'

    for i, file in ipairs(db.files) do
        json_str = json_str .. '    {\n'
        json_str = json_str .. '      "id": "' .. file.id .. '",\n'
        json_str = json_str .. '      "path": "' .. file.path .. '",\n'
        json_str = json_str .. '      "size_bytes": ' .. file.size_bytes .. '\n'
        json_str = json_str .. '    }' .. (i < #db.files and "," or "") .. '\n'
    end

    json_str = json_str .. '  ]\n'
    json_str = json_str .. '}\n'

    local f = io.open(output_path, "w")
    if not f then
        return false, "cannot write to " .. output_path
    end

    f:write(json_str)
    f:close()
    return true
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
