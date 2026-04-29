package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local A2 = require("moonlift.asdl")
local Parse = require("moonlift.parse")
local Typecheck = require("moonlift.tree_typecheck")
local TreeToBack = require("moonlift.tree_to_back")
local Validate = require("moonlift.back_validate")
local Object = require("moonlift.back_object")

local function shell_quote(text)
    return "'" .. tostring(text):gsub("'", [['"'"']]) .. "'"
end

local function run(command)
    local pipe = assert(io.popen(command .. " 2>&1", "r"))
    local out = pipe:read("*a")
    local ok, why, code = pipe:close()
    if ok == nil or ok == false then
        error((out ~= "" and out or command) .. (why and (" (" .. tostring(why) .. " " .. tostring(code) .. ")") or ""), 2)
    end
    return out
end

local function have_cc()
    local ok = os.execute("cc --version >/dev/null 2>&1")
    return ok == true or ok == 0
end

local T = pvm.context()
A2.Define(T)
local P = Parse.Define(T)
local TC = Typecheck.Define(T)
local Lower = TreeToBack.Define(T)
local V = Validate.Define(T)
local O = Object.Define(T)

local src = [[
export func add_i32(a: i32, b: i32) -> i32
    return a + b
end
]]

local parsed = P.parse_module(src)
assert(#parsed.issues == 0, "parse issues: " .. #parsed.issues)
local checked = TC.check_module(parsed.module)
assert(#checked.issues == 0, "type issues: " .. #checked.issues)
local program = Lower.module(checked.module)
local report = V.validate(program)
assert(#report.issues == 0, "back validation issues: " .. #report.issues)

local object = O.compile(program, { module_name = "moonlift_object_smoke" })
local bytes = object:bytes()
assert(type(bytes) == "string" and #bytes > 0, "expected non-empty object bytes")

if not have_cc() then
    io.stderr:write("test_back_object_emit: cc not available; object byte emission only checked\n")
    print("moonlift back_object_emit ok")
    return
end

local base = os.tmpname():gsub("[^A-Za-z0-9_./-]", "_")
local obj_path = base .. ".o"
local c_path = base .. ".c"
local exe_path = base .. ".exe"
object:write(obj_path)
local c = assert(io.open(c_path, "wb"))
c:write [[
#include <stdint.h>
extern int32_t add_i32(int32_t a, int32_t b);
int main(void) {
    return add_i32(20, 22) == 42 ? 0 : 1;
}
]]
c:close()

run(string.format("cc %s %s -o %s", shell_quote(c_path), shell_quote(obj_path), shell_quote(exe_path)))
run(shell_quote(exe_path))

os.remove(obj_path)
os.remove(c_path)
os.remove(exe_path)
print("moonlift back_object_emit ok")
