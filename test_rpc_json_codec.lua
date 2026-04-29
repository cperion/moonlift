package.path = "./?.lua;./?/init.lua;./moonlift/lua/?.lua;./moonlift/lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local A = require("moonlift.asdl")
local DecodeMod = require("moonlift.rpc_json_decode")
local EncodeMod = require("moonlift.rpc_json_encode")

local T = pvm.context()
A.Define(T)
local R = T.Moon2Rpc
local E = T.Moon2Editor
local Decode = DecodeMod.Define(T)
local Encode = EncodeMod.Define(T)

local req = Decode.decode_message([[{"jsonrpc":"2.0","id":"abc","method":"textDocument/hover","params":{"x":null}}]])
assert(pvm.classof(req) == R.RpcRequest)
assert(req.id == E.RpcIdString("abc"))
assert(req.method == "textDocument/hover")
local params = Decode.value_to_lua(req.params)
assert(params.x == Decode.JSON_NULL)

local n = Decode.decode_message([[{"jsonrpc":"2.0","method":"initialized","params":{}}]])
assert(pvm.classof(n) == R.RpcIncomingNotification)
assert(n.method == "initialized")

local bad = Decode.decode_message([[{"jsonrpc":"2.0","id":1,"method":]])
assert(pvm.classof(bad) == R.RpcInvalid)
assert(bad.reason:match("json decode error"))

local encoded = Encode.encode_lua({ b = true, a = { 1, "x", Encode.JSON_NULL } })
assert(encoded == [[{"a":[1,"x",null],"b":true}]])
local round = Decode.decode_lua(encoded)
assert(round.a[1] == 1 and round.a[2] == "x" and round.a[3] == Decode.JSON_NULL and round.b == true)

print("moonlift rpc json codec ok")
