package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local c_tcc = require("lalin.c_tcc")
local ffi = require("ffi")

local ok, why = c_tcc.available()
assert(type(ok) == "boolean", "available returns boolean")

if not ok then
    assert(type(why) == "table" and why.skip == true, "absent libtcc should report a skip diagnostic")
    local session, err = c_tcc.compile("int answer(void) { return 42; }\n")
    assert(session == nil, "compile should not return a session when libtcc is absent")
    assert(type(err) == "table" and err.skip == true and err.message:match("libtcc"), "compile absence diagnostic should be clear")
    io.write("libtcc not available; lalin.c_tcc optional binding skip ok\n")
    os.exit(0)
end

local session, err = c_tcc.compile([[ 
int answer(void) { return 42; }
int add(int a, int b) { return a + b; }
]], { libraries = { "m" } })
assert(session, err and err.message or "libtcc compile failed")

local answer = assert(session:symbol("answer", "int (*)(void)"))
assert(answer() == 42, "libtcc answer symbol should execute")

local add = assert(c_tcc.symbol("add", "int (*)(int, int)"))
assert(add(20, 22) == 42, "module-level symbol should use last session")

session:free()
local missing, sym_err = session:symbol("answer", "int (*)(void)")
assert(missing == nil and sym_err.code == "session_freed", "freed session should reject symbols")

local triple_host = ffi.cast("int (*)(int)", function(x) return x * 3 end)
local host_session, host_err = c_tcc.compile([[
int triple_host(int x);
int via_host(int x) { return triple_host(x) + 1; }
]], {
    host_symbols = {
        triple_host = ffi.cast("void *", ffi.cast("uintptr_t", triple_host)),
    },
})
assert(host_session, host_err and host_err.message or "libtcc host-symbol compile failed")
local via_host = assert(host_session:symbol("via_host", "int (*)(int)"))
assert(via_host(7) == 22, "libtcc host symbol should be visible during relocation")
host_session:free()
triple_host:free()

io.write("lalin.c_tcc libtcc compile-run ok\n")
