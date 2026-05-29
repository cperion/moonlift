#ifndef SPONJIT_RUNTIME_H
#define SPONJIT_RUNTIME_H

#include <stdint.h>
#include <stddef.h>

#include "lua.h"
#include "lstate.h"
#include "lobject.h"
#include "lopcodes.h"
#include "sponbank.h"

typedef struct SponPatchedTile {
  SponTileId tile_id;
  uint32_t pc_start;
  uint32_t pc_end;
  void *code;
  size_t code_size;
} SponPatchedTile;

typedef struct SponImage {
  uint32_t pc_start;
  uint32_t pc_end;
  uint32_t n_tiles;
  SponFactSig entry_sig;
  SponFactSig observed_sig;
  SponPatchedTile *tiles;
} SponImage;

int spon_image_build(lua_State *L, const Proto *p, uint32_t pc_start, uint32_t pc_end,
                     SponFactSig entry_sig, SponFactSig observed_sig,
                     SponImage **out_image);
int spon_image_execute(SponImage *img, StkId base, const Proto *p, uint32_t *resume_pc);
void spon_image_free(SponImage *img);

SponFactSig spon_observe_i64_slots(StkId base, uint32_t max_slots);

#endif
