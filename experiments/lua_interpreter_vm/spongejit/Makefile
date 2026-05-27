# SponJIT Foundry — Makefile
#
# Targets:
#   make stencils    Build stencil library (GCC → .o → stencil_library.json)
#   make foundry     Run the foundry (stencils + corpus + SSA + lowering)
#   make puc-build   Build vanilla + SponJIT-patched PUC Lua from tracked sources
#   make puc-bench   Run whole-program PUC vs SponJIT comparison
#   make clean       Remove build artifacts

SPONGEJIT := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
SPONGEJIT := $(SPONGEJIT:%/=%)
ROOT := $(SPONGEJIT)/../..

STENCILS_C   := $(SPONGEJIT)/stencils/stencils.c
STENCILS_OUT := $(SPONGEJIT)/build/stencil_library.json
# PUC-compatible stencil variant (same GCC, PUC-native ABI)
STENCILS_PUC_C   := $(SPONGEJIT)/stencils/stencils_puc.c
STENCILS_PUC_OUT := $(SPONGEJIT)/build/stencil_library_puc.json
EXTRACT      := $(SPONGEJIT)/stencils/extract.lua
FOUNDRY      := $(SPONGEJIT)/foundry.lua
LUA          := luajit

.PHONY: all stencils stencils-puc foundry runtime-test puc-build puc-bench clean

all: stencils foundry

stencils-puc: $(STENCILS_PUC_OUT)

stencils: $(STENCILS_OUT)

$(STENCILS_OUT): $(STENCILS_C) $(EXTRACT)
	mkdir -p $(SPONGEJIT)/build
	cd $(SPONGEJIT) && $(LUA) -e 'package.path="src/?.lua;src/?/init.lua;"..package.path' $(EXTRACT) stencils/stencils.c build/stencil_library.json

$(STENCILS_PUC_OUT): $(STENCILS_PUC_C) $(EXTRACT)
	mkdir -p $(SPONGEJIT)/build
	cd $(SPONGEJIT) && $(LUA) -e 'package.path="src/?.lua;src/?/init.lua;"..package.path' $(EXTRACT) stencils/stencils_puc.c build/stencil_library_puc.json

foundry: $(STENCILS_OUT)
	cd $(SPONGEJIT) && $(LUA) -e 'package.path="src/?.lua;src/?/init.lua;"..package.path' $(FOUNDRY) $(FOUNDRY_ARGS)

runtime-test: $(STENCILS_OUT)
	cd $(SPONGEJIT) && LUA_PATH='runtime/?.lua;src/?.lua;src/?/init.lua;;' $(LUA) runtime/materialize.lua build/stencil_library.json

puc-build:
	cd $(ROOT) && $(LUA) $(SPONGEJIT)/puc/build_sponjit_puc.lua

puc-bench: puc-build
	cd $(ROOT) && $(LUA) $(SPONGEJIT)/puc/bench_compare.lua --reps $${REPS:-5} -- $(SPONGEJIT)/bench/programs/int_loop.lua $${N:-100000000}

clean:
	rm -rf $(SPONGEJIT)/build
	mkdir -p $(SPONGEJIT)/build
