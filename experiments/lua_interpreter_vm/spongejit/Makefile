# SponJIT LuaCompile foundry foundation
#
# Maintained offline foundry artifacts are MoonCFG + LuaContract +
# Stencil.VariantKey representatives. The old SSA/stencil/sponbank path is
# quarantined historical material and is not a maintained build/test path.

SPONGEJIT := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
SPONGEJIT := $(SPONGEJIT:%/=%)
ROOT := $(SPONGEJIT)/../..
LUA := luajit
LUAROCKS_ENV := eval "$$(luarocks --lua-version=5.1 path 2>/dev/null || luarocks path)" &&

.PHONY: all test test-completion test-lua-compile \
	test-lua-compile-foundry test-lua-compile-corpus100 \
	no-old-imports lua-compile-foundry stencils bank test-bank test-c-interp probe \
	play-bytecode bench-l1-fusion bench-puc-span bench-function clean

all: test

# Main test is the current honest implemented-slice gate.
# Completion/corpus gates are opt-in targets.
test: test-lua-compile test-lua-compile-foundry no-old-imports

test-completion:
	cd $(ROOT)/.. && $(LUAROCKS_ENV) $(LUA) experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_completion.lua

lua-compile-foundry:
	cd $(SPONGEJIT) && ./build_lua_compile_foundry.sh

stencils:
	@printf '%s\n' 'ERROR: stencils belongs to the retired old Copy-Link-Patch ABI target name.' >&2
	@printf '%s\n' 'Use: make lua-compile-foundry for ASDL Stencil.VariantKey artifacts.' >&2
	@exit 2

test-lua-compile:
	cd $(ROOT)/.. && { set -e; for t in experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_*.lua; do case "$$t" in *corpus100.lua|*completion.lua) continue;; esac; $(LUAROCKS_ENV) $(LUA) "$$t"; done; }

test-lua-compile-foundry:
	cd $(ROOT)/.. && $(LUAROCKS_ENV) $(LUA) experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_foundry.lua

test-lua-compile-corpus100:
	cd $(SPONGEJIT) && eval "$$(luarocks --lua-version=5.1 path 2>/dev/null || luarocks path)" && $(LUA) foundry.lua --corpus-mode --max-files 20 --max-windows 120 --max-arity 2 --max-fact-combos 32 --out build/lua_compile_corpus100
	cd $(ROOT)/.. && $(LUAROCKS_ENV) LUA_COMPILE_CORPUS_REQUIRED=1 LUA_COMPILE_CORPUS_ARTIFACT=experiments/lua_interpreter_vm/spongejit/build/lua_compile_corpus100/lua_compile_representatives.json LUA_COMPILE_CORPUS_MIN_WINDOWS=100 $(LUA) experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_corpus100.lua

no-old-imports:
	cd $(ROOT)/.. && ! rg -n "require\\(['\"]src\\.(ssa|ssa_ir|ssa_lift|ssa_opt|ssa_atoms|ssa_validate|ssa_fact_axes|ssa_contract|ssa_to_stencil|stencil_|dedupe_normal_forms|build_bank|materialize_native_x64|enumerate|grammar_enum|facts|fact_signature|opcode_coverage)" experiments/lua_interpreter_vm/spongejit/lua_compile experiments/lua_interpreter_vm/spongejit/foundry.lua experiments/lua_interpreter_vm/spongejit/src/worker_compile.lua experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_*.lua
	cd $(ROOT)/.. && ! rg -n "SponDesc|SponStencil|SponTile|sponbank|stencil_desc|materialize_native_x64|OpcodeHelper|HelperCall|copy_link_patch|CopyLinkPatch|SponBank|SponMaterializer" experiments/lua_interpreter_vm/spongejit/lua_compile experiments/lua_interpreter_vm/spongejit/foundry.lua experiments/lua_interpreter_vm/spongejit/src/worker_compile.lua experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_*.lua

# Retired old-runtime targets. They intentionally fail instead of silently
# rebuilding quarantined descriptor/bank/materializer artifacts.
bank test-bank test-c-interp probe play-bytecode bench-l1-fusion bench-puc-span bench-function:
	@printf '%s\n' 'ERROR: $@ belongs to the retired SSA/stencil/sponbank runtime path.' >&2
	@printf '%s\n' 'Use: make test, make lua-compile-foundry, or make test-lua-compile-corpus100.' >&2
	@exit 2

clean:
	rm -rf $(SPONGEJIT)/build
