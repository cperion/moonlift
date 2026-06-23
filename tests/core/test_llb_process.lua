package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local llb = require("llb")

local records = llb.process. records (function(ctx, bytes)
  ctx. header {
    magic = bytes:sub(1, 4),
    size = #bytes,
  }

  local offset = 5
  while offset <= #bytes do
    ctx:consume(1)
    ctx. record {
      offset = offset,
      byte = bytes:byte(offset),
    }
    offset = offset + 1
  end

  return {
    bytes = #bytes,
  }
end)

local seen = {}
for ev in records("LLPVabc") do
  seen[#seen + 1] = ev
end
assert(#seen == 4, "process iterator yields header and records")
assert(seen[1].kind == "header" and seen[1].magic == "LLPV", "ctx. header yields flattened event")
assert(seen[1].seq == 1 and seen[2].seq == 2, "process events carry stable seq")
assert(seen[2].kind == "record" and seen[2].offset == 5, "ctx. record yields record event")

local h = records:start("LLPVx")
assert(h:status() == "ready", "handle starts ready")
assert(h:resume().kind == "header", "handle resumes first event")
assert(h:resume().kind == "record", "handle resumes second event")
assert(h:resume() == nil and h:done(), "handle finishes after events")
assert(h:result().bytes == 5, "handle stores result")

local budgeted = records:start("LLPVxyz", llb.process_opts { budget = 1 })
assert(budgeted:resume().kind == "header", "budgeted process first event")
assert(budgeted:resume().kind == "budget_exhausted", "budget exhaustion is an event")
assert(budgeted:resume { budget = 10 }.kind == "record", "resume can refresh budget")

local checked = llb.process. checked (function(ctx)
  ctx. warning {
    code = "W_TEST",
    message = "warning event",
  }
  ctx. error {
    code = "E_TEST",
    message = "error event",
  }
  return true
end)
local ch = checked:start()
local w = ch:resume()
local e = ch:resume()
assert(w.kind == "diagnostic" and w.severity == "warning", "ctx. warning yields diagnostic event")
assert(e.kind == "diagnostic" and e.severity == "error", "ctx. error yields diagnostic event")
assert(#ch.diagnostics.items == 2, "diagnostics are collected on handle")

local desc = llb.describe_process("records")
assert(desc and desc.name == "records", "process registered for introspection")

local moon = require("moonlift")
local env = {}
moon.use { scope = "env", target = env, global = false, searcher = false }
assert(env.process == llb.process, "Moonlift DSL env exposes process")
assert(moon.source, "Moonlift exposes source process")

local source_events = {}
for ev in moon.source([[return fn. add { a [i32], b [i32] } [i32] { ret (a) }]], "process-source.lua", { eval = true }) do
  source_events[#source_events + 1] = ev
end
assert(source_events[1].kind == "load", "source process emits load")
assert(source_events[2].kind == "index", "source process emits index")
assert(source_events[3].kind == "eval", "source process emits eval")

print("llb process ok")
