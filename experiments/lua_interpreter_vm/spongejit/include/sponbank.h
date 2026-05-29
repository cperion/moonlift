#ifndef SPONBANK_H
#define SPONBANK_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef uint64_t SponFactSig;
typedef uint32_t SponTileId;

typedef struct SponTValueABI {
  unsigned long long value_;
  unsigned char tt_;
} SponTValueABI;

typedef struct SponExecCtx {
  void *stack;
  SponTValueABI *k;
  SponTValueABI scratch[256];
  uint32_t exit_kind;
  uint32_t exit_pc;
  uint32_t exit_op_idx;
  uint32_t exit_hole;
} SponExecCtx;

enum {
  SPON_EXIT_NONE = 0,
  SPON_EXIT_GUARD = 1,
  SPON_EXIT_RESIDUAL = 2,
  SPON_EXIT_BOUNDARY = 3,
  SPON_EXIT_BARRIER = 4,
  SPON_EXIT_UNLOWERED = 5
};

typedef struct {
  SponTileId tile_id;
  uint32_t pc_start;
  uint32_t pc_end;
} SponTileChoice;

typedef struct {
  uint64_t pattern_probes;
  uint64_t candidate_checks;
  uint32_t choices;
} SponSelectStats;

typedef struct {
  uint32_t code_offset;
  uint16_t hole_id;
  uint16_t reloc_kind;
  uint16_t role_kind;
  uint16_t op_idx;
  int32_t role_arg;
} SponHoleReloc;

typedef struct {
  SponTileId tile_id;
  uint32_t offset;
  uint32_t size;
  uint32_t hole_start;
  uint32_t slotmap_start;
  uint16_t len;
  uint16_t n_holes;
  uint16_t n_slotmaps;
  uint16_t flags;
  SponFactSig fact_sig;      /* selector/profitability signature */
  uint64_t pattern_key;
  SponFactSig required_sig;  /* must hold in incoming propagated facts */
  SponFactSig checked_sig;   /* guard-proven on success */
  SponFactSig produced_sig;  /* semantically created on success */
  SponFactSig killed_sig;    /* invalidated by writes/effects */
} SponTileDesc;

typedef struct {
  uint16_t op_idx;
  uint8_t logical_slot;
  uint8_t field_kind;
} SponSlotMapEntry;

enum {
  SPON_TILE_PUC_PATCHABLE = 1u << 0
};

enum {
  SPON_FIELD_A = 1,
  SPON_FIELD_B = 2,
  SPON_FIELD_C = 3,
  SPON_FIELD_DEST = 4,
  SPON_FIELD_AUX = 5
};

enum {
  SPON_RELOC_UNKNOWN=0,
  SPON_RELOC_ABS32=1,
  SPON_RELOC_ABS32S=2,
  SPON_RELOC_PLT32=3,
  SPON_RELOC_PC32=4
};

enum {
  SPON_HOLE_UNKNOWN=0,
  SPON_HOLE_SLOT=1,
  SPON_HOLE_IMM=2,
  SPON_HOLE_CONST=3,
  SPON_HOLE_BOOL=4,
  SPON_HOLE_EXIT=5,
  SPON_HOLE_FAIL=6,
  SPON_HOLE_SHAPE_OFFSET=7,
  SPON_HOLE_SHAPE_ID=8,
  SPON_HOLE_METATABLE_OFFSET=9,
  SPON_HOLE_FIELD_OFFSET=10,
  SPON_HOLE_ARRAY_BASE_OFFSET=11,
  SPON_HOLE_CALL_TARGET=12,
  SPON_HOLE_BARRIER=13,
  SPON_HOLE_SLOT_STORE=14
};

uint32_t spon_bank_tile_count(void);
uint32_t spon_bank_pattern_count(void);
uint32_t spon_bank_hole_count(void);
const SponTileDesc *spon_get_tile(SponTileId id);
const unsigned char *spon_tile_data(SponTileId id);
const SponHoleReloc *spon_tile_holes(SponTileId id, uint32_t *out_n);
const SponSlotMapEntry *spon_tile_slotmaps(SponTileId id, uint32_t *out_n);
SponTileId spon_l0_for_opcode(uint32_t opcode);

/* Legacy selector: one observed signature for the whole region; no fact flow. */
const SponTileChoice *spon_select_greedy_stats(const uint32_t *bc, uint32_t start, uint32_t end,
                                              SponFactSig observed_sig, uint32_t *out_n,
                                              SponSelectStats *stats);
const SponTileChoice *spon_select_greedy(const uint32_t *bc, uint32_t start, uint32_t end,
                                        SponFactSig observed_sig, uint32_t *out_n);

/* Real image selector: propagates required/checked/produced/killed facts across the cover. */
const SponTileChoice *spon_select_flow_stats(const uint32_t *bc, uint32_t start, uint32_t end,
                                            SponFactSig entry_sig, SponFactSig observed_sig,
                                            uint32_t *out_n, SponSelectStats *stats);
const SponTileChoice *spon_select_flow(const uint32_t *bc, uint32_t start, uint32_t end,
                                      SponFactSig entry_sig, SponFactSig observed_sig,
                                      uint32_t *out_n);
const SponTileChoice *spon_select_flow_flags_stats(const uint32_t *bc, uint32_t start, uint32_t end,
                                                  SponFactSig entry_sig, SponFactSig observed_sig,
                                                  uint16_t required_tile_flags,
                                                  uint32_t *out_n, SponSelectStats *stats);
const SponTileChoice *spon_select_flow_flags(const uint32_t *bc, uint32_t start, uint32_t end,
                                            SponFactSig entry_sig, SponFactSig observed_sig,
                                            uint16_t required_tile_flags,
                                            uint32_t *out_n);
const SponTileChoice *spon_select_flow_flags_slots_stats(const uint32_t *bc, uint32_t start, uint32_t end,
                                                        SponFactSig entry_sig, SponFactSig observed_sig,
                                                        uint16_t required_tile_flags,
                                                        const SponSlotMapEntry *actual_slots,
                                                        uint32_t n_actual_slots,
                                                        uint32_t *out_n, SponSelectStats *stats);
const SponTileChoice *spon_select_flow_flags_slots(const uint32_t *bc, uint32_t start, uint32_t end,
                                                  SponFactSig entry_sig, SponFactSig observed_sig,
                                                  uint16_t required_tile_flags,
                                                  const SponSlotMapEntry *actual_slots,
                                                  uint32_t n_actual_slots,
                                                  uint32_t *out_n);

#ifdef __cplusplus
}
#endif

#endif
