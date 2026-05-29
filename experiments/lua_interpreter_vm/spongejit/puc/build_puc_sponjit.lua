#!/usr/bin/env luajit
-- Build a vendored PUC Lua with the real SponJIT region/image hook.

local source = debug.getinfo(1, "S").source
local this = source:sub(1, 1) == "@" and source:sub(2) or source
local spongejit = this:match("^(.*)/puc/build_puc_sponjit%.lua$") or "experiments/lua_interpreter_vm/spongejit"
local repo = spongejit:sub(1, 1) == "/" and spongejit:gsub("/experiments/lua_interpreter_vm/spongejit$", "") or "."
local pwd_f = assert(io.popen("pwd", "r")); local cwd = pwd_f:read("*l"); pwd_f:close()
local abs_spongejit = spongejit:sub(1,1) == "/" and spongejit or (cwd .. "/" .. spongejit)
local abs_repo = repo:sub(1,1) == "/" and repo or (cwd .. "/" .. repo)

local function q(s) return "'" .. tostring(s):gsub("'", [['"'"']]) .. "'" end
local function run(cmd)
  io.stderr:write("[puc-sponjit] ", cmd, "\n")
  local ok = os.execute(cmd)
  if ok ~= true and ok ~= 0 then error("command failed: " .. cmd) end
end
local function read(path) local f=assert(io.open(path,"rb"),path); local s=f:read("*a"); f:close(); return s end
local function write(path,s) local f=assert(io.open(path,"wb"),path); f:write(s); f:close() end
local function replace_once(s, old, new, label)
  local n; s,n=s:gsub(old:gsub("([^%w])","%%%1"), function() return new end, 1)
  if n ~= 1 then error("patch failed " .. label .. " matches=" .. tostring(n)) end
  return s
end

local out = spongejit .. "/build/puc_sponjit"
local vendor = repo .. "/.vendor/Lua"
local bank = os.getenv("SPON_BANK_DIR") or (abs_spongejit .. "/build/cp_lib")
local inc = abs_spongejit .. "/include"
local stamp = out .. "/.puc_sponjit.cachekey"

local function file_key(paths)
  local cmd = "(printf %s " .. q("bank=" .. bank .. "\n") .. "; "
  for _, p in ipairs(paths) do cmd = cmd .. "sha256sum " .. q(p) .. " 2>/dev/null; " end
  cmd = cmd .. ") | sha256sum | awk '{print $1}'"
  local f = assert(io.popen(cmd, "r")); local k = f:read("*l") or ""; f:close(); return k
end
local key = file_key({
  this,
  spongejit .. "/puc/lsponjit.c", spongejit .. "/puc/lsponjit.h",
  spongejit .. "/puc/sponjit_runtime.c", spongejit .. "/puc/sponjit_runtime.h",
  spongejit .. "/include/sponbank.h",
})

local cached = false
if os.getenv("FORCE") ~= "1" and os.getenv("FORCE_PUC") ~= "1" then
  local sf = io.open(stamp, "rb")
  local old = sf and sf:read("*l") or nil
  if sf then sf:close() end
  local mf = io.open(out .. "/makefile", "rb")
  cached = old == key and mf ~= nil
  if mf then mf:close() end
end

if cached then
  io.stderr:write("[puc-sponjit] cache hit: reusing patched tree ", out, "\n")
else
  run("rm -rf " .. q(out))
  run("mkdir -p " .. q(out))
  run("cp -R " .. q(vendor) .. "/* " .. q(out) .. "/")
  run("cp " .. q(spongejit .. "/puc/lsponjit.c") .. " " .. q(spongejit .. "/puc/lsponjit.h") .. " " ..
      q(spongejit .. "/puc/sponjit_runtime.c") .. " " .. q(spongejit .. "/puc/sponjit_runtime.h") .. " " .. q(out) .. "/")
end

if not cached then
  local lobject = out .. "/lobject.h"
  local s = read(lobject)
  s = replace_once(s, "  TString  *source;  /* used for debug information */\n  GCObject *gclist;",
                     "  TString  *source;  /* used for debug information */\n  void *sponjit;  /* optional SponJIT Proto metadata */\n  GCObject *gclist;", "Proto.sponjit")
  write(lobject, s)

  local lfunc = out .. "/lfunc.c"
  s = read(lfunc)
  s = replace_once(s, '#include "lfunc.h"\n', '#include "lfunc.h"\n#include "lsponjit.h"\n', "include lsponjit")
  s = replace_once(s, "  f->source = NULL;\n  return f;", "  f->source = NULL;\n  f->sponjit = NULL;\n  return f;", "init sponjit")
  s = replace_once(s, "void luaF_freeproto (lua_State *L, Proto *f) {\n  if (!(f->flag & PF_FIXED)) {",
                     "void luaF_freeproto (lua_State *L, Proto *f) {\n  luaSponJIT_freeproto(L, f);\n  if (!(f->flag & PF_FIXED)) {", "free sponjit")
  write(lfunc, s)

  local hook = [[
    if (luaSponJIT_maybe_enter(L, ci, cl->p, base, &pc, i, trap)) {
      updatetrap(ci);
      continue;
    }
]]
  local lvm = out .. "/lvm.c"
  s = read(lvm)
  s = replace_once(s, '#include "lvm.h"\n', '#include "lvm.h"\n#include "lsponjit.h"\n', "include lsponjit in lvm")
  s = replace_once(s, '    lua_assert(luaP_isIT(i) || (cast_void(L->top.p = base), 1));\n    vmdispatch (GET_OPCODE(i)) {',
                     '    lua_assert(luaP_isIT(i) || (cast_void(L->top.p = base), 1));\n' .. hook .. '    vmdispatch (GET_OPCODE(i)) {', "vm hook")
  write(lvm, s)

  local jt = out .. "/ljumptab.h"
  local ok_jt, js = pcall(read, jt)
  if ok_jt then
    js = replace_once(js, '#define vmbreak\t\tvmfetch(); vmdispatch(GET_OPCODE(i));',
                      '#define vmbreak\t\tvmfetch(); if (luaSponJIT_maybe_enter(L, ci, cl->p, base, &pc, i, trap)) { updatetrap(ci); continue; } vmdispatch(GET_OPCODE(i));',
                      "jumptable hook")
    write(jt, js)
  end

  local mf = out .. "/makefile"
  s = read(mf)
  s = replace_once(s, "MYCFLAGS= $(LOCAL) -std=c99 -DLUA_USE_LINUX",
                     "MYCFLAGS= $(LOCAL) -std=c99 -DLUA_USE_LINUX -DLUA_USE_SPONJIT -I" .. inc, "make cflags")
  s = replace_once(s, "\tltm.o lundump.o lvm.o lzio.o ltests.o",
                     "\tlsponjit.o sponjit_runtime.o \\\n\tltm.o lundump.o lvm.o lzio.o ltests.o", "make objects")
  s = replace_once(s, "\t$(CC) -o $@ $(MYLDFLAGS) $(LUA_O) $(CORE_T) $(LIBS) $(MYLIBS) $(DL)",
                     "\t$(CC) -o $@ $(MYLDFLAGS) $(LUA_O) $(CORE_T) -L" .. bank .. " -Wl,-rpath," .. bank .. " -lsponbank $(LIBS) $(MYLIBS) $(DL)", "link bank")
  write(mf, s)
  write(stamp, key .. "\n")
end

run("cd " .. q(out) .. " && make -s -j lua")
print("sponjit_lua=" .. out .. "/lua")
