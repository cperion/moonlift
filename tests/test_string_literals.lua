package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local pvm = require("moonlift.pvm")
local A = require("moonlift.asdl")
local Pipeline = require("moonlift.frontend_pipeline")
local Jit = require("moonlift.back_jit")

local T = pvm.context(); A.Define(T)
local J = Jit.Define(T)
local Back = T.MoonBack

local src = [[
func first_byte(): i32
    return as(i32, "Hi"[0])
end

func newline_byte(): i32
    return as(i32, "a\n"[1])
end

func nul_terminated(): i32
    return as(i32, "A"[1])
end

func escaped_quote_and_hex(): i32
    return as(i32, "\"\x21"[1])
end

func octal_escape(): i32
    return as(i32, "\101"[0])
end

func reused_literal(): i32
    return as(i32, "Z"[0]) + as(i32, "Z"[0])
end
]]

local result = Pipeline.Define(T).parse_and_lower(src, { site = "test_string_literals" })
local program = result.program
local report = result.back_report
assert(#report.issues == 0, tostring(report.issues[1]))

local artifact = J.jit():compile(program)
local function fn(name)
    return ffi.cast("int32_t (*)()", artifact:getpointer(Back.BackFuncId(name)))
end

assert(fn("first_byte")() == string.byte("H"))
assert(fn("newline_byte")() == 10)
assert(fn("nul_terminated")() == 0)
assert(fn("escaped_quote_and_hex")() == string.byte("!"))
assert(fn("octal_escape")() == string.byte("A"))
assert(fn("reused_literal")() == string.byte("Z") * 2)
artifact:free()

print("moonlift string_literals ok")
