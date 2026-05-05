package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path
local ffi = require("ffi");local pvm = require("moonlift.pvm");local A2 = require("moonlift.asdl")
local T = pvm.context();A2.Define(T)
local mlua_parse = require("moonlift.mlua_parse").Define(T)
local OE = require("moonlift.open_expand").Define(T)
local TC = require("moonlift.tree_typecheck").Define(T)
local Layout = require("moonlift.sem_layout_resolve").Define(T)
local Lower = require("moonlift.tree_to_back").Define(T)
local BL = require("moonlift.back_luajit").Define(T)

local src = [[
export func fib(n: i32) -> i32
    if n <= 1 then return n end
    return fib(n - 1) + fib(n - 2)
end
]]
local parsed = mlua_parse.parse(src, "test")
local expanded = OE.module(parsed.module)
local checked = TC.check_module(expanded)
local resolved = Layout.module(checked.module, {})
local program = Lower.module(resolved)

-- Instrument the backend to print generated source
-- Patch quote:compile to print source
local quote = require("moonlift.quote")
local orig_compile = quote.compile_source
quote.compile_source = function(src, env, name)
    print("=== GENERATED SOURCE (" .. (name or "?") .. ") ===")
    print(src)
    print("=== END ===")
    return orig_compile(src, env, name)
end

-- Now re-require to get a fresh instance
-- Actually the patching needs to happen differently since BL already loaded
-- Let me just run with the patched compile
local function cls(x) return pvm.classof(x) end
local function itxt(id) if type(id) == "string" then return id end; return id.text end
local function ish(t) return t:gsub("[^%w]", "_"):gsub("_+", "_"):gsub("^_", ""):gsub("_$", "") end

-- Rebuild what back_luajit would produce
local cmds = program.cmds
local sigs = {}
local funcs = {}
local exported = {}
local blocks = {}
local vals = {}
local entry_params = {}
local block_params = {}
local func_entry_block = {}
local cf = nil
local vs, ss, bs = 0, 0, 0

local function rv(id)
    if id == nil then return nil end
    local vt = itxt(id); if vt == nil then return nil end
    if not vals[vt] then vs = vs + 1; vals[vt] = string.format("v%d", vs) end
    return vals[vt]
end

for _, cmd in ipairs(cmds) do
    local c = cls(cmd)
    if c == T.MoonBack.CmdCreateSig then sigs[itxt(cmd.sig)] = {params = cmd.params, results = cmd.results}
    elseif c == T.MoonBack.CmdDeclareFunc then
        local fid = itxt(cmd.func); funcs[fid] = {sig = sigs[itxt(cmd.sig)]}
        if cmd.visibility and cls(cmd.visibility) == T.MoonCore.VisibilityExport then exported[fid] = true end
    elseif c == T.MoonBack.CmdBeginFunc then cf = itxt(cmd.func); entry_params[cf] = {}
    elseif c == T.MoonBack.CmdBindEntryParams then
        func_entry_block[cf] = itxt(cmd.block)
        for _, v in ipairs(cmd.values) do entry_params[cf][#entry_params[cf] + 1] = itxt(v) end
    elseif c == T.MoonBack.CmdCreateBlock then
        bs = bs + 1; blocks[itxt(cmd.block)] = string.format("b%d_%s", bs, ish(itxt(cmd.block)))
    elseif c == T.MoonBack.CmdAppendBlockParam then
        local bid = itxt(cmd.block); if not block_params[bid] then block_params[bid] = {} end
        block_params[bid][#block_params[bid] + 1] = itxt(cmd.value)
    end
    if cmd.dst then rv(cmd.dst) end; if cmd.src then rv(cmd.src) end
    if cmd.lhs then rv(cmd.lhs) end; if cmd.rhs then rv(cmd.rhs) end
    if cmd.value then rv(cmd.value) end
    if cmd.result and cls(cmd.result) == T.MoonBack.BackCallValue then rv(cmd.result.dst) end
    if cmd.args then for _, a in ipairs(cmd.args) do rv(a) end end
end

print("vals:", vals)
print("entry_params:", entry_params)

-- Now generate the source manually for fib
local buf = quote()
cf = nil
local self_ret_seq = 0
local self_ret_labels = {}

local function vn(val) return vals[itxt(val)] end
local function lb(id) return blocks[itxt(id)] end

for _, cmd in ipairs(cmds) do
    local c = cls(cmd)
    if c == T.MoonBack.CmdBeginFunc then
        cf = itxt(cmd.func); local ep = entry_params[cf] or {}
        buf = quote(); self_ret_seq = 0; self_ret_labels = {}
        local pns = {}; for _, p in ipairs(ep) do pns[#pns + 1] = vn(p) end
        buf("local function fn_%s(%s)", ish(cf), table.concat(pns, ", "))
        buf("local ffi=require(\"ffi\")")
        buf("local bit=require(\"bit\")")
        buf("local _cs={} local _sp=0 local _r=nil")
        for i = 1, vs do
            local nm = string.format("v%d", i)
            local skip = false
            for _, p in ipairs(ep) do if vn(p) == nm then skip = true end end
            if not skip then buf("local %s", nm) end
        end
    elseif c == T.MoonBack.CmdCreateBlock then
        bs = bs + 1; blocks[itxt(cmd.block)] = string.format("b%d_%s", bs, ish(itxt(cmd.block)))
    elseif c == T.MoonBack.CmdSwitchToBlock then
        buf("::%s::", lb(cmd.block))
    elseif c == T.MoonBack.CmdCall then
        local tc = cls(cmd.target)
        if tc == T.MoonBack.BackCallDirect and itxt(cmd.target.func) == cf then
            self_ret_seq = self_ret_seq + 1
            local rl = string.format("sret%d", self_ret_seq)
            self_ret_labels[#self_ret_labels + 1] = rl
            local ags = {}; for _, a in ipairs(cmd.args) do ags[#ags + 1] = vn(a) end
            local ep = entry_params[cf]
            -- Push frame with saved params
            buf("_sp=_sp+1")
            buf("_cs[_sp]={ret=\"%s\"", rl)
            for i, pid in ipairs(ep) do buf(",s%d=%s", i, vn(pid)) end
            buf("}")
            -- Set callee params
            for i = 1, #ags do
                if ep[i] then buf("%s=%s", vn(ep[i]), ags[i]) end
            end
            local entry_lbl = func_entry_block[cf] and blocks[func_entry_block[cf]]
            if entry_lbl then buf("goto %s", entry_lbl) end
            buf("::%s::", rl)
            if cls(cmd.result) == T.MoonBack.BackCallValue then
                buf("%s=_r", vn(cmd.result.dst))
            end
        end
    elseif c == T.MoonBack.CmdReturnValue then
        buf("_r=%s", vn(cmd.value))
        buf("if _sp>0 then goto return_dispatch end")
        buf("do return _r end")
    elseif c == T.MoonBack.CmdIntBinary then
        buf("%s=(%s + %s)", vn(cmd.dst), vn(cmd.lhs), vn(cmd.rhs))
    elseif c == T.MoonBack.CmdConst then
        buf("%s=%s", vn(cmd.dst), cmd.value.raw)
    elseif c == T.MoonBack.CmdCompare then
        buf("%s=(%s <= %s)", vn(cmd.dst), vn(cmd.lhs), vn(cmd.rhs))
    elseif c == T.MoonBack.CmdBrIf then
        buf("if %s then goto %s else goto %s end", vn(cmd.cond), lb(cmd.then_block), lb(cmd.else_block))
    elseif c == T.MoonBack.CmdJump then
        buf("goto %s", lb(cmd.dest))
    elseif c == T.MoonBack.CmdFinishFunc then
        buf("::return_dispatch::")
        if #self_ret_labels > 0 then
            local ep = entry_params[cf]; local ep_vs = {}; for _, p in ipairs(ep or {}) do ep_vs[#ep_vs + 1] = vn(p) end
            buf("local fr=_cs[_sp]; _sp=_sp-1")
            for i, pv in ipairs(ep_vs) do buf("%s=fr.s%d", pv, i) end
            buf("local _ret=fr.ret")
            for i, rl in ipairs(self_ret_labels) do
                if i == 1 then buf("if _ret==\"%s\" then goto %s", rl, rl)
                else buf("elseif _ret==\"%s\" then goto %s", rl, rl) end
            end
            buf("else error(\"bad ret: \"..tostring(_ret)) end")
        else
            buf("error(\"return_dispatch no trampoline\")")
        end
        buf("end")
        buf("return fn_%s", ish(cf))
    end
end

local src = buf:source()
print("=== SOURCE ===")
print(src)
print("=== END ===")
