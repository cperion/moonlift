# LLPVM Implementation Notes

These are observed compiler/backend constraints and current implementation
quirks. They are not philosophy.

## C Emission Surfaces

Use the executed-module artifact path for LLPVM:

```lua
lalin.emit_c_file_artifact("lua/llpvm/native/llpvm_abi.mlua", {
    name = "llpvm",
    combined_path = "llpvm_amalgam.c",
    h_path = "llpvm_amalgam.h",
})
lalin.bundle_file("lua/llpvm/native/llpvm_abi.mlua", "llpvm"):emit_c_artifact()
```

Do not create ad hoc source-string C APIs for LLPVM modules. LLPVM uses
`lalin.require`, so C emission must execute the module and return a full artifact
with generated source, generated header, explicit support source, and combined
translation unit.

## Fragment References

Cross-module region composition should use explicit fragment splices:

```lalin
emit @{Mem.llpvm_grow_elems}(...; grown = ok, oom = bad)
```

Self-recursive region use cannot splice itself before the value exists. Use
`call` as the recursion boundary:

```lalin
call ll_next_op(vm, tape; op = got, done = done, blocked = blocked, failed = failed)
```

## Views

Views are source-level descriptors, not ordinary structs. Use:

```lalin
len(v)
v[i]
```

Do not use:

```lalin
v.len
v.data
```

When raw pointer access is required, pass a `ptr(T)` separately or store it in a
real product.

## Handles

Handle representation is opaque in safe casts. Use:

```lalin
Handle.from_repr(raw)
repr(handle)
```

only in trusted store code. Do not use `as(Handle, raw)`.

## C Close Boundary

`llpvm_close(llpvm_vm_ref)` is a C ABI boundary. It currently lowers through
`ll_vm_close(vm: LlVmRef; ...)`, not `owned LlVmRef`, because C cannot express
Lalin's `owned` wrapper in its function signature.

The internal owned protocol still needs a separate preserving form:

```lalin
region ll_vm_close_owned(vm: owned LlVmRef;
    closed
  | live_leases(vm: owned LlVmRef, count: index)
  | live_recordings(vm: owned LlVmRef, count: index))
end
```

Do not inspect an `owned LlVmRef` as plain data. The failed C emission caught
that correctly.

## Current Memory Support Quirk

`llpvm_memory.mlua` and the support source embedded by `llpvm.native.build_c`
currently use bootstrap extern pins:

```text
default_malloc/default_realloc/default_free
llpvm_vm_register/llpvm_vm_get/llpvm_vm_unregister
```

This is not the final memory architecture. The correct design is a named
`LlRuntimeSupport` ABI/product that owns allocator callbacks, handle table
capacity, generation policy, thread model, and failure behavior.
