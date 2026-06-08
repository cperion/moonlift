# Moonlift C backend examples

These examples show the user-facing path:

```text
Moonlift source -> moon.emit_c -> TCC/cc -> executable -> run
```

Run all examples from the repository root:

```sh
luajit examples/c_backend/run_examples.lua
```

The runner covers return codes, arithmetic, pointer/view processing, structs,
extern calls, function pointers, and tagged unions. It prints the exact compiler
mode used for each example.

## Fast TCC loop

By default the runner chooses:

1. `MOONLIFT_C_CC` when set,
2. `tcc` when installed,
3. `cc`, `gcc`, then `clang` as fallbacks.

Useful commands:

```sh
MOONLIFT_C_CC=tcc luajit examples/c_backend/run_examples.lua
MOONLIFT_C_CC=cc  luajit examples/c_backend/run_examples.lua
```

For optional in-memory libtcc execution, install libtcc and run:

```sh
MOONLIFT_C_USE_LIBTCC=1 luajit examples/c_backend/run_examples.lua
```

If libtcc is not available, `MOONLIFT_C_USE_LIBTCC=1` prints a skip diagnostic
and falls back to the subprocess compiler path. Tests use the same environment
knobs (`MOONLIFT_C_CC`, `MOONLIFT_C_USE_LIBTCC`, and optional `MOONLIFT_LIBTCC`).
