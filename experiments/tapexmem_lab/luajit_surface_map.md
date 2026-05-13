# LuaJIT surface map for Moonlift VM design

Goal: keep design surface to two forests.

1. **Struct forest** (memory + ABI layout)
2. **Protocol forest** (region signatures / continuation contracts)

This map anchors those forests to real LuaJIT code under `.vendor/LuaJIT/src`.

## Evidence that VM is broader than tracing/JIT

- Core object model and thread/global state:
  - `lj_obj.h` (`TValue`, GC object kinds, `GCproto`, `GCfunc`, `GCtab`, `global_State`, `lua_State`)
- Dispatch and hotcount machine:
  - `lj_dispatch.c`, `lj_dispatch.h`
  - VM hotloop macros in `vm_x86.dasc` (`hotloop`, `vm_hotloop`)
- Trace machine:
  - `lj_trace.c` (`LJ_TRACE_START/RECORD/END/ASM/ERR` state machine)
- Recorder and in-flight optimization:
  - `lj_record.c` + `lj_iropt.h` (fold/CSE while recording)
- Snapshots and deopt:
  - `lj_snap.c`, `lj_trace.c` (`lj_trace_exit`)
- Assembler/regalloc/patch:
  - `lj_asm.c`
- GC and write barriers (+ JIT interaction):
  - `lj_gc.c`, `lj_gc.h` (`lj_gc_step_jit`, barriers, trace marking)
- Metamethod subsystem:
  - `lj_meta.h`
- Parser/lexer frontend:
  - `lj_lex.h`, `lj_parse.h`
- FFI type system/cdata/calls:
  - `lj_ctype.h`, `lj_cdata.h`, `lj_ccall.h`
- VM event/hook surface:
  - `lj_vmevent.h`, dispatch/hook paths in `lj_dispatch.c`

## Forest interpretation

### A) Struct forest packages

- **Value/Object package**: TValue, GC headers, string/table/func/proto/upval/thread.
- **Execution package**: frame/stack/thread/global state, dispatch/hotcount tables.
- **JIT package**: jit state, trace store, IR, snapshots, exits, mcode metadata.
- **GC package**: gc phase/debt/threshold, gray/sweep queues, barriers.
- **Frontend package**: lex/parse state, proto build metadata.
- **FFI package**: CType table/state, CData objects, callback/call ABI metadata.
- **Observability package**: hook masks, VM events, profiler counters.

### B) Protocol forest packages

- **Top VM protocol**: step/halt.
- **Dispatch protocol**: interp/record/hook/profile transitions.
- **Call/return protocol**: Lua/C/FF call edges and yields/errors.
- **Metamethod protocol**: lookup/cache/call/fallback/error.
- **GC protocol**: propagate/sweep/finalize/pause + barrier edges.
- **Trace protocol**: root/side start, record, end, asm, abort.
- **Recording protocol**: decode/observe/fold/emit/snapshot/stop.
- **Compile protocol**: RA/emit/patch/stub/install.
- **Native/exit protocol**: enter/run/decode-exit/restore/side-trigger.
- **FFI protocol**: ctype parse, cdata alloc, ccall/callback, conversion errors.
- **Frontend protocol**: parse/load success/error.
- **Event protocol**: BC/TRACE/RECORD/TEXIT hook/event emissions.

## Lab artifact

- `vm_surface_forests_only.mlua` encodes this full two-forest surface as Moonlift declarations.
- `five_mode_machine_regular.mlua` is a runnable subset showing iterator + split submachines.

Use this as the controlling design contract before filling implementation details.
