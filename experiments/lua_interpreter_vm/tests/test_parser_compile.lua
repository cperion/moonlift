package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
pcall(ffi.cdef, [[
void* malloc(size_t size);
void free(void* ptr);
]])
local moon = require("moonlift")
local vm = require("experiments.lua_interpreter_vm.src.init")
local const = vm.const

require("experiments.lua_interpreter_vm.tools.vm_ffi_schema").apply(ffi)
assert(ffi.sizeof("CompileUnit") > 512, "CompileUnit FFI schema is stale")
assert(ffi.sizeof("ParseNode") > 0, "ParseNode missing from FFI schema")
assert(ffi.sizeof("HirFunction") > 0, "HirFunction missing from FFI schema")
assert(ffi.sizeof("LowerFrame") > 0, "LowerFrame missing from FFI schema")

local compile_region = vm.regions_compiler.compile_lua_source_into
local wrapper = moon.func { compile_lua_source_into = compile_region } [[
compile_text(cu: ptr(CompileUnit), b: ptr(FuncBuilder), p: ptr(Proto), bytes: ptr(u8), n: index, code: ptr(Instr), locals: ptr(CompileLocal), workspace: ptr(u8), workspace_cap: index): i32
    return region: i32
    entry start()
        emit @{compile_lua_source_into}(cu, b, p, bytes, n, code, as(index, 32), locals, as(index, 16), workspace, workspace_cap;
            ok = ok,
            syntax_error = syntax_bad,
            semantic_error = semantic_bad,
            limit_error = limit_bad,
            oom = oom_bad)
    end
    block ok(proto: ptr(Proto)) yield as(i32, proto.code_len) end
    block syntax_bad(err: CompileError) yield 0 - err.code end
    block semantic_bad(err: CompileError) yield -100 - err.code end
    block limit_bad(err: CompileError) yield -200 - err.code end
    block oom_bad() yield -999 end
    end
end
]]

local compiled = assert(wrapper:compile())

local realloc_cb = ffi.cast("uint64_t (*)(uint8_t*, uint64_t, uint64_t, uint64_t)",
    function(old, old_size, new_size, align)
        if new_size == 0 then
            if old ~= nil then ffi.C.free(old) end
            return ffi.cast("uint64_t", 0)
        end
        local p = ffi.C.malloc(tonumber(new_size))
        if p == nil then return ffi.cast("uint64_t", 0) end
        return ffi.cast("uint64_t", ffi.cast("uintptr_t", p))
    end)

local runner = moon.func {
    validate_proto = vm.validate.validate_proto,
    vm_resume = vm.vm_loop.vm_resume,
} [[
run_proto(L: ptr(LuaThread), p: ptr(Proto)): i32
    return region: i32
    entry start()
        emit @{validate_proto}(L, p; ok = valid, invalid = invalid, oom = oom_bad)
    end
    block valid()
        emit @{vm_resume}(L, 0;
            ok = done,
            yielded = yielded,
            runtime_error = runtime_bad,
            oom = oom_bad)
    end
    block done(nres: i32) return nres end
    block yielded(nres: i32) return -100 - nres end
    block runtime_bad(code: i32) return -200 - code end
    block invalid(code: i32) return -300 - code end
    block oom_bad() return -999 end
    end
end
]]:compile()

local function compile_status(src, workspace_cap)
    local cu = ffi.new("CompileUnit[1]")
    local b = ffi.new("FuncBuilder[1]")
    local p = ffi.new("Proto[1]")
    local code = ffi.new("Instr[128]")
    local locals = ffi.new("CompileLocal[32]")
    local cap = workspace_cap or (1024 * 1024)
    local workspace = ffi.new("uint8_t[?]", cap)
    local bytes = ffi.new("uint8_t[?]", #src)
    ffi.copy(bytes, src, #src)
    local n = compiled(cu, b, p, bytes, #src, code, locals, workspace, cap)
    return n, cu, p, code, workspace, bytes
end

local function make_thread(proto)
    local closure = ffi.new("LClosure[1]")
    closure[0].proto = proto
    local stack = ffi.new("Value[128]")
    for i = 0, 127 do
        stack[i].tag = const.Tag.NIL
        stack[i].aux = 0
        stack[i].bits = 0
    end
    stack[0].tag = const.Tag.LCLOSURE
    stack[0].bits = ffi.cast("uint64_t", closure)
    local frames = ffi.new("Frame[8]")
    frames[0].closure = stack[0]
    frames[0].base = 1
    frames[0].top = 1
    frames[0].pc = 0
    frames[0].wanted = 1
    frames[0].resume.kind = const.Resume.NORMAL
    frames[0].result_base = 1
    frames[0].call_top = 1
    frames[0].yieldable = 1
    local global = ffi.new("GlobalState[1]")
    local alloc = ffi.new("Allocator[1]")
    alloc[0].realloc = ffi.cast("uint8_t*", realloc_cb)
    global[0].allocator = alloc
    global[0].threshold = 1024 * 1024
    global[0].totalbytes = 0
    global[0].currentwhite = 0
    local env_nodes = ffi.new("Node[16]")
    for i = 0, 15 do
        env_nodes[i].key.tag = const.Tag.NIL
        env_nodes[i].value.tag = const.Tag.NIL
        env_nodes[i].next = nil
    end
    local env = ffi.new("Table[1]")
    env[0].array_len = 0
    env[0].array_cap = 0
    env[0].array = nil
    env[0].node_mask = 15
    env[0].node_count = 0
    env[0].nodes = env_nodes
    env[0].metatable = nil
    closure[0].env = env
    local env_value = ffi.new("Value[1]")
    env_value[0].tag = const.Tag.TABLE
    env_value[0].bits = ffi.cast("uint64_t", env)
    local upv = ffi.new("UpVal[1]")
    upv[0].v = env_value
    upv[0].closed = env_value[0]
    local upv_ptrs = ffi.new("UpVal*[1]")
    upv_ptrs[0] = upv
    if proto[0].upvals_len > 0 then
        closure[0].upvals = upv_ptrs
        closure[0].nupvals = 1
    end
    local L = ffi.new("LuaThread[1]")
    L[0].status = const.Status.OK
    L[0].stack = stack
    L[0].stack_size = 128
    L[0].top = 1
    L[0].frames = frames
    L[0].frame_count = 1
    L[0].frame_cap = 8
    L[0].global = global
    L[0].yieldable = 1
    global[0].mainthread = L
    return L, stack, { closure = closure, frames = frames, global = global, alloc = alloc, env = env, env_nodes = env_nodes, env_value = env_value, upv = upv, upv_ptrs = upv_ptrs }
end

local function run_int(src)
    local n, cu, p, code, workspace, bytes = compile_status(src)
    assert(n > 0, src .. " failed to compile: " .. tostring(n))
    local L, stack, keep = make_thread(p)
    local nres = runner(L, p)
    assert(nres == 1, src .. " nres: " .. tostring(nres))
    assert(stack[1].tag == const.Tag.INTEGER, src .. " result tag: " .. tostring(stack[1].tag))
    return tonumber(ffi.cast("int64_t", stack[1].bits)), n, cu, p, code, workspace, bytes, keep
end

local function run_string(src)
    local n, cu, p, code, workspace, bytes = compile_status(src)
    assert(n > 0, src .. " failed to compile: " .. tostring(n))
    local L, stack, keep = make_thread(p)
    local nres = runner(L, p)
    assert(nres == 1, src .. " nres: " .. tostring(nres))
    assert(stack[1].tag == const.Tag.STR, src .. " result tag: " .. tostring(stack[1].tag))
    local s = ffi.cast("String*", stack[1].bits)
    return ffi.string(s.bytes, tonumber(s.len)), n, cu, p, code, workspace, bytes, keep
end

local function run_two_ints(src)
    local n, cu, p, code, workspace, bytes = compile_status(src)
    assert(n > 0, src .. " failed to compile: " .. tostring(n))
    local L, stack, keep = make_thread(p)
    local nres = runner(L, p)
    assert(nres == 2, src .. " nres: " .. tostring(nres))
    assert(stack[1].tag == const.Tag.INTEGER, src .. " result1 tag: " .. tostring(stack[1].tag))
    assert(stack[2].tag == const.Tag.INTEGER, src .. " result2 tag: " .. tostring(stack[2].tag))
    return tonumber(ffi.cast("int64_t", stack[1].bits)), tonumber(ffi.cast("int64_t", stack[2].bits)), n, cu, p, code, workspace, bytes, keep
end

local n, cu, p = compile_status("return 1")
assert(n == 2, "return integer should lower to LOADI + RETURN1")
assert(cu[0].root_parse_function ~= 0, "parse phase did not produce root parse function")
assert(cu[0].root_hir_function ~= 0, "semantic phase did not produce root HIR function")
assert(cu[0].parse_nodes.len > 0, "parse phase produced no nodes")
assert(cu[0].hir_functions.len > 0, "semantic phase produced no HIR functions")
assert(cu[0].hir_stmts.len == 1, "semantic phase did not build return HIR")
assert(cu[0].hir_exprs.len == 1, "semantic phase did not build integer HIR")
assert(p[0].code_len == n, "proto was not closed by lowering")

local n2, cu2, p2 = compile_status("local a = 2 return a + 3")
assert(n2 > 2, "local + binary return should lower real bytecode")
assert(cu2[0].hir_stmts.len == 2, "expected local and return HIR statements")
assert(cu2[0].hir_exprs.len >= 4, "expected literal/local/binary HIR expressions")
assert(p2[0].code_len == n2, "local proto code length mismatch")

local n3, cu3 = compile_status("local a a = 5 return -a")
assert(n3 > 2, "assignment + unary return should lower real bytecode")
assert(cu3[0].hir_stmts.len == 3, "expected local, assignment, return HIR statements")

local n4, cu4 = compile_status("return true")
assert(n4 == 2 and cu4[0].hir_exprs.len == 1, "boolean return should compile")

local n5, cu5 = compile_status("return 1 < 2")
assert(n5 > 2 and cu5[0].hir_exprs.len >= 3, "comparison expression should build/lower HIR")

local nbit = compile_status("return 6 | 1")
assert(nbit > 0, "bitwise operators beyond &: should compile")

local nstr, custr = compile_status("return 'x'")
assert(nstr > 0 and custr[0].hir_exprs.len == 1, "strings should parse/resolve/lower through durable constants")

local n6, cu6 = compile_status("if true then return 1 else return 2 end")
assert(n6 > 0 and cu6[0].hir_stmts.len >= 4, "if/else should build control HIR")

local n7, cu7 = compile_status("local x = 0 while x < 3 do x = x + 1 end return x")
assert(n7 > 0 and cu7[0].hir_stmts.len >= 5, "while loop should build/lower HIR")

local n8, cu8 = compile_status("local x = 0 repeat x = x + 1 until x >= 3 return x")
assert(n8 > 0 and cu8[0].hir_stmts.len >= 4, "repeat/until should build/lower HIR")

local n9, cu9 = compile_status("local x = 0 for i = 1, 5 do x = x + i end return x")
assert(n9 > 0 and cu9[0].hir_stmts.len >= 5, "numeric for should build/lower HIR")

local ncall, cucall = compile_status("f(1)")
assert(ncall > 0 and cucall[0].hir_exprs.len >= 3, "simple global call statement should parse/HIR/lower")

local ncall2, cucall2 = compile_status("f(1, 2, 'x')")
assert(ncall2 > 0 and cucall2[0].hir_exprs.len >= 5, "multi-argument call should parse/HIR/lower")

local nmethod, cumethod = compile_status("obj:m(7)")
assert(nmethod > 0 and cumethod[0].hir_exprs.len >= 3, "method call syntax should parse/HIR/lower")

local nret2, curet2 = compile_status("return 1, 2")
assert(nret2 > 0 and curet2[0].hir_stmts.data[1].b == 2, "multi-return expression list should build HIR")

assert(run_int("if true then return 1 else return 2 end") == 1, "if true branch should execute")
assert(run_int("if false then return 1 else return 2 end") == 2, "if false branch should execute")
assert(run_int("local x = 0 while x < 3 do x = x + 1 end return x") == 3, "while loop should execute")
assert(run_int("local x = 0 repeat x = x + 1 until x >= 3 return x") == 3, "repeat loop should execute")
assert(run_int("local x = 0 for i = 1, 5 do x = x + i end return x") == 15, "numeric for should execute")
assert(run_string("return 'x'") == "x", "string constants should execute")
assert(run_int("g = 41 g = g + 1 return g") == 42, "globals through _ENV should execute")
assert(run_int("local t = {1, 2, 3} return t[2]") == 2, "array table constructor/index should execute")
assert(run_int("local t = {} t.answer = 42 return t.answer") == 42, "field set/get should execute")
assert(run_int("local t = { answer = 40, [2] = 2 } return t.answer + t[2]") == 42, "keyed table constructor entries should execute")
local a, b = run_two_ints("return 1, 2")
assert(a == 1 and b == 2, "multi-return should execute")

local small = compile_status("return 1", 4096)
assert(small == -999, "small workspace must fail through oom boundary")

print("PASS parser architecture smoke")

-- Compiled closures are process-lifetime test fixtures. Avoid explicit free;
-- process exit reclaims them.
return true
