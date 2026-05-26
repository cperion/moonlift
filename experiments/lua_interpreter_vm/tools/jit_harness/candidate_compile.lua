-- candidate_compile.lua
-- Compiles candidate kernels through Moonlift/Cranelift
-- Per LUA_STENCIL_HARNESS_DESIGN.md §4.11

local M = {}
local util = require("tools.jit_harness.util")

local function compile_kernel_gcc(kernel, config, output_dir, obj_path)
    local src = kernel.path or kernel.source
    if not kernel.path and kernel.source then
        local temp_src = output_dir .. "/" .. kernel.id .. ".c"
        local f = io.open(temp_src, "w")
        if f then f:write(kernel.source); f:close(); src = temp_src end
    end
    if not src then
        return { id = kernel.id, compiled = false, error = "no C kernel source" }
    end
    local cc = config.cc or os.getenv("CC") or "gcc"
    local flags = config.cflags or "-O3 -std=c11 -fno-stack-protector -fno-asynchronous-unwind-tables -fno-unwind-tables -fomit-frame-pointer -fno-ident -fPIC"
    local cmd = string.format("%s %s -c %s -o %s",
        util.shell_quote(cc), flags, util.shell_quote(util.abspath(src)), util.shell_quote(util.abspath(obj_path)))
    local ok, output, why, code = util.run_capture(cmd)
    local abs_obj = util.abspath(obj_path)
    if ok and util.path_exists(abs_obj) then
        local f = io.open(abs_obj, "rb")
        local bytes = f and f:read("*a") or ""
        if f then f:close() end
        return {
            id = kernel.id,
            kernel_id = kernel.id,
            compiled = true,
            backend = "gcc",
            object_path = abs_obj,
            source_path = util.abspath(src),
            symbol = "stencil_" .. kernel.id,
            size_bytes = #bytes,
            command = cmd,
            output = output,
        }
    end
    return { id = kernel.id, compiled = false, backend = "gcc", error = output or "gcc compilation failed", command = cmd, status = why, code = code }
end

-- Compile a single kernel through Moonlift or GCC
function M.compile_kernel(kernel, config)
    config = config or {}

    local output_dir = config.output_dir or "build/candidate_objects"
    util.mkdir_p(output_dir)

    local obj_path = output_dir .. "/" .. kernel.id .. ".o"
    local backend = config.backend or kernel.backend or (kernel.language == "c" and "gcc") or "moonlift"
    if backend == "gcc" or backend == "c" then
        return compile_kernel_gcc(kernel, config, output_dir, obj_path)
    end

    local kernel_src = kernel.path or kernel.source

    -- If kernel is just source string, write it to temp file first
    if not kernel.path and kernel.source then
        local temp_src = output_dir .. "/" .. kernel.id .. ".mlua"
        local f = io.open(temp_src, "w")
        if f then
            f:write(kernel.source)
            f:close()
            kernel_src = temp_src
        end
    end

    if not kernel_src then
        return {
            id = kernel.id,
            compiled = false,
            error = "no kernel source",
        }
    end

    local repo_root = util.abspath(config.repo_root or util.find_repo_root(".") or ".")
    local emitter = config.emit_object or (repo_root .. "/emit_object.lua")
    local abs_obj = util.abspath(obj_path)
    local abs_src = util.abspath(kernel_src)
    local module_name = (config.module_name or kernel.id):gsub("[^%w_]", "_")

    local cmd = string.format(
        "cd %s && luajit %s %s -o %s --module-name %s",
        util.shell_quote(repo_root),
        util.shell_quote(emitter),
        util.shell_quote(abs_src),
        util.shell_quote(abs_obj),
        util.shell_quote(module_name)
    )

    local ok, output, why, code = util.run_capture(cmd)
    local success = ok and util.path_exists(abs_obj)

    if success then
        local f = io.open(abs_obj, "rb")
        local bytes = f and f:read("*a") or ""
        if f then f:close() end
        return {
            id = kernel.id,
            kernel_id = kernel.id,
            compiled = true,
            object_path = abs_obj,
            source_path = abs_src,
            symbol = "stencil_" .. kernel.id,
            size_bytes = #bytes,
            command = cmd,
            output = output,
        }
    end

    return {
        id = kernel.id,
        compiled = false,
        error = output or "compilation failed",
        command = cmd,
        status = why,
        code = code,
    }
end

-- Compile a batch of kernels
function M.compile_kernel_batch(kernels, config)
    config = config or {}

    local results = {}
    local failed = 0
    local succeeded = 0

    for _, kernel in ipairs(kernels) do
        local result = M.compile_kernel(kernel, config)

        if result.compiled then
            succeeded = succeeded + 1
        else
            failed = failed + 1
        end

        table.insert(results, result)
    end

    return {
        results = results,
        total = #kernels,
        succeeded = succeeded,
        failed = failed,
    }
end

-- Dump compiled object to output directory
function M.dump_candidate_object(obj, output_dir)
    output_dir = output_dir or "build/candidate_objects"
    os.execute("mkdir -p " .. output_dir)

    -- Create metadata file
    local manifest = "{\n"
    manifest = manifest .. '  "id": "' .. obj.id .. '",\n'
    manifest = manifest .. '  "symbol": "' .. (obj.symbol or "unknown") .. '",\n'
    manifest = manifest .. '  "object_path": "' .. (obj.object_path or "") .. '",\n'
    manifest = manifest .. '  "timestamp": ' .. os.time() .. "\n"
    manifest = manifest .. "}\n"

    local path = output_dir .. "/" .. obj.id .. ".json"
    local f = io.open(path, "w")
    if not f then
        return nil, "cannot write to " .. path
    end

    f:write(manifest)
    f:close()

    return {
        output_dir = output_dir,
        manifest = path,
        object = obj,
    }
end

-- Report compilation results
function M.report_compilation(batch_result)
    print("\n=== Compilation Results ===")
    print(string.format("Compiled: %d", batch_result.succeeded or 0))
    print(string.format("Failed: %d", batch_result.failed or 0))

    if batch_result.failed and batch_result.failed > 0 then
        print("\n  Failed kernels:")
        local count = 0
        for _, result in ipairs(batch_result.results or {}) do
            if not result.compiled and count < 5 then
                print(string.format("    - %s: %s", result.id, result.error or "unknown"))
                count = count + 1
            end
        end
        if #batch_result.results > 5 then
            print(string.format("    ... and %d more", #batch_result.results - 5))
        end
    end
end

return M
