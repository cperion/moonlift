package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local Host = require("moonlift.mlua_run")

local mod = Host.dofile("lua/moonlift/mom/parser/document_scan.mlua")
local unit = mod:compile()
local scan = unit:get("mom_scan_document")

local ISLAND_FUNC = 1
local ISLAND_REGION = 2
local ISLAND_EXPR = 3
local ISLAND_STRUCT = 4
local ISLAND_UNION = 5
local ISLAND_EXTERN = 6

local function run(src)
    local n = #src
    local p = ffi.new("uint8_t[?]", n > 0 and n or 1)
    if n > 0 then ffi.copy(p, src, n) end
    local cap = 64
    local kinds = ffi.new("int32_t[?]", cap)
    local starts = ffi.new("int32_t[?]", cap)
    local stops = ffi.new("int32_t[?]", cap)
    local name_starts = ffi.new("int32_t[?]", cap)
    local name_stops = ffi.new("int32_t[?]", cap)
    local count = tonumber(scan(p, n, kinds, starts, stops, name_starts, name_stops, cap))
    local out = {}
    for i = 0, count - 1 do
        out[#out + 1] = {
            kind = tonumber(kinds[i]),
            start = tonumber(starts[i]),
            stop = tonumber(stops[i]),
            name = src:sub(tonumber(name_starts[i]) + 1, tonumber(name_stops[i])),
            text = src:sub(tonumber(starts[i]) + 1, tonumber(stops[i])),
        }
    end
    return out
end

local islands = run([==[
local ignored = "func fake() end"
-- region skipped() end
local long = [=[
struct Nope
end
]=]
func add(x: i32) -> i32
  if x > 0 then
    return x
  else
    return 0
  end
end

region scan(p: ptr(u8); ok: cont())
entry start()
  jump ok()
end
end

expr inc(x: i32) -> i32
  x + 1
end

struct Pair
  left: i32
end
union Maybe
  none
end
extern puts(p: ptr(u8)) -> i32 end
]==])

assert(#islands == 6, "islands: " .. #islands)
assert(islands[1].kind == ISLAND_FUNC and islands[1].name == "add", "func island")
assert(islands[2].kind == ISLAND_REGION and islands[2].name == "scan", "region island")
assert(islands[3].kind == ISLAND_EXPR and islands[3].name == "inc", "expr island")
assert(islands[4].kind == ISLAND_STRUCT and islands[4].name == "Pair", "struct island")
assert(islands[5].kind == ISLAND_UNION and islands[5].name == "Maybe", "union island")
assert(islands[6].kind == ISLAND_EXTERN and islands[6].name == "puts", "extern island")
assert(islands[1].text:match("if x > 0 then"), "function range retains nested if")
assert(not islands[1].text:match("region scan"), "function range stops at own end")

unit.artifact:free()
print("mom document scan ok")
