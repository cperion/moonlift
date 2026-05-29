#ifndef LSPONJIT_H
#define LSPONJIT_H

#include "lstate.h"
#include "lobject.h"

void luaSponJIT_freeproto(lua_State *L, Proto *p);
int luaSponJIT_maybe_enter(lua_State *L, CallInfo *ci, Proto *p, StkId base,
                           const Instruction **ppc, Instruction i, int trap);

#endif
