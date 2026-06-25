LUAJIT    = .vendor/LuaJIT/src
TINYCC    = deps/tinycc
TCC_PREFIX = $(CURDIR)/$(TINYCC)/.local
LIBTCC    = $(TINYCC)/.local/lib/libtcc.so
LALIN_BIN_DIR = target/lalin_binary
LALIN_BIN = target/lalin
LALIN_BC_BANK_C = $(LALIN_BIN_DIR)/lalin_embedded_bc_bank.c
LALIN_BC_BANK_H = $(LALIN_BIN_DIR)/lalin_embedded_bc_bank.h
LALIN_MC_BANK_C = $(LALIN_BIN_DIR)/lalin_embedded_mc_bank.c
LALIN_MC_BANK_H = $(LALIN_BIN_DIR)/lalin_embedded_mc_bank.h

.PHONY: all luajit lalin-bin clean bench libtcc

all: luajit
luajit: $(LUAJIT)/libluajit.a

$(LUAJIT)/libluajit.a:
	$(MAKE) -C $(LUAJIT) CFLAGS="-fPIC"
	ln -sf libluajit.a $(LUAJIT)/libluajit-5.1.a

lalin-bin: $(LALIN_BIN)

$(LALIN_BC_BANK_C) $(LALIN_BC_BANK_H): $(shell find lua -name '*.lua' | sort) tools/gen_lalin_module_bank.lua
	luajit tools/gen_lalin_module_bank.lua $(LALIN_BC_BANK_C) $(LALIN_BC_BANK_H) lua

$(LALIN_MC_BANK_C) $(LALIN_MC_BANK_H): $(shell find lua -name '*.lua' | sort) tools/gen_lalin_mc_bank.lua
	luajit tools/gen_lalin_mc_bank.lua $(LALIN_MC_BANK_C) $(LALIN_MC_BANK_H)

$(LALIN_BIN): src/lalin.c $(LALIN_BC_BANK_C) $(LALIN_BC_BANK_H) $(LALIN_MC_BANK_C) $(LALIN_MC_BANK_H) $(LUAJIT)/libluajit.a
	$(CC) -O2 -I$(LUAJIT) -I$(LALIN_BIN_DIR) src/lalin.c $(LALIN_BC_BANK_C) $(LALIN_MC_BANK_C) $(LUAJIT)/libluajit.a -lm -ldl -pthread -o $(LALIN_BIN)

libtcc: $(LIBTCC)

$(LIBTCC): $(TINYCC)/configure
	cd $(TINYCC) && ./configure --prefix="$(TCC_PREFIX)" --disable-static
	$(MAKE) -C $(TINYCC) libtcc.so libtcc1.a tcc
	$(MAKE) -C $(TINYCC) install

clean:
	$(MAKE) -C $(LUAJIT) clean
	rm -f $(LUAJIT)/libluajit-5.1.a
	rm -rf $(LALIN_BIN_DIR) $(LALIN_BIN)

bench:
	luajit benchmarks/bench_json_stack_decode.lua
