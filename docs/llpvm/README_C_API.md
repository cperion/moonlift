# LLPVM C API

The C side is intentionally one generated include:

```c
#include "llpvm_amalgam.h"
```

Generate the combined blob and header with the artifact API:

```lua
local build = require "llpvm.native.build_c"
build.write_artifact("llpvm_amalgam.c", { h_path = "llpvm_amalgam.h" })
```

or directly:

```lua
local lalin = require "lalin"
lalin.emit_c_file_artifact("lua/llpvm/native/llpvm_abi.mlua", {
    name = "llpvm",
    combined_path = "llpvm_amalgam.c",
    h_path = "llpvm_amalgam.h",
    support_source = "... platform/runtime support C ...",
})
```

The support source is explicit artifact input. The default LLPVM builder embeds
the current extern pin layer used by the emitted Lalin code:

```text
default_malloc/default_realloc/default_free
llpvm_vm_register/llpvm_vm_get/llpvm_vm_unregister
```

Applications normally call only:

```c
llpvm_status llpvm_open(const llpvm_config *config, llpvm_vm_ref *out);
llpvm_status llpvm_close(llpvm_vm_ref vm);
llpvm_status llpvm_load_program(llpvm_vm_ref vm, const void *bytes,
                                size_t len, llpvm_tape_ref *out_root);
llpvm_status llpvm_apply_phase(llpvm_vm_ref vm, llpvm_phase_ref phase,
                               llpvm_tape_ref input, llpvm_args_ref args,
                               llpvm_tape_ref *out);
llpvm_status llpvm_drain(llpvm_vm_ref vm, llpvm_tape_ref tape,
                         llpvm_buffer_ref *out);
llpvm_status llpvm_report(llpvm_vm_ref vm, llpvm_vm_report *out);
```

No durable pointer identity crosses the API. Handles are opaque `uint32_t`
values and stale VM handles are rejected by the support table.

`llpvm_load_program` creates a VM view over caller-owned immutable image bytes.
Those bytes must outlive all program tapes derived from them. If a caller
needs copied ownership, it allocates/copies before calling this API and owns
that allocation.

Known C-emission constraints:

- Use `lalin.emit_c_file_artifact(...)` or
  `lalin.bundle_file(...):emit_c_artifact(...)` for LLPVM `.mlua` modules.
- Region fragments emitted across files should use `emit @{Module.region}(...)`
  so bundle lowering sees the fragment value.
- Self-recursive region use must use `call region_name(...)` as a recursion
  boundary; a region cannot splice itself before its value exists.
- View values use `len(v)` and `v[i]` in Lalin source. They are not source
  structs with `.len` or `.data` fields.
- Handle construction from raw integers must use `Handle.from_repr(raw)` inside
  trusted store code. Ordinary `as(Handle, raw)` is rejected by design.
