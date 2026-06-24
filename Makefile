LUAJIT    = .vendor/LuaJIT/src
TINYCC    = deps/tinycc
TCC_PREFIX = $(CURDIR)/$(TINYCC)/.local
LIBTCC    = $(TINYCC)/.local/lib/libtcc.so

.PHONY: all luajit clean bench libtcc

all: luajit
luajit: $(LUAJIT)/libluajit.a

$(LUAJIT)/libluajit.a:
	$(MAKE) -C $(LUAJIT) CFLAGS="-fPIC"
	ln -sf libluajit.a $(LUAJIT)/libluajit-5.1.a

libtcc: $(LIBTCC)

$(LIBTCC): $(TINYCC)/configure
	cd $(TINYCC) && ./configure --prefix="$(TCC_PREFIX)" --disable-static
	$(MAKE) -C $(TINYCC) libtcc.so libtcc1.a tcc
	$(MAKE) -C $(TINYCC) install

clean:
	$(MAKE) -C $(LUAJIT) clean
	rm -f $(LUAJIT)/libluajit-5.1.a

bench:
	luajit benchmarks/bench_json_stack_decode.lua
