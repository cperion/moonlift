MOONLIFT  = target/release/moonlift
MOM       = target/release/mom
LUAJIT    = .vendor/LuaJIT/src
MOM_OBJ   = target/libmom_precompiled.o
MOONLIB   = target/release/libmoonlift.so

.PHONY: all clean mom-obj mom-tags test-mom

all: $(MOONLIFT) $(MOM)

$(LUAJIT)/libluajit.a:
	$(MAKE) -C $(LUAJIT) CFLAGS="-fPIC"
	ln -sf libluajit.a $(LUAJIT)/libluajit-5.1.a

$(MOONLIFT): $(LUAJIT)/libluajit.a
	LUAJIT_LIB=$(CURDIR)/$(LUAJIT)/libluajit-5.1.a \
	LUAJIT_INCLUDE=$(CURDIR)/$(LUAJIT) \
	cargo build --release --bin moonlift

mom-tags: $(MOONLIFT)
	$(MOONLIFT) scripts/generate_mom_tags.lua

$(MOONLIB): $(LUAJIT)/libluajit.a
	LUAJIT_LIB=$(CURDIR)/$(LUAJIT)/libluajit-5.1.a \
	LUAJIT_INCLUDE=$(CURDIR)/$(LUAJIT) \
	cargo build --release --lib

$(MOM_OBJ): $(MOONLIFT) $(MOONLIB) mom-tags
	@mkdir -p target
	MOM_OBJ_PATH=$(MOM_OBJ) $(MOONLIFT) scripts/emit_mom_precompiled.lua

mom-obj: $(MOM_OBJ)

$(MOM): $(LUAJIT)/libluajit.a $(MOM_OBJ)
	LUAJIT_LIB=$(CURDIR)/$(LUAJIT)/libluajit-5.1.a \
	LUAJIT_INCLUDE=$(CURDIR)/$(LUAJIT) \
	MOM_OBJ_PATH=$(CURDIR)/$(MOM_OBJ) \
	cargo build --release --bin mom

clean:
	$(MAKE) -C $(LUAJIT) clean
	cargo clean
	rm -f $(LUAJIT)/libluajit-5.1.a src/embedded_hosted_lua.rs $(MOM_OBJ)

test-mom: $(MOM)
	luajit tests/test_mom_cli.lua

run:
	$(MOONLIFT) $(FILE)

bench:
	luajit benchmarks/bench_json_stack_decode.lua
