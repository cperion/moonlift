// puc_trace_operands.c -- run PUC Lua with count hook and dump dynamic
// instruction trace including decoded operands.

#include <stdio.h>
#include <stdlib.h>

#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"

#include "lstate.h"
#include "lobject.h"
#include "ldebug.h"
#include "lopcodes.h"
#include "lopnames.h"

static unsigned long long g_seq = 0;
static unsigned long long g_limit = 0;
static FILE *g_out = NULL;

static void trace_hook(lua_State *L, lua_Debug *ar) {
    (void)ar;
    if (g_limit != 0 && g_seq >= g_limit) {
        lua_sethook(L, NULL, 0, 0);
        return;
    }
    CallInfo *ci = L->ci;
    if (!isLua(ci)) return;
    const Proto *p = ci_func(ci)->p;
    const Instruction *ip = ci->u.l.savedpc - 1;
    int pc = (int)(ip - p->code);
    if (pc < 0 || pc >= p->sizecode) return;
    Instruction ins = *ip;
    OpCode op = GET_OPCODE(ins);
    fprintf(g_out, "%llu\t%p\t%d\t%d\t%s\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%u\n",
        g_seq++, (const void*)p, pc, (int)op, opnames[op],
        GETARG_A(ins), GETARG_B(ins), GETARG_C(ins), GETARG_k(ins),
        GETARG_Bx(ins), GETARG_sBx(ins), GETARG_Ax(ins), (unsigned int)ins);
}

int main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr, "usage: %s file.lua [limit] [trace.tsv] [script-args...]\n", argv[0]);
        return 2;
    }
    const char *file = argv[1];
    g_limit = argc >= 3 ? strtoull(argv[2], NULL, 10) : 1000000ULL;
    const char *trace_path = argc >= 4 ? argv[3] : NULL;
    g_out = trace_path ? fopen(trace_path, "wb") : stdout;
    if (!g_out) { perror(trace_path); return 1; }

    lua_State *L = luaL_newstate();
    if (!L) return 1;
    luaL_openlibs(L);

    if (luaL_loadfile(L, file) != LUA_OK) {
        fprintf(stderr, "%s\n", lua_tostring(L, -1));
        lua_close(L);
        if (trace_path) fclose(g_out);
        return 1;
    }

    int nargs = 0;
    if (argc > 4) {
        nargs = argc - 4;
        for (int i = 4; i < argc; i++) lua_pushstring(L, argv[i]);
    }

    fprintf(g_out, "seq\tproto\tpc\topcode\tname\ta\tb\tc\tk\tbx\tsbx\tax\tword\n");
    lua_sethook(L, trace_hook, LUA_MASKCOUNT, 1);
    int rc = lua_pcall(L, nargs, LUA_MULTRET, 0);
    lua_sethook(L, NULL, 0, 0);
    if (rc != LUA_OK) {
        fprintf(stderr, "%s\n", lua_tostring(L, -1));
        // Keep trace; profiling partial execution is still useful.
    }
    lua_close(L);
    if (trace_path) fclose(g_out);
    return rc == LUA_OK ? 0 : 1;
}
