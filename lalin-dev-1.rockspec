rockspec_format = "3.0"
package = "lalin"
version = "0.1.0-1"

source = {
    url = "git+https://github.com/cperion/lalin.git",
    tag = "v0.1.0",
}

description = {
    summary = "Typed, jump-first compiled language authored through a Lua-owned DSL.",
    detailed = [[
Lalin is a typed, jump-first compiled language embedded in LuaJIT
with a LuaTrace backend materialized as LuaJIT bytecode copy-patch. Lua is the
metaprogramming layer; Lalin is the monomorphic output.

Author in the Lua-owned DSL: Lua parses products, protocols, bodies,
and fill maps as table values; the standard LLB substrate hosts staged heads,
fragments, formatting, managed use sessions, and fragment algebra; Lalin
normalizes into typed ASDL and lowers to LuaJIT bytecode-backed stencil modules.
No source parser, no textual antiquote, no string quotes.
    ]],
    license = "MIT",
    homepage = "https://github.com/cperion/lalin",
    maintainer = "Lalin contributors",
}

dependencies = {
    "lua >= 5.1",
}

build = {
    type = "command",

    build_command = "make",

    install_command = [[
        mkdir -p "$(PREFIX)/bin"
        mkdir -p "$(PREFIX)/share/lua/$(LUA_VERSION)"
        cp scripts/lalinfmt.lua "$(PREFIX)/bin/lalinfmt"
        cp lua/llb.lua "$(PREFIX)/share/lua/$(LUA_VERSION)/"
        cp -r lua/lalin "$(PREFIX)/share/lua/$(LUA_VERSION)/"
        cp -r lua/llpvm "$(PREFIX)/share/lua/$(LUA_VERSION)/"
    ]],
}
