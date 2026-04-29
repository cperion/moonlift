package.path = "./?.lua;./?/init.lua;./moonlift/lua/?.lua;./moonlift/lua/?/init.lua;./moonlift/lua/?.lua;./moonlift/lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local Host = require("moonlift.host_quote")

local translated = Host.translate [[
local add1 = func add1(x: i32) -> i32
    return x + 1
end
return add1
]]
assert(translated:find("__moonlift_host%.func_from_source"))
local not_quote = Host.translate [[
local module = 1
return module
]]
assert(not_quote:find("local module = 1", 1, true))
assert(not not_quote:find("module_from_source", 1, true))

local loaded_chunk = Host.load [[
local add1 = func add1(x: i32) -> i32
    return x + 1
end
return add1
]]
assert(type(loaded_chunk) == "function")
assert(tostring(loaded_chunk()) == "MoonliftFuncQuote(add1)")

local add1 = Host.eval [[
local add1 = func add1(x: i32) -> i32
    return x + 1
end
return add1
]]
assert(tostring(add1) == "MoonliftFuncQuote(add1)")
local c_add1 = add1:compile()
assert(c_add1(41) == 42)
c_add1:free()

local find_byte = Host.eval [[
local find_byte = func find_byte(p: ptr(u8), n: i32, target: i32) -> i32
    return region -> i32
    entry scan(i: i32 = 0)
        if i >= n then yield -1 end
        if as(i32, p[i]) == target then yield i end
        jump scan(i = i + 1)
    end
    end
end
return find_byte
]]
local c_find = find_byte:compile()
local s = "abc-def"
local buf = ffi.new("uint8_t[?]", #s)
ffi.copy(buf, s, #s)
assert(c_find(buf, #s, string.byte("-")) == 3)
assert(c_find(buf, #s, string.byte("z")) == -1)
c_find:free()

local addk = Host.eval [[
local function make_addk(k)
    return func addk(x: i32) -> i32
        return x + @{k}
    end
end
return make_addk(7)
]]
local c_addk = addk:compile()
assert(c_addk(35) == 42)
c_addk:free()

local typed_add = Host.eval [[
local T = __moonlift_host.i32
local typed_add = func typed_add(x: @{T}) -> @{T}
    return x + 1
end
return typed_add
]]
local c_typed_add = typed_add:compile()
assert(c_typed_add(41) == 42)
c_typed_add:free()

local use_cont_frag = Host.eval [[
local emit_hit = region emit_hit(x: i32; hit: cont(pos: i32))
entry start()
    jump hit(pos = x)
end
end

local use_cont_frag = func use_cont_frag(x: i32) -> i32
    return region -> i32
    entry start()
        emit @{emit_hit}(x; hit = found)
    end
    block found(pos: i32)
        yield pos + 1
    end
    end
end
return use_cont_frag
]]
assert(tostring(use_cont_frag) == "MoonliftFuncQuote(use_cont_frag)")
local c_use_cont_frag = use_cont_frag:compile()
assert(c_use_cont_frag(41) == 42)
c_use_cont_frag:free()

local use_loop_frag = Host.eval [[
local countdown = region countdown(x: i32; done: cont(pos: i32))
entry loop(i: i32 = x)
    if i <= 0 then jump done(pos = i) end
    jump loop(i = i - 1)
end
end

local use_loop_frag = func use_loop_frag(x: i32) -> i32
    return region -> i32
    entry start()
        emit @{countdown}(x; done = finished)
    end
    block finished(pos: i32)
        yield pos + 42
    end
    end
end
return use_loop_frag
]]
local c_use_loop_frag = use_loop_frag:compile()
assert(c_use_loop_frag(5) == 42)
c_use_loop_frag:free()

local use_multiblock_frag = Host.eval [[
local countdown2 = region countdown2(x: i32; done: cont(pos: i32))
entry start(i: i32 = x)
    jump loop(i = i)
end
block loop(i: i32)
    if i <= 0 then jump done(pos = i) end
    jump loop(i = i - 1)
end
end

local use_multiblock_frag = func use_multiblock_frag(x: i32) -> i32
    return region -> i32
    entry start()
        emit countdown2(x; done = finished)
    end
    block finished(pos: i32)
        yield pos + 42
    end
    end
end
return use_multiblock_frag
]]
local c_use_multiblock_frag = use_multiblock_frag:compile()
assert(c_use_multiblock_frag(5) == 42)
c_use_multiblock_frag:free()

local use_expr_frag = Host.eval [[
local inc = expr inc(x: i32) -> i32
    x + 1
end

local use_expr_frag = func use_expr_frag(x: i32) -> i32
    return emit inc(x)
end
return use_expr_frag
]]
assert(tostring(use_expr_frag) == "MoonliftFuncQuote(use_expr_frag)")
local c_use_expr_frag = use_expr_frag:compile()
assert(c_use_expr_frag(41) == 42)
c_use_expr_frag:free()

local mod = Host.eval [[
local m = module
export func add2(x: i32) -> i32
    return x + 2
end

export func mul3(x: i32) -> i32
    return x * 3
end
end
return m
]]
assert(tostring(mod) == "MoonliftModuleQuote")
local cm = mod:compile()
assert(cm:get("add2")(40) == 42)
assert(cm:get("mul3")(14) == 42)
cm:free()

local file_chunk = Host.loadfile("moonlift/test_host_quote_file.mlua")
assert(type(file_chunk) == "function")
local file_add = file_chunk()
local c_file_add = file_add:compile()
assert(c_file_add(37) == 42)
c_file_add:free()
local file_add_again = Host.dofile("moonlift/test_host_quote_file.mlua")
assert(tostring(file_add_again) == "MoonliftFuncQuote(file_add)")

print("moonlift host_quote ok")
