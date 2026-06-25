-- Virtual file system for C #include resolution
-- Provides a pluggable VFS for the preprocessor.
-- Default VFS reads from the real filesystem.
-- Tests inject a mock VFS for hermetic testing.

local M = {}

local function read_file(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local content = f:read("*a")
    f:close()
    return content
end

local function join_path(dir, path)
    if dir == nil or dir == "" then return path end
    if dir:sub(-1) == "/" then return dir .. path end
    return dir .. "/" .. path
end

-- Create a real-filesystem VFS.
-- opts.include_paths is searched for angle includes after quoted-relative lookup.
function M.real_fs(opts)
    opts = opts or {}
    local include_paths = opts.include_paths or opts.system_include_paths or {}
    return {
        read_file = function(path)
            return read_file(path)
        end,

        resolve_include = function(kind, path, current_dir)
            if kind ~= "angle" then
                local full_path = current_dir and join_path(current_dir, path) or path
                local content = read_file(full_path)
                if content then return full_path, content end
            end

            for _, dir in ipairs(include_paths) do
                local full_path = join_path(dir, path)
                local content = read_file(full_path)
                if content then
                    return full_path, content
                end
            end

            return nil, nil
        end,
    }
end

-- Create a mock VFS for testing
function M.mock(files)
    -- files: table mapping path -> file content (string)
    return {
        read_file = function(path)
            return files[path]
        end,

        resolve_include = function(kind, path, current_dir)
            if kind == "angle" then
                local content = files["<" .. path .. ">"]
                if content then return "<" .. path .. ">", content end
                return nil, nil
            else
                local full_path
                if current_dir then
                    full_path = current_dir .. "/" .. path
                else
                    full_path = path
                end
                if files[full_path] then
                    return full_path, files[full_path]
                end
                if files[path] then
                    return path, files[path]
                end
                return nil, nil
            end
        end,
    }
end

return M
