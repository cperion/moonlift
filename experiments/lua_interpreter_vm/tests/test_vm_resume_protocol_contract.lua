-- ResumeState protocol routing checks.

package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local moon = require("moonlift")
local vm = require("experiments.lua_interpreter_vm.src.init")
local const = vm.const

local route = moon.func { decode = vm.regions_resume.decode_resume_kind } [[
route_resume(kind: u16): i32
    return region: i32
    entry start()
        let nilv: Value = { tag = 0, aux = 0, bits = 0 }
        let state: ResumeState = { kind = kind, a = 0, b = 0, c = 0, pc = 0, base = 0,
                                   result_base = 0, call_top = 0, wanted = 0,
                                   value = nilv, errfunc_slot = 0 }
        emit @{decode}(state;
            normal = normal, tailcall = tailcall, pcall = pcall, xpcall = xpcall,
            gettable_mm = gettable_mm, settable_mm = settable_mm,
            binop_mm = binop_mm, unop_mm = unop_mm, len_mm = len_mm,
            concat_mm = concat_mm, eq_mm = eq_mm, lt_mm = lt_mm, le_mm = le_mm,
            call_mm = call_mm, tforloop_call = tforloop_call, native_cont = native_cont,
            tbc_close = tbc_close, finalizer_call = finalizer_call,
            coroutine_resume = coroutine_resume, coroutine_yield = coroutine_yield,
            unknown = unknown)
    end
    block normal() yield 0 end
    block tailcall() yield 1 end
    block pcall() yield 2 end
    block xpcall() yield 3 end
    block gettable_mm() yield 4 end
    block settable_mm() yield 5 end
    block binop_mm() yield 6 end
    block unop_mm() yield 7 end
    block len_mm() yield 8 end
    block concat_mm() yield 9 end
    block eq_mm() yield 10 end
    block lt_mm() yield 11 end
    block le_mm() yield 12 end
    block call_mm() yield 13 end
    block tforloop_call() yield 14 end
    block native_cont() yield 15 end
    block tbc_close() yield 16 end
    block finalizer_call() yield 17 end
    block coroutine_resume() yield 18 end
    block coroutine_yield() yield 19 end
    block unknown(kind: u16) yield 1000 + as(i32, kind) end
    end
end
]]:compile()

local pass, fail = 0, 0
local function check(name, cond)
    if cond then pass = pass + 1; print("  PASS " .. name)
    else fail = fail + 1; print("  FAIL " .. name) end
end

print("=== VM resume protocol contract ===\n")
for i = 0, const.Resume.N - 1 do
    check("resume kind " .. i, route(i) == i)
end
check("unknown resume kind", route(const.Resume.N) == 1000 + const.Resume.N)
route:free()
print(string.format("\n=== %d/%d passed ===", pass, pass + fail))
assert(fail == 0)
return true
