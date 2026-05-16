MOONLIFT  = target/release/moonlift
MOM       = target/release/mom
LUAJIT    = .vendor/LuaJIT/src
MOM_OBJ   = target/libmom_precompiled.o

.PHONY: all clean mom-obj

all: $(MOONLIFT) $(MOM)

$(LUAJIT)/libluajit.a:
	$(MAKE) -C $(LUAJIT) CFLAGS="-fPIC"
	ln -sf libluajit.a $(LUAJIT)/libluajit-5.1.a

$(MOONLIFT): $(LUAJIT)/libluajit.a
	LUAJIT_LIB=$(CURDIR)/$(LUAJIT)/libluajit-5.1.a \
	LUAJIT_INCLUDE=$(CURDIR)/$(LUAJIT) \
	cargo build --release --bin moonlift

$(MOM_OBJ): $(MOONLIFT)
	@mkdir -p target
	MOM_OBJ_PATH=$(MOM_OBJ) $(MOONLIFT) scripts/emit_mom_precompiled.lua

mom-obj: $(MOM_OBJ)

$(MOM): $(LUAJIT)/libluajit.a
	LUAJIT_LIB=$(CURDIR)/$(LUAJIT)/libluajit-5.1.a \
	LUAJIT_INCLUDE=$(CURDIR)/$(LUAJIT) \
	cargo build --release --bin mom

clean:
	$(MAKE) -C $(LUAJIT) clean
	cargo clean
	rm -f $(LUAJIT)/libluajit-5.1.a src/embedded_lua.rs $(MOM_OBJ)

run:
	$(MOONLIFT) $(FILE)

bench:
	luajit benchmarks/bench_json_stack_decode.lua
