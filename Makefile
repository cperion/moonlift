MOONLIFT  = target/release/moonlift
LUAJIT    = .vendor/LuaJIT/src

.PHONY: all clean

all: $(MOONLIFT)

$(LUAJIT)/libluajit.a:
	$(MAKE) -C $(LUAJIT) CFLAGS="-fPIC"
	ln -sf libluajit.a $(LUAJIT)/libluajit-5.1.a

$(MOONLIFT): $(LUAJIT)/libluajit.a
	LUAJIT_LIB=$(CURDIR)/$(LUAJIT)/libluajit-5.1.a \
	LUAJIT_INCLUDE=$(CURDIR)/$(LUAJIT) \
	cargo build --release --bin moonlift

clean:
	$(MAKE) -C $(LUAJIT) clean
	cargo clean
	rm -f $(LUAJIT)/libluajit-5.1.a src/embedded_lua.rs

run:
	$(MOONLIFT) $(FILE)

bench:
	$(MOONLIFT) benchmarks/bench_json_hosted_decode.mlua
