# SponJIT native-fragment foundation
#
# The legacy C-function stencil/tile bank pipeline has been removed. Maintained
# build artifacts are abstract native-fragment metadata emitted by src/worker_compile.lua
# from pre-split grammar chunks.

SPONGEJIT := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
SPONGEJIT := $(SPONGEJIT:%/=%)
ROOT := $(SPONGEJIT)/../..
LUA := luajit

.PHONY: all test clean

all: test

test:
	cd $(ROOT)/.. && $(LUA) experiments/lua_interpreter_vm/tests/test_spongejit_real_ssa.lua
	cd $(ROOT)/.. && $(LUA) experiments/lua_interpreter_vm/tests/test_spongejit_fragment_ir.lua
	cd $(ROOT)/.. && $(LUA) experiments/lua_interpreter_vm/tests/test_spongejit_fragment_projection.lua
	cd $(ROOT)/.. && $(LUA) experiments/lua_interpreter_vm/tests/test_spongejit_stencil_to_fragment.lua
	cd $(ROOT)/.. && $(LUA) experiments/lua_interpreter_vm/tests/test_spongejit_retirement.lua

clean:
	rm -rf $(SPONGEJIT)/build
