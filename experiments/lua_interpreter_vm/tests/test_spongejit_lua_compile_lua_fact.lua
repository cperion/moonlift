#!/usr/bin/env luajit
package.path = "./experiments/lua_interpreter_vm/spongejit/?.lua;./experiments/lua_interpreter_vm/spongejit/?/init.lua;./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local Runtime = require("lua_compile.lua_fact_from_runtime_observe")
local Foundry = require("lua_compile.lua_fact_from_foundry_bundle")
local Validate = require("lua_compile.lua_fact_validate")
local Contradiction = require("lua_compile.lua_fact_contradiction")
local Payload = require("lua_compile.lua_fact_payload_lease")
local B = require("lua_compile.builders")
local T = B.T
local pvm = require("lalin.pvm")

local function alts(sum)
  local out = {}
  for cls in pairs(sum.members) do if cls.kind then out[#out + 1] = cls.kind end end
  table.sort(out)
  return out
end
local function norm(s) return tostring(s):gsub("([a-z0-9])([A-Z])", "%1_%2"):lower() end
local function assert_ok(e)
  local ok, errs = Validate.validate(e)
  assert(ok, table.concat(errs, "\n"))
  return e
end
local function has_subject(e, kind)
  for _, f in ipairs(e.observed or {}) do if f.subject.kind == kind then return true end end
  for _, p in ipairs(e.payloads or {}) do if p.subject and p.subject.kind == kind then return true end end
  return false
end
local function has_pred(e, kind, value_key)
  for _, f in ipairs(e.observed or {}) do
    if f.predicate.kind == kind and (value_key == nil or f.value_key == value_key) then return true end
  end
  return false
end
local function has_dep(xs, kind)
  for _, d in ipairs(xs or {}) do if d.kind == kind then return true end end
  return false
end

-- Runtime import: every LuaFact.Subject alternative has a stable input shape.
local subject_records = {
  SrcSlot = { subject={kind="SrcSlot", slot=1}, predicate="is_i64" },
  CanonSlot = { subject={kind="CanonSlot", slot_class=2}, predicate="is_i64" },
  Const = { subject={kind="Const", k=3}, predicate="const_i64", value=7 },
  Upvalue = { subject={kind="Upvalue", up=4}, predicate="is_table" },
  TableValue = { subject={kind="TableValue", id=5}, predicate="shape_known", shape_key="shape5" },
  Callsite = { subject={kind="Callsite", pc=6}, predicate="known_call_target", target_key="target6" },
  Memory = { subject={kind="Memory", domain="heap"}, predicate="barrier_clean" },
  Global = { subject={kind="Global"}, predicate="barrier_clean" },
}
local subject_obs = {}
for _, kind in ipairs(alts(T.LuaFact.Subject)) do subject_obs[#subject_obs + 1] = assert(subject_records[kind], "missing subject fixture " .. kind) end
local subject_e = assert_ok(Runtime.observe(subject_obs))
for _, kind in ipairs(alts(T.LuaFact.Subject)) do assert(has_subject(subject_e, kind), "runtime import missed subject " .. kind) end

-- Runtime import: every predicate alias maps to the ASDL predicate alternative and preserves value keys.
local pred_obs = {}
for _, kind in ipairs(alts(T.LuaFact.Predicate)) do
  local alias = norm(kind)
  assert(Runtime.PREDICATE_ALIASES[alias], "missing runtime predicate alias for " .. kind)
  local rec = { slot=1, predicate=alias, value="v" }
  if kind == "ConstI64" then rec = { const=1, predicate=alias, value=11 }
  elseif kind == "ConstF64" then rec = { const=2, predicate=alias, value=1.5 }
  elseif kind == "ShapeEq" or kind == "ShapeKnown" or kind == "MetatableAbsent" then rec.shape_key = "shape1"
  elseif kind == "FieldOffset" then rec.shape_key = "shape1"; rec.key = 9
  elseif kind == "KeyConst" then rec.key = 9
  elseif kind == "KnownCallTarget" or kind == "TargetEq" then rec.target_key = "target1" end
  pred_obs[#pred_obs + 1] = rec
end
local pred_e = assert_ok(Runtime.observe(pred_obs))
for _, kind in ipairs(alts(T.LuaFact.Predicate)) do assert(has_pred(pred_e, kind), "runtime import missed predicate " .. kind) end
assert(has_pred(pred_e, "ShapeEq", "shape1"), "ShapeEq value_key must be shape_key")
assert(has_pred(pred_e, "FieldOffset", "shape1:k9"), "FieldOffset value_key must bind shape/key")
assert(has_pred(pred_e, "TargetEq", "target1"), "TargetEq value_key must be target_key")

-- Dependency aliases: every ASDL dependency alternative imports and validates.
local dep_names = {}
for _, kind in ipairs(alts(T.LuaFact.Dependency)) do
  local alias = norm(kind)
  assert(Runtime.DEPENDENCY_ALIASES[alias], "missing dependency alias for " .. kind)
  dep_names[#dep_names + 1] = alias
end
local dep_e = assert_ok(Runtime.observe({ { slot=1, predicate="is_i64", deps=dep_names } }))
for _, kind in ipairs(alts(T.LuaFact.Dependency)) do assert(has_dep(dep_e.observed[1].deps, kind), "runtime import missed dependency " .. kind) end

-- Payload lease alternatives, including call-target/static source-CALL payloads.
local RT, Exec, GC = T.LuaRT, T.LuaExec, T.LuaGC
local function rn(s) return RT.Name(s) end
local function en(s) return Exec.Name(s) end
local caller = RT.FrameRef(rn("payload_caller"))
local call_ref = RT.CallRef(rn("payload_call"))
local closure_ref = RT.ClosureRef(rn("payload_closure"))
local closure_identity = RT.ClosureIdentity(closure_ref, RT.ProtoRef(B.k(1)), {}, 1)
local resolved_target = RT.ResolvedCallTarget(call_ref, RT.DirectLuaClosureTarget(RT.StackValue(caller, RT.Slot(0)), closure_ref), RT.LuaClosureTargetIdentity(closure_ref, B.k(1), 9, {}), RT.CallableLuaClosure)
local region_id = Exec.RegionId(en("payload_callee"))
local descriptor = Exec.RegionDescriptor(region_id, Exec.ReturnRegion, Exec.ReturnFamily, RT.Pc(20), RT.Pc(21))
local binding = Exec.StaticRegionBinding(Exec.RegionRef(region_id), descriptor, Exec.StaticCalleeBodyRegion)
local entry = Exec.BlockId(en("payload_entry"))
local region = Exec.Region(en("payload_callee"), Exec.ReturnRegion, {}, {}, entry, { Exec.Block(entry, {}, {}, Exec.Continue(Exec.ContRef(en("ret")), {})) })
local gc_lists = GC.GCLists(GC.NoGCRef, GC.NoGCRef, GC.NoGCRef, GC.NoGCRef, GC.NoGCRef, GC.NoGCRef, GC.NoGCRef)
local allocator = GC.Allocator(GC.Name("ctx"), GC.Name("alloc"), GC.Name("realloc"), GC.Name("free"))
local gc_state = GC.GCState(GC.Pause, GC.White0, gc_lists, 0, 0, GC.GCLimits(200, 100, 1024), 1, 2, allocator)
local alloc_req = GC.AllocRequest(gc_state, GC.ClosureKind, 64, 8)
local alloc_header = GC.GCHeader(GC.GCObjectRef(GC.Name("payload_closure_gc")), GC.NoGCRef, GC.ClosureKind, GC.White0, 0, 1)
local allocation = GC.GCAllocationEffect(alloc_req, GC.Allocated(alloc_header))
local payload_obs = {
  { slot=2, payload="shape", pc=10, shape_key="shape2", deps={"shape_epoch"} },
  { slot=2, payload="field", key=9, pc=10, shape_key="shape2", deps={"table_epoch"} },
  { slot=2, payload="array", pc=11, deps={"table_epoch"} },
  { callsite=12, payload="call_target", pc=12, target_key="call:foo", deps={"call_target_epoch"} },
  { slot=0, payload="static_closure_target", pc=14, closure=closure_identity, target=resolved_target, deps={"call_target_epoch"} },
  { slot=0, payload="static_callee_region", pc=14, closure=closure_identity, binding=binding, region=region, deps={"call_target_epoch"} },
  { slot=0, payload="static_closure_value", pc=15, closure=closure_identity, target=resolved_target, binding=binding, allocation=allocation, deps={"call_target_epoch", "gc_barrier_protocol"} },
  { payload="barrier", pc=13, deps={"gc_barrier_protocol"} },
}
local payload_e = assert_ok(Runtime.observe(payload_obs))
local payload_seen = {}
for _, p in ipairs(payload_e.payloads) do payload_seen[p.kind] = true end
for _, kind in ipairs(alts(T.LuaFact.PayloadLease)) do assert(payload_seen[kind], "runtime import missed payload " .. kind) end
assert(has_pred(payload_e, "ShapeEq", "shape2"), "shape payload closure must imply matching ShapeEq")
assert(has_pred(payload_e, "FieldOffset", "shape2:k9"), "field payload closure must imply matching FieldOffset")
assert(has_pred(payload_e, "KnownCallTarget", "call:foo"), "call target payload closure must imply call target fact")

-- Foundry import handles facts and payload leases, not just flat fact arrays.
local foundry = assert_ok(Foundry.from_bundle({
  facts = {
    { subject={kind="slot", id="R3"}, predicate="shape_eq", shape_key="shape3", deps={"shape_epoch"} },
    { subject={kind="slot", id="R3"}, predicate="metatable_absent", shape_key="shape3" },
  },
  payloads = {
    { subject={kind="slot", id="R3"}, payload="shape", pc=20, shape_key="shape3" },
    { subject={kind="slot", id="R3"}, payload="field", key=4, pc=20, shape_key="shape3" },
    { subject={kind="callsite", pc=20}, payload="call_target", pc=20, target_key="call:bar" },
  },
}))
assert(has_pred(foundry, "ShapeEq", "shape3"), "foundry shape fact import must preserve shape_key")
assert(has_pred(foundry, "FieldOffset", "shape3:k4"), "foundry payload import must preserve field shape/key")
assert(has_pred(foundry, "TargetEq", "call:bar"), "foundry call target payload import must preserve target_key")
assert(#foundry.payloads == 3, "foundry import must preserve payload leases")

-- Closure and contradiction rules.
local closure_e = assert_ok(Runtime.observe({
  { slot=1, predicate="is_true" },
  { slot=2, predicate="is_i64" },
  { const=1, predicate="const_f64", value=2.5 },
}))
assert(has_pred(closure_e, "IsBool"), "true/false facts must imply IsBool")
assert(has_pred(closure_e, "IsNumber"), "i64/f64 facts must imply IsNumber")
local ok_bool = Runtime.observe({ { slot=1, predicate="is_true" }, { slot=1, predicate="is_bool" } })
assert(#Contradiction.find(ok_bool) == 0, "IsBool must not contradict true/false subtypes")
local ok_num = Runtime.observe({ { slot=1, predicate="is_i64" }, { slot=1, predicate="is_number" } })
assert(#Contradiction.find(ok_num) == 0, "IsNumber must not contradict numeric subtypes")
local bad = Runtime.observe({ { slot=1, predicate="is_i64" }, { slot=1, predicate="is_table" } })
assert(#Contradiction.find(bad) >= 1)
local bad_bool = Runtime.observe({ { slot=1, predicate="is_nil" }, { slot=1, predicate="is_bool" } })
assert(#Contradiction.find(bad_bool) >= 1, "IsBool must contradict nil/table/number subjects")

-- Payload constructor validation catches malformed leases.
local lease = Payload.field(B.src_slot_subject(1), B.k(9), B.pc(1), "shape")
assert(lease.kind == "FieldPayload")
local malformed_fact = T.LuaFact.Fact(B.src_slot_subject(1), T.LuaFact.IsI64, "", {})
malformed_fact.predicate = "not_a_predicate"
local malformed = T.LuaFact.Evidence({ malformed_fact }, {}, B.region_set({}))
local ok, errs = Validate.validate(malformed)
assert(not ok and table.concat(errs, "\n"):match("predicate"), "validator must reject non-ASDL predicates")
local bad_payload = T.LuaFact.Evidence({}, { T.LuaFact.FieldPayload(B.src_slot_subject(1), B.k(1), B.pc(1), "", {}) }, B.region_set({}))
ok, errs = Validate.validate(bad_payload)
assert(not ok and table.concat(errs, "\n"):match("shape_key"), "validator must reject malformed payload linkage")

print("ok - SpongeJIT LuaCompile LuaFact (subjects/predicates/dependencies/payloads " .. #alts(T.LuaFact.Subject) .. "/" .. #alts(T.LuaFact.Predicate) .. "/" .. #alts(T.LuaFact.Dependency) .. "/" .. #alts(T.LuaFact.PayloadLease) .. ")")
