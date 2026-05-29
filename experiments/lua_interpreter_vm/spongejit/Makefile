# SponJIT bank pipeline
#
# Current build path:
#   make stencils  -> build/cp_lib/stencils.o + stencil_library.json
#   make bank      -> build/cp_lib/libsponbank.so
#   make puc-build -> patched PUC Lua linked against libsponbank.so

SPONGEJIT := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
SPONGEJIT := $(SPONGEJIT:%/=%)
ROOT := $(SPONGEJIT)/../..
LUA := luajit

.PHONY: all pipeline stencils bank puc-build puc-bench clean

all: pipeline

pipeline:
	cd $(SPONGEJIT) && ./build_pipeline.sh

stencils:
	cd $(SPONGEJIT) && ./build_stencils.sh

bank: stencils
	cd $(SPONGEJIT) && ./build_bank.sh

puc-build: bank
	cd $(ROOT) && $(LUA) $(SPONGEJIT)/puc/build_puc_sponjit.lua

puc-bench: puc-build
	cd $(ROOT) && $(LUA) $(SPONGEJIT)/puc/bench_sponbank_puc.lua $${PUC_BENCH_ARGS:-}

clean:
	rm -rf $(SPONGEJIT)/build
	mkdir -p $(SPONGEJIT)/build/cp_lib
