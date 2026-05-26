// puc_proto_dump.c -- dump PUC Lua 5.5 Proto instructions with operands.
// Build from repo root:
//   cc -I.vendor/Lua tools/.../puc_proto_dump.c .vendor/Lua/liblua.a -lm -ldl -o build/puc_proto_dump

#include <stdio.h>
#include <stdlib.h>

#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"

#include "lstate.h"
#include "lobject.h"
#include "lopcodes.h"
#include "lopnames.h"

static void dump_proto(const Proto *p, int depth, unsigned long *proto_id) {
    unsigned long id = (*proto_id)++;
    for (int pc = 0; pc < p->sizecode; pc++) {
        Instruction ins = p->code[pc];
        OpCode op = GET_OPCODE(ins);
        int a = GETARG_A(ins);
        int b = GETARG_B(ins);
        int c = GETARG_C(ins);
        int k = GETARG_k(ins);
        int bx = GETARG_Bx(ins);
        int sbx = GETARG_sBx(ins);
        int ax = GETARG_Ax(ins);
        const char *name = opnames[op];
        printf("%lu\t%d\t%d\t%d\t%s\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%u\n",
            id, depth, pc, (int)op, name ? name : "?", a, b, c, k, bx, sbx, ax, (unsigned int)ins);
    }
    for (int i = 0; i < p->sizep; i++) {
        dump_proto(p->p[i], depth + 1, proto_id);
    }
}

int main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr, "usage: %s file.lua\n", argv[0]);
        return 2;
    }
    lua_State *L = luaL_newstate();
    if (L == NULL) return 1;
    luaL_openlibs(L);
    int rc = luaL_loadfile(L, argv[1]);
    if (rc != LUA_OK) {
        fprintf(stderr, "%s\n", lua_tostring(L, -1));
        lua_close(L);
        return 1;
    }
    StkId top = L->top.p - 1;
    const TValue *o = s2v(top);
    if (!ttisLclosure(o)) {
        fprintf(stderr, "top is not Lua closure\n");
        lua_close(L);
        return 1;
    }
    printf("proto\tdepth\tpc\topcode\tname\ta\tb\tc\tk\tbx\tsbx\tax\tword\n");
    unsigned long proto_id = 0;
    dump_proto(clLvalue(o)->p, 0, &proto_id);
    lua_close(L);
    return 0;
}
