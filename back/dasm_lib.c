/*
** LalinLift DynASM encoding engine.
** Compiles dasm_x86.h into a shared library for LuaJIT FFI.
**
** Build:  gcc -shared -fPIC -O2 -I.vendor/LuaJIT/dynasm -I.vendor/LuaJIT/src \
**              -o back/libdasm.so back/dasm_lib.c
*/

#define DASM_CHECKS 1
#include "dasm_proto.h"
#include "dasm_x86.h"

/* ── memory hooks (default: realloc / free) ────────────────────────── */

#ifndef DASM_M_GROW
#define DASM_M_GROW(ctx, t, p, sz, need) \
  do { \
    size_t _sz = (sz), _need = (need); \
    if (_sz < _need) { \
      if (_sz < 16) _sz = 16; \
      while (_sz < _need) _sz += _sz; \
      (p) = (t *)realloc((p), _sz); \
      if ((p) == NULL) exit(1); \
      (sz) = _sz; \
    } \
  } while(0)
#endif

#ifndef DASM_M_FREE
#define DASM_M_FREE(ctx, p, sz)  free(p)
#endif

/* ── extern resolution ─────────────────────────────────────────────── */

/*
 * Called by dasm_encode pass 3 when it encounters an EXTERN action.
 * Returns the target address as a signed offset from the code position.
 *
 * The Lua side patches the host_extern_fn function pointer before
 * calling dasm_encode so that we can resolve symbols dynamically.
 */
static int (*host_extern_fn)(void *ctx, unsigned char *addr, int idx, int type);

void dasm_set_extern_fn(int (*fn)(void *, unsigned char *, int, int)) {
    host_extern_fn = fn;
}

#undef  DASM_EXTERN
#define DASM_EXTERN(ctx, addr, idx, type) \
    (host_extern_fn ? host_extern_fn(ctx, addr, idx, type) : 0)

/* ── expose dasm_put with a counted-argument calling convention ────── */

/*
 * Varargs across FFI boundaries is fragile.  We expose a trampoline that
 * takes a flat array of dasm_put arguments.  The Lua side prepares an
 * int[] and calls dasm_put_array.
 */
#include <stdint.h>

void dasm_put_array(dasm_State **Dst, int start, const int *args, int nargs) {
    /* dasm_put internally uses va_arg.  We forward through a small
       switch to avoid the need for libffi or platform-specific vararg
       calling.  12 args covers essentially all LalinLift fragments. */
    switch (nargs) {
    case  0: dasm_put(Dst, start); break;
    case  1: dasm_put(Dst, start, args[0]); break;
    case  2: dasm_put(Dst, start, args[0], args[1]); break;
    case  3: dasm_put(Dst, start, args[0], args[1], args[2]); break;
    case  4: dasm_put(Dst, start, args[0], args[1], args[2], args[3]); break;
    case  5: dasm_put(Dst, start, args[0], args[1], args[2], args[3], args[4]); break;
    case  6: dasm_put(Dst, start, args[0], args[1], args[2], args[3], args[4], args[5]); break;
    case  7: dasm_put(Dst, start, args[0], args[1], args[2], args[3], args[4], args[5], args[6]); break;
    case  8: dasm_put(Dst, start, args[0], args[1], args[2], args[3], args[4], args[5], args[6], args[7]); break;
    case  9: dasm_put(Dst, start, args[0], args[1], args[2], args[3], args[4], args[5], args[6], args[7], args[8]); break;
    case 10: dasm_put(Dst, start, args[0], args[1], args[2], args[3], args[4], args[5], args[6], args[7], args[8], args[9]); break;
    case 11: dasm_put(Dst, start, args[0], args[1], args[2], args[3], args[4], args[5], args[6], args[7], args[8], args[9], args[10]); break;
    case 12: dasm_put(Dst, start, args[0], args[1], args[2], args[3], args[4], args[5], args[6], args[7], args[8], args[9], args[10], args[11]); break;
    case 13: dasm_put(Dst, start, args[0], args[1], args[2], args[3], args[4], args[5], args[6], args[7], args[8], args[9], args[10], args[11], args[12]); break;
    case 14: dasm_put(Dst, start, args[0], args[1], args[2], args[3], args[4], args[5], args[6], args[7], args[8], args[9], args[10], args[11], args[12], args[13]); break;
    case 15: dasm_put(Dst, start, args[0], args[1], args[2], args[3], args[4], args[5], args[6], args[7], args[8], args[9], args[10], args[11], args[12], args[13], args[14]); break;
    case 16: dasm_put(Dst, start, args[0], args[1], args[2], args[3], args[4], args[5], args[6], args[7], args[8], args[9], args[10], args[11], args[12], args[13], args[14], args[15]); break;
    default: break;
    }
}
