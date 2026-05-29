#ifndef SPONBANK_H
#define SPONBANK_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef uint64_t SponFactSig;
typedef uint32_t SponFragmentId;

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
  SponFragmentId fragment_id;
  uint32_t pc_start;
  uint32_t pc_end;
} SponFragmentChoice;

typedef struct {
  uint64_t pattern_probes;
  uint64_t candidate_checks;
  uint32_t choices;
} SponSelectStats;

typedef struct {
  uint16_t op_idx;
  uint8_t logical_slot;
  uint8_t field_kind;
} SponSlotMapEntry;

enum {
  SPON_FRAGMENT_ABSTRACT = 1u << 0,
  SPON_FRAGMENT_NATIVE = 1u << 1,
  SPON_FRAGMENT_PUC_PATCHABLE = 1u << 2
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
  SPON_ABI_X86_64_SYSV_SPON_V1 = 1
};

enum {
  SPON_VALUE_UNKNOWN = 0,
  SPON_VALUE_TVALUE = 1,
  SPON_VALUE_I64 = 2,
  SPON_VALUE_BOOL = 3,
  SPON_VALUE_PTR = 4
};

enum {
  SPON_LOC_NONE = 0,
  SPON_LOC_REG = 1,
  SPON_LOC_CTX_FIELD = 2,
  SPON_LOC_FRAME_SLOT = 3,
  SPON_LOC_IMMEDIATE = 4
};

enum {
  SPON_ENDPOINT_ENTRY = 1,
  SPON_ENDPOINT_OK = 2,
  SPON_ENDPOINT_GUARD_EXIT = 3,
  SPON_ENDPOINT_RESIDUAL_EXIT = 4,
  SPON_ENDPOINT_BOUNDARY_EXIT = 5,
  SPON_ENDPOINT_UNLOWERED_EXIT = 6
};

enum {
  SPON_DATA_RELOC_SLOT = 1,
  SPON_DATA_RELOC_SLOT_STORE = 2,
  SPON_DATA_RELOC_IMM = 3,
  SPON_DATA_RELOC_CONST = 4,
  SPON_DATA_RELOC_BOOL = 5,
  SPON_DATA_RELOC_SHAPE_OFFSET = 6,
  SPON_DATA_RELOC_SHAPE_ID = 7,
  SPON_DATA_RELOC_METATABLE_OFFSET = 8,
  SPON_DATA_RELOC_FIELD_OFFSET = 9,
  SPON_DATA_RELOC_ARRAY_BASE_OFFSET = 10,
  SPON_DATA_RELOC_CALL_TARGET = 11,
  SPON_DATA_RELOC_BARRIER = 12
};

enum {
  SPON_CONTROL_RELOC_FALLTHROUGH = 1,
  SPON_CONTROL_RELOC_GUARD_FAIL = 2,
  SPON_CONTROL_RELOC_RESIDUAL = 3,
  SPON_CONTROL_RELOC_BOUNDARY = 4,
  SPON_CONTROL_RELOC_PROJECTION_STUB = 5
};

enum {
  SPON_PROJ_SYNCED_FRAME = 1,
  SPON_PROJ_BOX_I64 = 2
};

typedef struct {
  uint16_t kind;
  uint16_t value_type;
  uint16_t reg;
  uint16_t reserved;
  int32_t index;
} SponLocationDesc;

typedef struct {
  uint16_t kind;
  uint16_t flags;
  uint32_t location_start;
  uint16_t n_locations;
  uint16_t projection_start;
  uint16_t n_projections;
} SponEndpointDesc;

typedef struct {
  uint32_t code_offset;
  uint16_t reloc_kind;
  uint16_t role_kind;
  uint16_t op_idx;
  int32_t role_arg;
} SponDataReloc;

typedef struct {
  uint32_t code_offset;
  uint16_t reloc_kind;
  uint16_t edge_kind;
  uint16_t endpoint_index;
  int32_t target_delta;
} SponControlReloc;

typedef struct {
  uint16_t kind;
  uint16_t value_type;
  uint16_t logical_slot;
  uint16_t value_index;
} SponProjectionEntry;

typedef struct {
  const char *name;
} SponDependencyDesc;

typedef struct {
  SponFragmentId fragment_id;
  uint32_t offset;
  uint32_t size;
  uint32_t endpoint_start;
  uint32_t data_reloc_start;
  uint32_t control_reloc_start;
  uint32_t slotmap_start;
  uint32_t projection_start;
  uint32_t dependency_start;
  uint16_t len;
  uint16_t n_endpoints;
  uint16_t n_data_relocs;
  uint16_t n_control_relocs;
  uint16_t n_slotmaps;
  uint16_t n_projections;
  uint16_t n_dependencies;
  uint16_t flags;
  uint16_t physical_abi;
  uint16_t reserved;
  uint64_t pattern_key;
  SponFactSig selector_sig;
  SponFactSig required_sig;
  SponFactSig checked_sig;
  SponFactSig produced_sig;
  SponFactSig killed_sig;
} SponFragmentDesc;

uint32_t spon_bank_fragment_count(void);
uint32_t spon_bank_pattern_count(void);
const SponFragmentDesc *spon_get_fragment(SponFragmentId id);
const unsigned char *spon_fragment_data(SponFragmentId id);
const SponEndpointDesc *spon_fragment_endpoints(SponFragmentId id, uint32_t *out_n);
const SponDataReloc *spon_fragment_data_relocs(SponFragmentId id, uint32_t *out_n);
const SponControlReloc *spon_fragment_control_relocs(SponFragmentId id, uint32_t *out_n);
const SponSlotMapEntry *spon_fragment_slotmaps(SponFragmentId id, uint32_t *out_n);
const SponProjectionEntry *spon_fragment_projections(SponFragmentId id, uint32_t *out_n);
const SponDependencyDesc *spon_fragment_dependencies(SponFragmentId id, uint32_t *out_n);
SponFragmentId spon_l0_fragment_for_opcode(uint32_t opcode);

const SponFragmentChoice *spon_select_greedy_stats(const uint32_t *bc, uint32_t start, uint32_t end,
                                                  SponFactSig observed_sig, uint32_t *out_n,
                                                  SponSelectStats *stats);
const SponFragmentChoice *spon_select_greedy(const uint32_t *bc, uint32_t start, uint32_t end,
                                            SponFactSig observed_sig, uint32_t *out_n);

const SponFragmentChoice *spon_select_flow_stats(const uint32_t *bc, uint32_t start, uint32_t end,
                                                SponFactSig entry_sig, SponFactSig observed_sig,
                                                uint32_t *out_n, SponSelectStats *stats);
const SponFragmentChoice *spon_select_flow(const uint32_t *bc, uint32_t start, uint32_t end,
                                          SponFactSig entry_sig, SponFactSig observed_sig,
                                          uint32_t *out_n);
const SponFragmentChoice *spon_select_flow_flags_stats(const uint32_t *bc, uint32_t start, uint32_t end,
                                                      SponFactSig entry_sig, SponFactSig observed_sig,
                                                      uint16_t required_fragment_flags,
                                                      uint32_t *out_n, SponSelectStats *stats);
const SponFragmentChoice *spon_select_flow_flags(const uint32_t *bc, uint32_t start, uint32_t end,
                                                SponFactSig entry_sig, SponFactSig observed_sig,
                                                uint16_t required_fragment_flags,
                                                uint32_t *out_n);
const SponFragmentChoice *spon_select_flow_flags_slots_stats(const uint32_t *bc, uint32_t start, uint32_t end,
                                                            SponFactSig entry_sig, SponFactSig observed_sig,
                                                            uint16_t required_fragment_flags,
                                                            const SponSlotMapEntry *actual_slots,
                                                            uint32_t n_actual_slots,
                                                            uint32_t *out_n, SponSelectStats *stats);
const SponFragmentChoice *spon_select_flow_flags_slots(const uint32_t *bc, uint32_t start, uint32_t end,
                                                      SponFactSig entry_sig, SponFactSig observed_sig,
                                                      uint16_t required_fragment_flags,
                                                      const SponSlotMapEntry *actual_slots,
                                                      uint32_t n_actual_slots,
                                                      uint32_t *out_n);

#ifdef __cplusplus
}
#endif

#endif
