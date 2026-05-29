# SpongeJIT PUC integration status

The legacy PUC benchmark and C-function tile materialization paths were removed
with the unified native-fragment ABI hard-yank. Maintained SpongeJIT artifacts
are abstract native-fragment metadata descriptors produced by `src/worker_compile.lua`.

There is intentionally no PUC executable integration in this directory until the
native fragment linker exists and consumes `SponFragmentDesc`, `SponDataReloc`,
`SponControlReloc`, endpoint locations, clobbers, and projection entries directly.
Do not resurrect the removed tile-era local ABI declarations or stale bank
benchmarks.
