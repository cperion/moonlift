-- Virtual file system for C #include resolution
-- Provides a pluggable VFS for the preprocessor.
-- Default VFS reads from the real filesystem.
-- Tests inject a mock VFS for hermetic testing.

local M = {}

-- Create a real-filesystem VFS
function M.real_fs()
    return {
        read_file = function(path)
            local f, err = io.open(path, "r")
            if not f then
                -- Remove noisy ENOENT for paths we can't read
                return nil
            end
            local content = f:read("*a")
            f:close()
            return content
        end,

        resolve_include = function(kind, path, current_dir)
            if kind == "angle" then
                -- System include: search system paths
                -- TODO: configurable system include paths
                return nil, nil
            else
                -- Quoted include: search relative to current file first
                local full_path
                if current_dir then
                    full_path = current_dir .. "/" .. path
                else
                    full_path = path
                end
                local content = io.open(full_path, "r")
                if content then
                    content:close()
                    return full_path, io.open(full_path, "r"):read("*a")
                end
                return nil, nil
            end
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
