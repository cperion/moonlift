package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local moon = require("moonlift")

local M = {}

local function exec_status(cmd)
    local r = os.execute(cmd)
    if r == true then return 0 end
    if type(r) == "number" then return r end
    return 1
end

local function exec_ok(cmd)
    return exec_status(cmd) == 0
end

local function shell_quote(s)
    s = tostring(s)
    return "'" .. s:gsub("'", "'\\''") .. "'"
end

local function write_file(path, data)
    local f = assert(io.open(path, "wb"))
    f:write(data)
    f:close()
end

local function read_file(path)
    local f = assert(io.open(path, "rb"))
    local data = f:read("*a")
    f:close()
    return data
end

local function getenv_nonempty(name)
    local v = os.getenv(name)
    if v ~= nil and v ~= "" then return v end
    return nil
end

local function file_exists(path)
    local f = io.open(path, "rb")
    if f == nil then return false end
    f:close()
    return true
end

local function repo_root()
    local info = debug.getinfo(1, "S")
    local source = info and info.source
    if type(source) ~= "string" then return nil end
    if source:sub(1, 1) == "@" then source = source:sub(2) end
    return source:match("^(.*)/tests/c_backend/test_c_gcc_harness%.lua$")
end

local function vendored_tcc()
    local root = repo_root()
    if root == nil then return nil end
    local path = root .. "/deps/tinycc/.local/bin/tcc"
    if file_exists(path) then return path end
    return nil
end

local function command_word(cmd)
    return tostring(cmd):match("^%s*(%S+)") or tostring(cmd)
end

local function have_command(cmd)
    return exec_ok("command -v " .. shell_quote(command_word(cmd)) .. " >/dev/null 2>&1")
end

local function is_tcc(cmd)
    local word = command_word(cmd):gsub("\\", "/")
    return word:match("(^|/)tcc$") ~= nil or word:match("(^|/)tinycc$") ~= nil
end

function M.choose_compiler(opts)
    opts = opts or {}
    local explicit = opts.cc or opts.compiler or getenv_nonempty("MOONLIFT_C_CC")
    if explicit then
        if have_command(explicit) then
            local source = (opts.cc or opts.compiler) and "opts" or "MOONLIFT_C_CC"
            return explicit, { source = source, preferred = true }
        end
        return nil, "requested C compiler not found: " .. tostring(explicit)
    end
    local candidates = {}
    local local_tcc = vendored_tcc()
    if local_tcc then candidates[#candidates + 1] = local_tcc end
    candidates[#candidates + 1] = "tcc"
    candidates[#candidates + 1] = "cc"
    candidates[#candidates + 1] = "gcc"
    candidates[#candidates + 1] = "clang"
    for i = 1, #candidates do
        if have_command(candidates[i]) then
            return candidates[i], { source = "auto", preferred = is_tcc(candidates[i]) }
        end
    end
    return nil, "no C compiler found (tried MOONLIFT_C_CC, tcc, cc, gcc, clang)"
end

function M.have_c_compiler(opts)
    return M.choose_compiler(opts) ~= nil
end

-- Backwards-compatible name used by existing tests.
function M.have_cc(opts)
    return M.have_c_compiler(opts)
end

function M.compiler_mode(opts)
    local cc, meta_or_err = M.choose_compiler(opts)
    if not cc then return nil, meta_or_err end
    return cc .. (is_tcc(cc) and " (tcc subprocess)" or " (subprocess)"), meta_or_err
end

function M.emit_artifact_source(src, opts)
    opts = opts or {}
    local emit_opts = opts.emit_opts or opts.c_opts or {}
    emit_opts.name = emit_opts.name or opts.name or "c_compiler_harness"
    emit_opts.c_path = emit_opts.c_path or opts.c_path
    return moon.emit_c_artifact(src, emit_opts).combined
end

function M.main_for_return(func_name, args, expected)
    args = args or {}
    local rendered = {}
    for i = 1, #args do rendered[i] = tostring(args[i]) end
    return string.format([[ 
#include <stdio.h>
int main(void) {
    long long got = (long long)%s(%s);
    long long expected = (long long)(%s);
    if (got != expected) {
        fprintf(stderr, "expected %%lld got %%lld\n", expected, got);
        return 100;
    }
    return 0;
}
]], func_name, table.concat(rendered, ", "), tostring(expected or 0))
end

local function default_cflags(cc, shared)
    if is_tcc(cc) then
        return shared and "-std=c99 -Wall -shared" or "-std=c99 -Wall"
    end
    return shared and "-std=c99 -Wall -Wextra -fPIC -shared" or "-std=c99 -Wall -Wextra"
end

local function default_ldflags(cc)
    -- tcc accepts -lm when libm is installed; cc/gcc/clang need it for helper tests.
    return "-lm"
end

function M.compile_c(c_src, opts)
    opts = opts or {}
    local cc, meta_or_err = M.choose_compiler(opts)
    assert(cc, meta_or_err)
    local base = opts.base or os.tmpname()
    local c_path = opts.c_path or (base .. ".c")
    local exe_path = opts.exe_path or (base .. ".out")
    write_file(c_path, c_src)
    local cmd = table.concat({
        cc,
        opts.cflags or default_cflags(cc, false),
        shell_quote(c_path),
        opts.ldflags or default_ldflags(cc),
        "-o",
        shell_quote(exe_path),
    }, " ")
    assert(exec_ok(cmd), "C compiler failed (" .. cc .. "): " .. cmd)
    return { c_path = c_path, exe_path = exe_path, cleanup = opts.cleanup ~= false, compiler = cc, compiler_meta = meta_or_err, mode = is_tcc(cc) and "tcc-subprocess" or "subprocess" }
end

function M.compile_shared(c_src, opts)
    opts = opts or {}
    local cc, meta_or_err = M.choose_compiler(opts)
    assert(cc, meta_or_err)
    local base = opts.base or os.tmpname()
    local c_path = opts.c_path or (base .. ".c")
    local so_path = opts.so_path or (base .. ".so")
    write_file(c_path, c_src)
    local cmd = table.concat({
        cc,
        opts.cflags or default_cflags(cc, true),
        shell_quote(c_path),
        opts.ldflags or default_ldflags(cc),
        "-o",
        shell_quote(so_path),
    }, " ")
    assert(exec_ok(cmd), "C compiler shared failed (" .. cc .. "): " .. cmd)
    return { c_path = c_path, so_path = so_path, cleanup = opts.cleanup ~= false, compiler = cc, compiler_meta = meta_or_err, mode = is_tcc(cc) and "tcc-subprocess" or "subprocess" }
end

function M.run_executable(exe_path, opts)
    opts = opts or {}
    local out_path = opts.out_path or (os.tmpname() .. ".out.txt")
    local cmd = shell_quote(exe_path) .. " >" .. shell_quote(out_path) .. " 2>&1"
    local status = exec_status(cmd)
    local output = read_file(out_path)
    if opts.cleanup ~= false then os.remove(out_path) end
    if opts.expected_status ~= nil then
        assert(status == opts.expected_status, "expected status " .. tostring(opts.expected_status) .. " got " .. tostring(status) .. " output:\n" .. output)
    else
        assert(status == 0, "executable failed status " .. tostring(status) .. " output:\n" .. output)
    end
    if opts.expected_output ~= nil then
        assert(output == opts.expected_output, "expected output " .. string.format("%q", opts.expected_output) .. " got " .. string.format("%q", output))
    end
    return { status = status, output = output, mode = "executable" }
end

local function use_libtcc(opts)
    opts = opts or {}
    if opts.use_libtcc ~= nil then return opts.use_libtcc end
    return getenv_nonempty("MOONLIFT_C_USE_LIBTCC") == "1"
end

function M.compile_run_libtcc(c_src, opts)
    opts = opts or {}
    local c_tcc = require("moonlift.c_tcc")
    local ok, why = c_tcc.available(opts.libtcc_opts)
    if not ok then return nil, why end
    if opts.expected_output ~= nil then
        return nil, { skip = true, code = "libtcc_output_capture_unsupported", message = "libtcc in-memory mode cannot capture process stdout; using subprocess compiler" }
    end
    local session, err = c_tcc.compile(c_src, opts.libtcc_opts or { libraries = { "m" } })
    if not session then return nil, err or { skip = true, code = "libtcc_compile_failed", message = "libtcc compile failed" } end
    local main, sym_err = session:symbol(opts.main_symbol or "main", opts.main_ctype or "int (*)(void)")
    if not main then
        session:free()
        return nil, sym_err or { skip = true, code = "libtcc_symbol_failed", message = "libtcc main symbol not found" }
    end
    local ok_call, status_or_err = pcall(function() return tonumber(main()) or 0 end)
    session:free()
    if not ok_call then return nil, { skip = true, code = "libtcc_call_failed", message = tostring(status_or_err) } end
    local status = status_or_err
    if opts.expected_status ~= nil then
        assert(status == opts.expected_status, "expected status " .. tostring(opts.expected_status) .. " got " .. tostring(status) .. " from libtcc main()")
    else
        assert(status == 0, "libtcc main() failed status " .. tostring(status))
    end
    return { status = status, output = "", mode = "libtcc", compiler = "libtcc" }
end

function M.compile_run(src, opts)
    opts = opts or {}
    local c_src = M.emit_artifact_source(src, opts)
    if opts.main then c_src = c_src .. "\n" .. opts.main .. "\n" end

    local libtcc_skip
    if use_libtcc(opts) then
        local result, err = M.compile_run_libtcc(c_src, opts)
        if result then return result, c_src end
        libtcc_skip = err
    end

    local artifact = M.compile_c(c_src, opts)
    local result = M.run_executable(artifact.exe_path, opts)
    result.compiler = artifact.compiler
    result.compiler_meta = artifact.compiler_meta
    result.mode = artifact.mode
    result.libtcc_skip = libtcc_skip
    if artifact.cleanup then os.remove(artifact.c_path); os.remove(artifact.exe_path) end
    return result, c_src
end

function M.assert_return(src, func_name, args, expected, opts)
    opts = opts or {}
    opts.main = opts.main or M.main_for_return(func_name, args, expected)
    opts.expected_status = opts.expected_status or 0
    return M.compile_run(src, opts)
end

if ... == nil then
    local cc, err = M.choose_compiler()
    if not cc then
        io.write(err .. "; skipping C compiler/TCC harness self-test\n")
        os.exit(0)
    end
    local src = [[
func add_i32(a: i32, b: i32): i32
    return a + b
end

func sum_to(n: i32): i32
    return block loop(i: i32 = 0, acc: i32 = 0): i32
        if i >= n then yield acc else jump loop(i = i + 1, acc = acc + i) end
    end
end
]]
    local r1 = M.assert_return(src, "add_i32", { "20", "22" }, 42, { name = "c_compiler_harness_add" })
    local r2 = M.assert_return(src, "sum_to", { "10" }, 45, { name = "c_compiler_harness_sum" })
    local c_src = M.emit_artifact_source(src, { name = "c_compiler_harness_shared" })
    local shared = M.compile_shared(c_src)
    if shared.cleanup then os.remove(shared.c_path); os.remove(shared.so_path) end

    local libtcc_note = ""
    local c_tcc = require("moonlift.c_tcc")
    local libtcc_ok, libtcc_err = c_tcc.available()
    if getenv_nonempty("MOONLIFT_C_USE_LIBTCC") == "1" then
        local skip = r1.libtcc_skip or r2.libtcc_skip
        if skip then
            libtcc_note = "; libtcc loadable but subprocess fallback used: " .. tostring(skip.message or skip.code)
        else
            libtcc_note = libtcc_ok and "; libtcc in-memory exercised" or ("; libtcc unavailable, subprocess fallback used: " .. tostring(libtcc_err and libtcc_err.message))
        end
    else
        libtcc_note = libtcc_ok and "; libtcc available (set MOONLIFT_C_USE_LIBTCC=1 to exercise)" or "; libtcc unavailable (optional)"
    end

    io.write("moonlift C compiler/TCC harness ok (", tostring(r1.mode or r2.mode or shared.mode), ", compiler=", tostring(r1.compiler or cc), ")", libtcc_note, "\n")
end

return M
