# Lalin JSON Showcase

`json_lua_stack_decoder.mlua` is the live JSON library showcase.

It demonstrates the intended architecture:

- Lua owns policy and the ergonomic API.
- Lalin owns strict byte-level JSON parsing.
- Lalin constructs a typed value-event tape before Lua projection.
- The generated C blob has no Lua C API dependency.
- The same kernels produce a full C backend blob through `bundle:c_source`.
- Runtime loading prefers a GCC `-O3` shared artifact and falls back to libtcc.
- The exposed C API is caller-buffer based and suitable for `emcc`.
- Browser/WASM consumers can view the output buffers as `Int32Array`,
  `Float64Array`, and `Uint8Array` without constructing JS objects first.

Run it:

```sh
luajit run_mlua.lua examples/json/json_lua_stack_decoder.mlua
```

Use it from Lua:

```lua
local Json = require("lalin.mlua_run").dofile("examples/json/json_lua_stack_decoder.mlua")

local doc = Json.decode([[{"xs":[1,true,null],"empty":{}}]])
assert(doc.xs[3] == Json.null)

local c_path = Json.write_c("target/lalin_json_showcase.c")
local h_path = Json.write_header("target/lalin_json_showcase.h")
```

Compile for the browser with Emscripten by exporting `json_decode_value_events`;
`Json.emcc_args` contains the intended export flags and `Json.c_api.typed_arrays`
names the JS typed-array views for every buffer. The `.mlua` file is the
canonical library-shaped example.
