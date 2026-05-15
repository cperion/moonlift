MOONLIFT  = target/release/moonlift
MOM       = target/release/mom
LUAJIT    = .vendor/LuaJIT/src

.PHONY: all clean

all: $(MOONLIFT) $(MOM)

$(LUAJIT)/libluajit.a:
	$(MAKE) -C $(LUAJIT) CFLAGS="-fPIC"
	ln -sf libluajit.a $(LUAJIT)/libluajit-5.1.a

$(MOONLIFT) $(MOM): $(LUAJIT)/libluajit.a
	LUAJIT_LIB=$(CURDIR)/$(LUAJIT)/libluajit-5.1.a \
	LUAJIT_INCLUDE=$(CURDIR)/$(LUAJIT) \
	cargo build --release --bin moonlift --bin mom

clean:
	$(MAKE) -C $(LUAJIT) clean
	cargo clean
	rm -f $(LUAJIT)/libluajit-5.1.a src/embedded_lua.rs

run:
	$(MOONLIFT) $(FILE)

bench:
	luajit benchmarks/bench_json_stack_decode.lua
