LJ_SRC  = ../.vendor/LuaJIT/src
CFLAGS  = -O2 -I$(LJ_SRC) -I$(LJ_SRC)/host -DLUA_CORE -DLUAJIT_TARGET=LUAJIT_ARCH_X64
LDFLAGS = -lm -ldl

luajit_host: luajit_host.c
	gcc $(CFLAGS) -o $@ $< $(LJ_SRC)/libluajit.a $(LDFLAGS)

clean:
	rm -f luajit_host
