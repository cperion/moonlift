package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local Parse = require("moonlift.parse")

local toks = Parse.lex("@{xs...} @{ y ... } @{z}")
assert(toks.splice_map["splice.1"] == "xs")
assert(toks.splice_spread["splice.1"] == true)
assert(toks.splice_map["splice.2"] == " y")
assert(toks.splice_spread["splice.2"] == true)
assert(toks.splice_map["splice.3"] == "z")
assert(toks.splice_spread["splice.3"] == nil)

local scan = Parse.scan_document [[
func f(): i32
    @{stmts...}
    return 1
end
]]
assert(scan.splice_map["splice.1"] == "stmts")
assert(scan.splice_spread["splice.1"] == true)

print("moonlift parse spread splice ok")
