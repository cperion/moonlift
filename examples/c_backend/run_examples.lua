package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local moon = require("moonlift")

local function exec_status(cmd)
    local r = os.execute(cmd)
    if r == true then return 0 end
    if type(r) == "number" then return r end
    return 1
end

local function exec_ok(cmd) return exec_status(cmd) == 0 end

local function q(s)
    return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

local function read(path)
    local f = assert(io.open(path, "rb"))
    local s = f:read("*a")
    f:close()
    return s
end

local function write(path, data)
    local f = assert(io.open(path, "wb"))
    f:write(data)
    f:close()
end

local function getenv_nonempty(name)
    local v = os.getenv(name)
    if v ~= nil and v ~= "" then return v end
    return nil
end

local function command_word(cmd)
    return tostring(cmd):match("^%s*(%S+)") or tostring(cmd)
end

local function have_command(cmd)
    return exec_ok("command -v " .. q(command_word(cmd)) .. " >/dev/null 2>&1")
end

local function choose_compiler()
    local forced = getenv_nonempty("MOONLIFT_C_CC")
    if forced then
        assert(have_command(forced), "MOONLIFT_C_CC compiler not found: " .. forced)
        return forced, "MOONLIFT_C_CC"
    end
    for _, cc in ipairs({ "tcc", "cc", "gcc", "clang" }) do
        if have_command(cc) then return cc, cc == "tcc" and "auto:tcc" or "auto:fallback" end
    end
    return nil, "no C compiler found (tried MOONLIFT_C_CC, tcc, cc, gcc, clang)"
end

local examples = {
    {
        file = "examples/c_backend/return_code.mlua",
        main = [[
int main(void) { return answer() == 42 ? 0 : 1; }
]],
    },
    {
        file = "examples/c_backend/arithmetic.mlua",
        main = [[
int main(void) { return arithmetic(10, 13) == 42 ? 0 : 1; }
]],
    },
    {
        file = "examples/c_backend/struct_pair.mlua",
        main = [[
int main(void) { struct _Pair p; p.x = 10; p.y = 32; return pair_sum(&p) == 42 ? 0 : 1; }
]],
    },
    {
        file = "examples/c_backend/extern_call.mlua",
        main = [[
int32_t host_add7(int32_t x) { return x + 7; }
int main(void) { return call_host(35) == 42 ? 0 : 1; }
]],
    },
    {
        file = "examples/c_backend/function_pointer.mlua",
        main = [[
int main(void) { return call_fp(inc, 41) == 42 ? 0 : 1; }
]],
    },
    {
        file = "examples/c_backend/pointer_view.mlua",
        main = [[
int main(void) {
    int32_t xs[6] = {1,2,3,4,5,6};
    moonlift_ml_view_MoonCore_ScalarI32 v = { xs, 3, 2 };
    if (pointer_store(xs) != 42) return 1;
    if (view_pick(v) != 3) return 2;
    return 0;
}
]],
    },
    {
        file = "examples/c_backend/tagged_union.mlua",
        main = [[
int main(void) { return tagged_pick(41) == 42 ? 0 : 1; }
]],
    },
}

local function try_libtcc(c_src)
    if getenv_nonempty("MOONLIFT_C_USE_LIBTCC") ~= "1" then return nil end
    local c_tcc = require("moonlift.c_tcc")
    local ok, why = c_tcc.available()
    if not ok then return nil, why and why.message or "libtcc unavailable" end
    local session, err = c_tcc.compile(c_src, { libraries = { "m" } })
    assert(session, err and err.message or "libtcc compile failed")
    local main = assert(session:symbol("main", "int (*)(void)"))
    local status = tonumber(main()) or 0
    session:free()
    assert(status == 0, "libtcc main() failed with status " .. tostring(status))
    return "libtcc in-memory"
end

local compiler, source = choose_compiler()
if not compiler then
    io.stderr:write(source, "\n")
    os.exit(77)
end

for i = 1, #examples do
    local ex = examples[i]
    local src = read(ex.file)
    local c_src = moon.emit_c(src, nil, ex.file) .. "\n" .. ex.main .. "\n"
    local mode, libtcc_skip = try_libtcc(c_src)
    if not mode then
        local base = os.tmpname()
        local c_path = base .. ".c"
        local exe_path = base .. ".out"
        write(c_path, c_src)
        local flags = compiler == "tcc" and "-std=c99 -Wall" or "-std=c99 -Wall -Wextra"
        local cmd = compiler .. " " .. flags .. " " .. q(c_path) .. " -lm -o " .. q(exe_path) .. " && " .. q(exe_path)
        assert(exec_ok(cmd), "example failed: " .. ex.file .. " via " .. compiler)
        os.remove(c_path)
        os.remove(exe_path)
        mode = compiler .. " subprocess (" .. source .. ")"
        if libtcc_skip then mode = mode .. "; libtcc skipped: " .. tostring(libtcc_skip) end
    end
    io.write("ok ", ex.file, " [", mode, "]\n")
end

io.write("moonlift C backend examples ok\n")
