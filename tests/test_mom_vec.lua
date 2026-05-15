package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local Host = require("moonlift.mlua_run")

local function compile(path)
    local mod = Host.dofile(path)
    local compiled, err = mod:compile()
    assert(compiled, "compile " .. path .. ": " .. tostring(err))
    return compiled
end

-- Phase 8a: vec_facts.mlua — fact extraction
local vf_mod = compile("lua/moonlift/mom/vec/vec_facts.mlua")
local mv_extract_vec_facts = vf_mod:get("mv_extract_vec_facts")

local ncf = 8
local cft = ffi.new("int32_t[?]", ncf)
local cfa = ffi.new("int32_t[?]", ncf)
local cfb = ffi.new("int32_t[?]", ncf)
local cfc = ffi.new("int32_t[?]", ncf)
cft[0]=1; cfa[0]=0
cft[1]=3; cfa[1]=0; cfc[1]=5
cft[2]=3; cfa[2]=1; cfc[2]=5
cft[3]=2; cfa[3]=1
cft[4]=4; cfa[4]=0; cfc[4]=5
cft[5]=4; cfa[5]=1; cfc[5]=5
cft[6]=10; cfa[6]=1; cfb[6]=1
cft[7]=9

local pb = ffi.new("int32_t[8]")
local ps = ffi.new("int32_t[8]")
local vft = ffi.new("int32_t[64]")
local vfa = ffi.new("int32_t[64]")
local vfb = ffi.new("int32_t[64]")
local vfc = ffi.new("int32_t[64]")
local vfd = ffi.new("int32_t[64]")
local vfe = ffi.new("int32_t[64]")
local vff = ffi.new("int32_t[64]")
local vfcnt = ffi.new("int32_t[1]", 0)

local res = mv_extract_vec_facts(cft, cfa, cfb, cfc, cfa, cfb, cfc, ncf,
                                  pb, ps, 8,
                                  vft, vfa, vfb, vfc, vfd, vfe, vff,
                                  vfcnt, 64)
assert(res == 1, "vec_facts recognized: " .. tonumber(res))
assert(vfcnt[0] >= 3, "vec_facts count: " .. tonumber(vfcnt[0]))
assert(vft[0] == 1, "vec_facts[0] domain: " .. tonumber(vft[0]))
assert(vft[1] == 2, "vec_facts[1] induction: " .. tonumber(vft[1]))
assert(vft[2] == 10, "vec_facts[2] reduction: " .. tonumber(vft[2]))

local vd_mod = compile("lua/moonlift/mom/vec/vec_decide.mlua")
local mv_decide = vd_mod:get("mv_decide")
local dec_arr = ffi.new("int32_t[6]")
local dec_cnt = ffi.new("int32_t[1]", 0)
mv_decide(vft, vfa, vfb, vfc, vfd, vfe, vff, vfcnt[0], 128,
          dec_arr, dec_cnt, 6)
assert(dec_cnt[0] == 1, "decide count: " .. tonumber(dec_cnt[0]))
assert(dec_arr[0] == 1, "decide legal: " .. tonumber(dec_arr[0]))
assert(dec_arr[2] == 4, "decide lanes: " .. tonumber(dec_arr[2]))

local vp_mod = compile("lua/moonlift/mom/vec/vec_plan.mlua")
local mv_plan_kernel = vp_mod:get("mv_plan_kernel")
local pt_arr = ffi.new("int32_t[5]")
local pa_arr = ffi.new("int32_t[5]")
local pb_arr = ffi.new("int32_t[5]")
local pc_arr = ffi.new("int32_t[5]")
local pd_arr = ffi.new("int32_t[5]")
local pcnt = ffi.new("int32_t[1]", 0)
mv_plan_kernel(vft, vfa, vfb, vfc, vfd, vfe, vff, vfcnt[0],
               dec_arr, dec_cnt[0],
               pt_arr, pa_arr, pb_arr, pc_arr, pd_arr, pcnt, 5)
assert(pcnt[0] == 1, "plan count: " .. tonumber(pcnt[0]))
assert(pt_arr[0] == 4, "plan algebraic: " .. tonumber(pt_arr[0]))

local vl_mod = compile("lua/moonlift/mom/vec/vec_lower.mlua")
local mv_lower_kernel = vl_mod:get("mv_lower_kernel")
local lct = ffi.new("int32_t[?]", 64)
local lca = ffi.new("int32_t[?]", 64)
local lcb = ffi.new("int32_t[?]", 64)
local lcc = ffi.new("int32_t[?]", 64)
local lcd = ffi.new("int32_t[?]", 64)
local lce = ffi.new("int32_t[?]", 64)
local lcf = ffi.new("int32_t[?]", 64)
local lcnt = ffi.new("int32_t[1]", 0)
local lst = ffi.new("int32_t[2]", {100, 200})
mv_lower_kernel(pt_arr, pa_arr, pb_arr, pc_arr, pd_arr, pcnt[0],
               dec_arr, dec_cnt[0],
               lct, lca, lcb, lcc, lcd, lce, lcf, lcnt, 64, lst)
assert(lcnt[0] > 0, "lower cmds: " .. tonumber(lcnt[0]))
local nblocks = 0
for i = 0, lcnt[0] - 1 do
    if lct[i] == 12 then nblocks = nblocks + 1 end
end
assert(nblocks == 4, "lower blocks: " .. tonumber(nblocks))
assert(lct[lcnt[0] - 1] == 55, "lower ends with return void")

vf_mod:free()
vd_mod:free()
vp_mod:free()
vl_mod:free()

print("mom vec pipeline ok")
