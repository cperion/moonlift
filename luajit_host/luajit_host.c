// luajit_host.c — standalone binary embedding LuaJIT + internal JIT API
#include "lj_obj.h"
#include "lj_jit.h"
#include "lj_ir.h"
#include "lj_iropt.h"
#include "lj_asm.h"
#include "lj_trace.h"
#include "lj_mcode.h"
#include "lj_gc.h"
#include "lj_state.h"
#include "lj_dispatch.h"
#include "lua.h"
#include "lualib.h"
#include "lauxlib.h"
#include <string.h>
#include <stdlib.h>

typedef struct { int o, t, op1, op2, i; } PackedIRIns;

static int cf_lj_jit_init(lua_State *L) {
    lj_trace_initstate(G(L));
    lj_dispatch_init_hotcount(G(L));
    lj_dispatch_update(G(L));
    jit_State *J = L2J(L);
    MCode *lim;
    lj_mcode_reserve(J, &lim);
    J->mctop = J->mcarea;
    lua_pushboolean(L, 1);
    return 1;
}

static int cf_ir_trace_compile(lua_State *L) {
    jit_State *J = L2J(L);
    luaL_checktype(L, 1, LUA_TTABLE);
    int nir = (int)lua_objlen(L, 1);
    int nk  = (int)luaL_optinteger(L, 2, 0);
    int ni  = nir - nk;
    if (ni < 2) { lua_pushnil(L); lua_pushstring(L, "ni<2"); return 2; }

    PackedIRIns *d = malloc((size_t)nir * sizeof(PackedIRIns));
    for (int i=0;i<nir;i++){
        lua_rawgeti(L,1,i+1);
        lua_getfield(L,-1,"o"); d[i].o=(int)lua_tointeger(L,-1); lua_pop(L,1);
        lua_getfield(L,-1,"t"); d[i].t=(int)lua_tointeger(L,-1); lua_pop(L,1);
        lua_getfield(L,-1,"op1");d[i].op1=(int)lua_tointeger(L,-1);lua_pop(L,1);
        lua_getfield(L,-1,"op2");d[i].op2=(int)lua_tointeger(L,-1);lua_pop(L,1);
        lua_getfield(L,-1,"i");  d[i].i=(int)lua_tointeger(L,-1);  lua_pop(L,1);
        lua_pop(L,1);
    }

    int total = REF_BIAS + ni + 64;
    IRIns *irbuf = calloc((size_t)total, sizeof(IRIns));
    irbuf[REF_NIL].o=IR_KPRI;   irbuf[REF_NIL].t.irt=IRT_NIL;
    irbuf[REF_TRUE].o=IR_KPRI;  irbuf[REF_TRUE].t.irt=IRT_TRUE;
    irbuf[REF_FALSE].o=IR_KPRI; irbuf[REF_FALSE].t.irt=IRT_FALSE;

    // Constants at irbuf[0..nk-1], instructions at irbuf[REF_BIAS..]
    for (int i=0;i<nk;i++) {
        IRIns *ins=&irbuf[i];
        ins->o=(IROp1)d[i].o; ins->t.irt=(uint8_t)d[i].t;
        ins->op1=(IRRef1)d[i].op1; ins->op2=(IRRef1)d[i].op2;
        ins->i=d[i].i; ins->prev=0;
    }
    for (int i=0;i<ni;i++) {
        IRIns *ins=&irbuf[REF_BIAS+i];
        int idx=nk+i;
        ins->o=(IROp1)d[idx].o; ins->t.irt=(uint8_t)d[idx].t;
        ins->op1=(IRRef1)d[idx].op1; ins->op2=(IRRef1)d[idx].op2;
        ins->i=d[idx].i; ins->prev=0;
    }
    free(d);

    GCtrace *T = lj_mem_new(L, sizeof(GCtrace));
    memset(T,0,sizeof(GCtrace));
    GCproto *pt = lj_mem_new(L, sizeof(GCproto));
    memset(pt,0,sizeof(GCproto));
    pt->gct=(uint8_t)~LJ_TPROTO;
    setgcrefp(T->startpt, pt);
    T->topslot=0; T->traceno=1; T->link=1; T->linktype=LJ_TRLINK_ROOT;
    T->nins=REF_BIAS+ni; T->nk=REF_BIAS; T->ir=irbuf;
    T->nsnap=0; T->nsnapmap=0;

    memset(&J->cur,0,sizeof(GCtrace));
    J->cur.traceno=1; J->cur.link=1; J->cur.linktype=LJ_TRLINK_ROOT;
    J->cur.ir=irbuf; J->cur.nins=REF_BIAS+ni; J->cur.nk=REF_BIAS;
    J->cur.nsnap=0; J->cur.nsnapmap=0;
    J->cur.snap=lj_mem_new(L,sizeof(SnapShot));
    J->cur.snapmap=lj_mem_new(L,sizeof(SnapEntry));
    memset(J->cur.snap,0,sizeof(SnapShot));
    memset(J->cur.snapmap,0,sizeof(SnapEntry));
    J->irtoplim=REF_BIAS+ni+64; J->irbotlim=0; J->loopref=0;
    J->framedepth=0; J->maxslot=0; J->baseslot=0;
    J->bc_min=NULL; J->bc_extent=0; J->pt=NULL; J->pc=NULL;
    J->mctop=J->mcarea;
    J->mcbot=(MCode*)((char*)J->mcarea+J->szmcarea);
    J->curfinal=T; T->mcode=J->mctop;
    memset(&J->fold,0,sizeof(J->fold)); J->fold.ins.o=IR_NOP;
    memset(J->chain,0,sizeof(J->chain));

    lj_opt_fold(J);
    lj_opt_cse(J);
    lj_opt_dce(J);
    lj_opt_sink(J);

    T->nins=J->cur.nins; T->nk=J->cur.nk; T->ir=irbuf;
    // lj_asm_trace(J, T);  // TODO: GC state wiring

    lua_newtable(L);
    lua_pushinteger(L, T->nins - T->nk); lua_setfield(L,-2,"nins");
    lua_pushinteger(L, T->nk); lua_setfield(L,-2,"nk");
    free(irbuf);
    lj_mem_free(G(L),pt,sizeof(GCproto));
    lj_mem_free(G(L),T,sizeof(GCtrace));
    return 1;
}

static const luaL_Reg jit_lib[]={
    {"init",cf_lj_jit_init},{"compile",cf_ir_trace_compile},{NULL,NULL}
};

int main(int argc,char**argv){
    lua_State*L=luaL_newstate(); luaL_openlibs(L);
    lua_getglobal(L,"jit");
    if(lua_isnil(L,-1)){lua_pop(L,1);lua_newtable(L);lua_setglobal(L,"jit");lua_getglobal(L,"jit");}
    luaL_setfuncs(L,jit_lib,0); lua_pop(L,1);
    if(argc<2){printf("luajit_host — -e code\n");lua_close(L);return 0;}
    int s=0;
    for(int i=1;i<argc;i++){
        if(!strcmp(argv[i],"-e")&&i+1<argc)s=luaL_dostring(L,argv[++i]);
        else s=luaL_dofile(L,argv[i]);
        if(s){fprintf(stderr,"%s\n",lua_tostring(L,-1));lua_pop(L,1);}
    }
    lua_close(L);return s;
}
