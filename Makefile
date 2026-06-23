MOONLIFT  = target/release/moonlift
LUAJIT    = .vendor/LuaJIT/src
MOONLIB   = target/release/libmoonlift.so
TINYCC    = deps/tinycc
TCC_PREFIX = $(CURDIR)/$(TINYCC)/.local
LIBTCC    = $(TINYCC)/.local/lib/libtcc.so

.PHONY: all lib clean bench libtcc

all: lib
lib: $(MOONLIB)

$(LUAJIT)/libluajit.a:
	$(MAKE) -C $(LUAJIT) CFLAGS="-fPIC"
	ln -sf libluajit.a $(LUAJIT)/libluajit-5.1.a

$(MOONLIB):
	cargo build --release --lib

libtcc: $(LIBTCC)

$(LIBTCC): $(TINYCC)/configure
	cd $(TINYCC) && ./configure --prefix="$(TCC_PREFIX)" --disable-static
	$(MAKE) -C $(TINYCC) libtcc.so libtcc1.a tcc
	$(MAKE) -C $(TINYCC) install

clean:
	$(MAKE) -C $(LUAJIT) clean
	cargo clean
	rm -f $(LUAJIT)/libluajit-5.1.a src/embedded_hosted_lua.rs

bench:
	luajit benchmarks/bench_json_stack_decode.lua
