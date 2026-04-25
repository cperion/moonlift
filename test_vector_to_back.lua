package.path = "./?.lua;./?/init.lua;./moonlift/lua/?.lua;./moonlift/lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local pvm = require("pvm")
local A = require("moonlift.asdl")
local Source = require("moonlift.source")
local VecFacts = require("moonlift.vector_facts")
local VecToBack = require("moonlift.vector_to_back")
local J = require("moonlift.jit")

local T = pvm.context()
A.Define(T)
local S = Source.Define(T)
local VF = VecFacts.Define(T)
local VB = VecToBack.Define(T)
local jit = J.Define(T).jit()
local Sem = T.MoonliftSem
local Back = T.MoonliftBack

local sem = S.sem_module([[
func sum_for_index(n: index) -> index
    for i in 0..n with acc: index = 0 do
        let term: index = (i * 1664525 + 1013904223) & 1023
        next acc = acc + term
    end
    return acc
end
]])
local loop = sem.items[1].func.body[1].loop
local decision = pvm.one(VF.vector_loop_decision(loop, 2, 1))
local back = pvm.one(VB.lower_decision(decision, "sum_for_index_vec"))
local unroll_module = pvm.one(VF.vector_module(sem, nil, 2, 4))
assert(#unroll_module.funcs[1].blocks > 0, "expected VecBlock skeleton for ordinary vector loop")
local unroll_back = pvm.one(VB.lower_module(unroll_module, "sum_for_index_vec_u4"))
local chunk_decision = pvm.one(VF.vector_loop_decision(loop, 4, 4, 1048576))
local chunk_module = pvm.one(VF.vector_module(sem, nil, 4, 4, 1048576))
assert(#chunk_module.funcs[1].blocks > 0, "expected VecBlock skeleton for chunked narrow vector loop")
local chunk_back = pvm.one(VB.lower_module(chunk_module, "sum_for_index_vec_i32c"))
local artifact = jit:compile(back)
local unroll_artifact = jit:compile(unroll_back)
local chunk_artifact = jit:compile(chunk_back)
local f = ffi.cast("intptr_t (*)(intptr_t)", artifact:getpointer(Back.BackFuncId("sum_for_index_vec")))
local fu = ffi.cast("intptr_t (*)(intptr_t)", unroll_artifact:getpointer(Back.BackFuncId("sum_for_index_vec_u4")))
local fc = ffi.cast("intptr_t (*)(intptr_t)", chunk_artifact:getpointer(Back.BackFuncId("sum_for_index_vec_i32c")))

local function ref(n)
    local acc = 0
    for i = 0, n - 1 do
        acc = acc + bit.band(i * 1664525 + 1013904223, 1023)
    end
    return acc
end

for _, n in ipairs({0, 1, 2, 3, 4, 5, 31, 32, 33, 1000}) do
    assert(tonumber(f(n)) == ref(n), "n=" .. n .. " got " .. tostring(f(n)) .. " expected " .. tostring(ref(n)))
    assert(tonumber(fu(n)) == ref(n), "u4 n=" .. n .. " got " .. tostring(fu(n)) .. " expected " .. tostring(ref(n)))
    assert(tonumber(fc(n)) == ref(n), "i32c n=" .. n .. " got " .. tostring(fc(n)) .. " expected " .. tostring(ref(n)))
end

local disasm = artifact:disasm("sum_for_index_vec", { bytes = 256 })
assert(disasm:find("xmm", 1, true) or disasm:find("ymm", 1, true) or disasm:find("zmm", 1, true), disasm)
chunk_artifact:free()
unroll_artifact:free()
artifact:free()

local p_param = Sem.SemParam("p", Sem.SemTPtrTo(Sem.SemTIndex))
local n_param = Sem.SemParam("n", Sem.SemTIndex)
local load_loop_id = "loop.sum_ptr"
local load_carry = Sem.SemCarryPort("acc.port", "acc", Sem.SemTIndex, Sem.SemExprConstInt(Sem.SemTIndex, "0"))
local load_index = Sem.SemBindLoopIndex(load_loop_id, "i", Sem.SemTIndex)
local load_acc = Sem.SemBindLoopCarry(load_loop_id, "acc.port", "acc", Sem.SemTIndex)
local p_binding = Sem.SemBindArg(0, "p", Sem.SemTPtrTo(Sem.SemTIndex))
local n_binding = Sem.SemBindArg(1, "n", Sem.SemTIndex)
local load_expr = Sem.SemExprIndex(
    Sem.SemIndexBaseView(Sem.SemViewContiguous(Sem.SemExprBinding(p_binding), Sem.SemTIndex, Sem.SemExprBinding(n_binding))),
    Sem.SemExprBinding(load_index),
    Sem.SemTIndex
)
local load_loop = Sem.SemOverStmt(
    load_loop_id,
    Sem.SemIndexPort("i", Sem.SemTIndex),
    Sem.SemDomainRange(Sem.SemExprBinding(n_binding)),
    { load_carry },
    {},
    {
        Sem.SemCarryUpdate(
            "acc.port",
            Sem.SemExprAdd(Sem.SemTIndex, Sem.SemExprBinding(load_acc), load_expr)
        ),
    }
)
local load_func = Sem.SemFuncExport("sum_ptr_vec", { p_param, n_param }, Sem.SemTIndex, {
    Sem.SemStmtLoop(load_loop),
    Sem.SemStmtReturnValue(Sem.SemExprBinding(load_acc)),
})
local load_module = Sem.SemModule("", { Sem.SemItemFunc(load_func) })
local load_vec = pvm.one(VF.vector_module(load_module, nil, 2, 2))
assert(#load_vec.funcs[1].decisions[1].facts.memory == 1, "expected vector memory access fact")
local load_back = pvm.one(VB.lower_module(load_vec, "sum_ptr_vec"))
local saw_vec_load = false
for i = 1, #load_back.cmds do
    if pvm.classof(load_back.cmds[i]) == Back.BackCmdVecLoad then
        saw_vec_load = true
        break
    end
end
assert(saw_vec_load, "expected BackCmdVecLoad")
local load_artifact = jit:compile(load_back)
local load_f = ffi.cast("intptr_t (*)(intptr_t*, intptr_t)", load_artifact:getpointer(Back.BackFuncId("sum_ptr_vec")))
local arr = ffi.new("intptr_t[10]")
local load_ref = 0
for i = 0, 9 do
    arr[i] = i + 1
    load_ref = load_ref + i + 1
end
assert(tonumber(load_f(arr, 10)) == load_ref)
load_artifact:free()

local fill_loop_id = "loop.fill_ptr"
local fill_index = Sem.SemBindLoopIndex(fill_loop_id, "i", Sem.SemTIndex)
local fill_place = Sem.SemPlaceIndex(
    Sem.SemIndexBaseView(Sem.SemViewContiguous(Sem.SemExprBinding(p_binding), Sem.SemTIndex, Sem.SemExprBinding(n_binding))),
    Sem.SemExprBinding(fill_index),
    Sem.SemTIndex
)
local fill_value = Sem.SemExprAdd(Sem.SemTIndex, Sem.SemExprBinding(fill_index), Sem.SemExprConstInt(Sem.SemTIndex, "1"))
local fill_loop = Sem.SemOverStmt(
    fill_loop_id,
    Sem.SemIndexPort("i", Sem.SemTIndex),
    Sem.SemDomainRange(Sem.SemExprBinding(n_binding)),
    {},
    { Sem.SemStmtSet(fill_place, fill_value) },
    {}
)
local fill_func = Sem.SemFuncExport("fill_ptr_vec", { p_param, n_param }, Sem.SemTVoid, {
    Sem.SemStmtLoop(fill_loop),
    Sem.SemStmtReturnVoid,
})
local fill_module = Sem.SemModule("", { Sem.SemItemFunc(fill_func) })
local fill_vec = pvm.one(VF.vector_module(fill_module, nil, 2, 2))
assert(#fill_vec.funcs[1].decisions[1].facts.stores == 1, "expected vector store fact")
local fill_back = pvm.one(VB.lower_module(fill_vec, "fill_ptr_vec"))
local saw_vec_store = false
for i = 1, #fill_back.cmds do
    if pvm.classof(fill_back.cmds[i]) == Back.BackCmdVecStore then
        saw_vec_store = true
        break
    end
end
assert(saw_vec_store, "expected BackCmdVecStore")
local fill_artifact = jit:compile(fill_back)
local fill_f = ffi.cast("void (*)(intptr_t*, intptr_t)", fill_artifact:getpointer(Back.BackFuncId("fill_ptr_vec")))
local fill_arr = ffi.new("intptr_t[10]")
fill_f(fill_arr, 10)
for i = 0, 9 do
    assert(tonumber(fill_arr[i]) == i + 1, "fill[" .. i .. "] = " .. tostring(fill_arr[i]))
end
fill_artifact:free()

local map_loop_id = "loop.map_in_place_ptr"
local map_index = Sem.SemBindLoopIndex(map_loop_id, "i", Sem.SemTIndex)
local map_view = Sem.SemViewContiguous(Sem.SemExprBinding(p_binding), Sem.SemTIndex, Sem.SemExprBinding(n_binding))
local map_load = Sem.SemExprIndex(Sem.SemIndexBaseView(map_view), Sem.SemExprBinding(map_index), Sem.SemTIndex)
local map_place = Sem.SemPlaceIndex(Sem.SemIndexBaseView(map_view), Sem.SemExprBinding(map_index), Sem.SemTIndex)
local map_loop = Sem.SemOverStmt(
    map_loop_id,
    Sem.SemIndexPort("i", Sem.SemTIndex),
    Sem.SemDomainRange(Sem.SemExprBinding(n_binding)),
    {},
    { Sem.SemStmtSet(map_place, Sem.SemExprAdd(Sem.SemTIndex, map_load, Sem.SemExprConstInt(Sem.SemTIndex, "1"))) },
    {}
)
local map_func = Sem.SemFuncExport("map_add1_in_place_vec", { p_param, n_param }, Sem.SemTVoid, {
    Sem.SemStmtLoop(map_loop),
    Sem.SemStmtReturnVoid,
})
local map_module = Sem.SemModule("", { Sem.SemItemFunc(map_func) })
local map_vec = pvm.one(VF.vector_module(map_module, nil, 2, 2))
assert(#map_vec.funcs[1].decisions[1].facts.memory == 2, "expected load and store memory facts")
assert(#map_vec.funcs[1].decisions[1].facts.dependences == 1, "expected dependence fact")
local map_back = pvm.one(VB.lower_module(map_vec, "map_add1_in_place_vec"))
local map_saw_vec_load = false
local map_saw_vec_store = false
for i = 1, #map_back.cmds do
    if pvm.classof(map_back.cmds[i]) == Back.BackCmdVecLoad then
        map_saw_vec_load = true
    elseif pvm.classof(map_back.cmds[i]) == Back.BackCmdVecStore then
        map_saw_vec_store = true
    end
end
assert(map_saw_vec_load, "expected map BackCmdVecLoad")
assert(map_saw_vec_store, "expected map BackCmdVecStore")
local map_artifact = jit:compile(map_back)
local map_f = ffi.cast("void (*)(intptr_t*, intptr_t)", map_artifact:getpointer(Back.BackFuncId("map_add1_in_place_vec")))
local map_arr = ffi.new("intptr_t[11]")
for i = 0, 10 do map_arr[i] = i * 3 end
map_f(map_arr, 11)
for i = 0, 10 do
    assert(tonumber(map_arr[i]) == i * 3 + 1, "map[" .. i .. "] = " .. tostring(map_arr[i]))
end
map_artifact:free()

print("moonlift vector to back ok")
