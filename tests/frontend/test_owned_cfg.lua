package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local A2 = require("moonlift.asdl")
local Parse = require("moonlift.parse")
local Typecheck = require("moonlift.tree_typecheck")

local T = pvm.context()
A2.Define(T)
local P = Parse.Define(T)
local TC = Typecheck.Define(T)
local Tr = T.MoonTree

local function check(src)
    local parsed = P.parse_module(src)
    assert(#parsed.issues == 0, "parse failed")
    return TC.check_module(parsed.module)
end

local function first_op(src)
    local checked = check(src)
    assert(#checked.issues > 0, "expected a type issue")
    for i = 1, #checked.issues do
        local issue = checked.issues[i]
        if pvm.classof(issue) == Tr.TypeIssueInvalidUnary then return issue.op end
    end
    error("expected invalid unary issue")
end

local header = [[
handle SessionRef : u32 invalid 0 end
extern close_session(s: owned SessionRef): void end
extern preserve_session(s: owned SessionRef): owned SessionRef end
extern observe_session(s: SessionRef): void end
]]

local ok_close = check(header .. [[
func ok_close(s: owned SessionRef): void
    close_session(s)
end
]])
assert(#ok_close.issues == 0)

local ok_return = check(header .. [[
func ok_return(s: owned SessionRef): owned SessionRef
    return preserve_session(s)
end
]])
assert(#ok_return.issues == 0)

assert(first_op(header .. [[
func leaks(s: owned SessionRef): void
    return
end
]]) == "owned dropped")

assert(first_op(header .. [[
func moved_twice(s: owned SessionRef): void
    close_session(s)
    close_session(s)
end
]]) == "owned use after move")

assert(first_op(header .. [[
func observed(s: owned SessionRef): void
    observe_session(s)
    close_session(s)
end
]]) == "owned passed to non-owned parameter")

assert(first_op(header .. [[
func cell(s: owned SessionRef): void
    var x: owned SessionRef = s
    close_session(x)
end
]]) == "owned var cell unsupported")

assert(first_op(header .. [[
struct BadBox
    s: owned SessionRef,
end
]]) == "owned stored in durable field")

assert(first_op(header .. [[
func raw_owner(p: owned ptr(u8)): void
    return
end
]]) == "owned invalid base")

assert(first_op(header .. [[
func branch_mismatch(s: owned SessionRef, b: bool): void
    if b then
        close_session(s)
    end
end
]]) == "owned branch mismatch")

local ok_loop = check(header .. [[
func loop_transfer(s: owned SessionRef, n: i32): void
    block loop(i: i32 = 0, cur: owned SessionRef = s)
        if i >= n then
            close_session(cur)
            return
        end
        jump loop(i = i + 1, cur = preserve_session(cur))
    end
end
]])
assert(#ok_loop.issues == 0)

local owned_emit = header .. [[
region keep_session(s: owned SessionRef;
    done(s: owned SessionRef))
entry start()
    jump done(s = s)
end
end
]]

local ok_emit = check(owned_emit .. [[
func emit_transfer(s: owned SessionRef): i32
    return region: i32
    entry start(cur: owned SessionRef = s)
        emit keep_session(cur; done = after)
    end
    block after(s: owned SessionRef)
        close_session(s)
        yield 0
    end
    end
end
]])
assert(#ok_emit.issues == 0)

assert(first_op(owned_emit .. [[
func emit_bad_target(s: owned SessionRef): i32
    return region: i32
    entry start(cur: owned SessionRef = s)
        emit keep_session(cur; done = after)
    end
    block after()
        yield 0
    end
    end
end
]]) == "owned emit target mismatch")

assert(first_op(owned_emit .. [[
func call_bad_payload(s: owned SessionRef): i32
    return region: i32
    entry start(cur: owned SessionRef = s)
        call keep_session(cur; done = after)
    end
    block after(s: owned SessionRef)
        close_session(s)
        yield 0
    end
    end
end
]]) == "owned region call payload")

print("moonlift owned cfg ok")
