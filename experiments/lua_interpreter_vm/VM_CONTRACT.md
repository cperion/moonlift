# Lalin Lua VM Contract / ABI

This document records the pre-SponJIT contract for the Lalin-native Lua 5.5 VM. It is an architectural gate: SponJIT must consume this contract only after the VM validator, frame/cache rules, native boundary, allocator boundary, and error/yield protocols are implemented and tested.

## Scope

- The VM targets Lua 5.5 semantics in Lalin-native data/control structures.
- PUC Lua is a semantic reference only. PUC layouts, `longjmp`, C-stack behavior, allocator conventions, and internal bytecode/runtime shapes MUST NOT be treated as implementation dependencies.
- Scratch-memory FFI tests are test fixtures only. They are not the stable host ABI.
- SponJIT remains separate and MUST NOT optimize or depend on scaffolding behavior.

## Internal ABI

The internal ABI is the typed product/control contract used by VM regions:

- `Value` MUST remain the canonical tagged value representation.
- `Proto` MUST describe validated bytecode and immutable prototype metadata.
- `Frame` MUST carry explicit call/return metadata, including `result_base`, `call_top`, `resume_mode`, and yieldability flags.
- `LuaThread` MUST carry explicit coroutine/error state, including status, protected-frame head, error value, yieldability counters, and last error code.
- `GlobalState` MUST own VM-wide runtime state and ABI version fields.

Internal pointers carry no implicit nullability or lifetime guarantees. Every non-null/lifetime assumption MUST be enforced by construction, validation, or explicit checks at the boundary where it matters.

## Host ABI

Host-visible access is through sealed API functions only. Host callers MUST NOT rely on internal struct allocation conventions beyond documented ABI fields and version checks. Any host operation that may allocate, call Lua/native code, yield, or error MUST expose that outcome explicitly; it MUST NOT hide VM control flow in a C return convention.

## Native ABI

Native Lua-callable functions use a Lalin-owned ABI contract:

- Native descriptors MUST carry an ABI version.
- Native execution MUST expose normal return, Lua error, yield, OOM, and stack-growth outcomes explicitly.
- Native functions MUST NOT use host exceptions, PUC-style `longjmp`, hidden scheduler behavior, or raw allocator side channels as VM semantics.
- Until native invocation is implemented, native-call paths MUST fail loudly with explicit error state.

## Bytecode Validation Contract

`validate_proto` is the trust boundary for the interpreter and any future JIT.

The validator MUST enforce every assumption used by dispatch and opcode handlers, including:

- opcode range
- register bounds
- constant and child-prototype bounds
- jump target bounds
- paired-instruction invariants such as `LOADKX`/`EXTRAARG` and arithmetic/`MMBIN*`
- call/return register windows
- loop register windows

A JIT MUST NOT consume bytecode accepted only by ad-hoc test fixtures.

## Frame and Cache Invariant

The VM loop may cache `code` and `constants` for the current frame. Whenever the current `Frame*` changes, cached prototype-derived pointers MUST be reloaded from that frame's closure. Cached pointers from a child frame MUST NOT be used to resume a parent.

## Call and Return Invariant

Call result placement is explicit:

- A call's destination is `Frame.result_base` (the caller's `base + A` or preserved tailcall destination).
- Return adjustment MUST NOT substitute `parent.base` for the call result base.
- Child-frame return metadata owns the return-mode payload; parent-frame state owns resumed execution.

## Error and Protected-Unwind Invariant

Opcode/runtime errors MUST flow through explicit error-object/protected-unwind machinery before reaching the outer VM error continuation. The VM MUST preserve `LuaThread.err_value` and `LuaThread.last_error_code` on error. Protected calls and to-be-closed variables MUST NOT depend on host stack unwinding.

## Coroutine and Yield Invariant

Yieldability is VM data, not hidden control flow. Every yieldable path (Lua call, native call, metamethod, iterator, `__close`, protected call) MUST carry enough explicit saved state to resume or reject the yield deterministically.

## Allocator and Extern Boundary

Allocation is VM semantics. Allocation paths MUST use an explicit allocator protocol with `ok`, `step_required`, and `oom` outcomes. The VM MUST NOT embed raw libc/malloc behavior or treat null pointer returns as the only error channel. GC barriers and lifetime ownership are part of the VM contract.

## SponJIT Gate

SponJIT integration is not allowed until these gates are tested:

1. bytecode validator is complete for interpreter/JIT assumptions;
2. frame-cache reload on frame switch is verified;
3. explicit call result base is verified;
4. unified error/protected-unwind path is verified;
5. explicit native ABI boundary is versioned and fail-loud;
6. allocator boundary is explicit and does not hide libc behavior.
