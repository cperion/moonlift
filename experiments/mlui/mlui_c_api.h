#ifndef MLUI_C_API_H
#define MLUI_C_API_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#ifndef MLUI_API
#define MLUI_API extern
#endif

typedef uint8_t mlui_bool;
typedef uint32_t mlui_id;
typedef uint32_t mlui_node_ref;
typedef uint32_t mlui_content_ref;
typedef uint32_t mlui_text_layout_ref;
typedef uint32_t mlui_paint_ref;
typedef uint32_t mlui_image_ref;
typedef uint32_t mlui_font_ref;
typedef uint32_t mlui_value_ref;

typedef struct mlui_kernel mlui_kernel;

enum {
    MLUI_ABI_VERSION = 1,
    MLUI_MAGIC = 0x4d4c5549u,
    MLUI_INVALID_HANDLE = 0
};

enum {
    MLUI_ENDIAN_LITTLE = 1,
    MLUI_ENDIAN_BIG = 2
};

enum {
    MLUI_ROOT_AUTH = 0,
    MLUI_ROOT_COMPOSE = 1
};

enum {
    MLUI_OK = 0,
    MLUI_OOM = 1,
    MLUI_DUPLICATE_ID = 2,
    MLUI_INVALID_ID = 3,
    MLUI_INVALID_CHILD = 4,
    MLUI_UNSUPPORTED_NODE = 5,
    MLUI_MISSING_NODE = 6,
    MLUI_MISSING_TEXT = 7,
    MLUI_TEXT_BACKEND_ERROR = 8,
    MLUI_DECOR_MISMATCH = 9,
    MLUI_MALFORMED_OP = 10,
    MLUI_STACK_UNBALANCED = 11,
    MLUI_STALE_FOCUS = 12,
    MLUI_STALE_CAPTURE = 13,
    MLUI_MISSING_SCROLL = 14,
    MLUI_INVALID_HEADER = 15,
    MLUI_INVALID_SECTION = 16,
    MLUI_INVALID_OPCODE = 17,
    MLUI_INVALID_RANGE = 18,
    MLUI_INVALID_ARITY = 19,
    MLUI_MISSING_RESOURCE = 20,
    MLUI_UNSUPPORTED_FEATURE = 21
};

enum {
    MLUI_SECTION_AUTH = 1,
    MLUI_SECTION_CHILDREN = 2,
    MLUI_SECTION_STYLE_TOKENS = 3,
    MLUI_SECTION_STYLE_TRACKS = 4,
    MLUI_SECTION_COMPOSE = 5,
    MLUI_SECTION_COMPOSE_CHILDREN = 6,
    MLUI_SECTION_PAINT = 7,
    MLUI_SECTION_PAINT_POINTS = 8,
    MLUI_SECTION_PAINT_VERTICES = 9,
    MLUI_SECTION_CONTENT_REFS = 10,
    MLUI_SECTION_IMAGE_REFS = 11,
    MLUI_SECTION_FONT_REFS = 12,
    MLUI_SECTION_VALUE_REFS = 13
};

enum {
    MLUI_AUTH_INVALID = 0,
    MLUI_AUTH_EMPTY = 1,
    MLUI_AUTH_FRAGMENT = 2,
    MLUI_AUTH_BOX = 3,
    MLUI_AUTH_TEXT = 4,
    MLUI_AUTH_TEXT_REF = 5,
    MLUI_AUTH_PAINT = 6,
    MLUI_AUTH_SCROLL = 7,
    MLUI_AUTH_WITH_INPUT = 8,
    MLUI_AUTH_WITH_DRAG_SOURCE = 9,
    MLUI_AUTH_WITH_DROP_TARGET = 10,
    MLUI_AUTH_WITH_DROP_SLOT = 11,
    MLUI_AUTH_WITH_STATE = 12,
    MLUI_AUTH_FOCUS_SCOPE = 13,
    MLUI_AUTH_LAYER = 14,
    MLUI_AUTH_OVERLAY = 15,
    MLUI_AUTH_MODAL = 16
};

enum {
    MLUI_COMPOSE_INVALID = 0,
    MLUI_COMPOSE_PANEL = 1,
    MLUI_COMPOSE_SCROLL_PANEL = 2,
    MLUI_COMPOSE_HSPLIT = 3,
    MLUI_COMPOSE_VSPLIT = 4,
    MLUI_COMPOSE_WORKBENCH = 5,
    MLUI_COMPOSE_RAW_AUTH = 6
};

enum {
    MLUI_PAINT_INVALID = 0,
    MLUI_PAINT_LINE = 1,
    MLUI_PAINT_POLYLINE = 2,
    MLUI_PAINT_POLYGON = 3,
    MLUI_PAINT_CIRCLE = 4,
    MLUI_PAINT_ARC = 5,
    MLUI_PAINT_BEZIER = 6,
    MLUI_PAINT_MESH = 7,
    MLUI_PAINT_IMAGE = 8
};

enum {
    MLUI_VIEW_INVALID = 0,
    MLUI_VIEW_BOX = 1,
    MLUI_VIEW_TEXT = 2,
    MLUI_VIEW_PAINT = 3,
    MLUI_VIEW_PUSH_CLIP_RECT = 4,
    MLUI_VIEW_POP_CLIP = 5,
    MLUI_VIEW_PUSH_TX = 6,
    MLUI_VIEW_POP_TX = 7,
    MLUI_VIEW_PUSH_SCROLL = 8,
    MLUI_VIEW_POP_SCROLL = 9,
    MLUI_VIEW_HIT = 10,
    MLUI_VIEW_FOCUS = 11,
    MLUI_VIEW_CURSOR = 12,
    MLUI_VIEW_DRAG_SOURCE = 13,
    MLUI_VIEW_DROP_TARGET = 14,
    MLUI_VIEW_DROP_SLOT = 15,
    MLUI_VIEW_BEGIN_FOCUS_SCOPE = 16,
    MLUI_VIEW_END_FOCUS_SCOPE = 17,
    MLUI_VIEW_BEGIN_LAYER = 18,
    MLUI_VIEW_END_LAYER = 19,
    MLUI_VIEW_OVERLAY = 20,
    MLUI_VIEW_MODAL_BARRIER = 21
};

enum {
    MLUI_RAW_INVALID = 0,
    MLUI_RAW_POINTER_MOVED = 1,
    MLUI_RAW_POINTER_PRESSED = 2,
    MLUI_RAW_POINTER_RELEASED = 3,
    MLUI_RAW_POINTER_CANCELLED = 4,
    MLUI_RAW_WHEEL_MOVED = 5,
    MLUI_RAW_KEY_PRESSED = 6,
    MLUI_RAW_KEY_RELEASED = 7,
    MLUI_RAW_TEXT_INPUT = 8,
    MLUI_RAW_TEXT_EDITING = 9,
    MLUI_RAW_FOCUS_MOVE = 10,
    MLUI_RAW_FOCUS_LOST = 11,
    MLUI_RAW_ACTIVATE_FOCUSED = 12,
    MLUI_RAW_CANCEL_INTERACTION = 13
};

enum {
    MLUI_EVENT_INVALID = 0,
    MLUI_EVENT_SET_POINTER = 1,
    MLUI_EVENT_SET_HOVER = 2,
    MLUI_EVENT_CLEAR_HOVER = 3,
    MLUI_EVENT_SET_FOCUS = 4,
    MLUI_EVENT_CLEAR_FOCUS = 5,
    MLUI_EVENT_SET_PRESSED = 6,
    MLUI_EVENT_CLEAR_PRESSED = 7,
    MLUI_EVENT_SET_CAPTURE = 8,
    MLUI_EVENT_RELEASE_CAPTURE = 9,
    MLUI_EVENT_CLEAR_CAPTURE = 10,
    MLUI_EVENT_CANCEL_CAPTURE = 11,
    MLUI_EVENT_SET_DRAG_PENDING = 12,
    MLUI_EVENT_SET_DRAGGING = 13,
    MLUI_EVENT_CLEAR_DRAG = 14,
    MLUI_EVENT_ACTIVATE = 15,
    MLUI_EVENT_INPUT_TEXT = 16,
    MLUI_EVENT_EDIT_TEXT = 17,
    MLUI_EVENT_DRAG_STARTED = 18,
    MLUI_EVENT_DRAG_MOVED = 19,
    MLUI_EVENT_DRAG_DROPPED = 20,
    MLUI_EVENT_DRAG_CANCELLED = 21,
    MLUI_EVENT_SCROLL_BY = 22
};

enum {
    MLUI_ROLE_PASSIVE = 0,
    MLUI_ROLE_HIT_TARGET = 1,
    MLUI_ROLE_FOCUS_TARGET = 2,
    MLUI_ROLE_ACTIVATE_TARGET = 3,
    MLUI_ROLE_EDIT_TARGET = 4
};

enum {
    MLUI_BUTTON_LEFT = 1,
    MLUI_BUTTON_MIDDLE = 2,
    MLUI_BUTTON_RIGHT = 3,
    MLUI_BUTTON_X1 = 4,
    MLUI_BUTTON_X2 = 5
};

enum {
    MLUI_FOCUS_FORWARD = 1,
    MLUI_FOCUS_BACKWARD = 2
};

typedef struct mlui_view_u8 {
    const uint8_t *data;
    size_t len;
    intptr_t stride;
} mlui_view_u8;

typedef struct mlui_rect {
    double x;
    double y;
    double w;
    double h;
} mlui_rect;

typedef struct mlui_color {
    uint32_t rgba8;
} mlui_color;

typedef struct mlui_state {
    mlui_bool hovered;
    mlui_bool focused;
    mlui_bool active;
    mlui_bool selected;
    mlui_bool disabled;
} mlui_state;

typedef struct mlui_status {
    int32_t code;
    int32_t detail;
    size_t at;
    size_t needed;
} mlui_status;

typedef void *(*mlui_alloc_fn)(void *ctx, size_t size, size_t align);
typedef void *(*mlui_realloc_fn)(void *ctx, void *ptr, size_t old_size, size_t new_size, size_t align);
typedef void (*mlui_free_fn)(void *ctx, void *ptr, size_t size, size_t align);

typedef struct mlui_allocator {
    void *ctx;
    mlui_alloc_fn alloc_fn;
    mlui_realloc_fn realloc_fn;
    mlui_free_fn free_fn;
} mlui_allocator;

typedef struct mlui_kernel_config {
    mlui_allocator *allocator;
    size_t initial_node_cap;
    size_t initial_op_cap;
    size_t initial_event_cap;
    uint32_t flags;
} mlui_kernel_config;

typedef struct mlui_program_header {
    uint32_t magic;
    uint32_t abi_version;
    uint32_t flags;
    uint32_t root_index;
    uint8_t root_kind;
    uint8_t endian;
    uint8_t pointer_size;
    uint8_t reserved;
    uint64_t epoch;
} mlui_program_header;

typedef struct mlui_style_state_cond {
    uint8_t hovered;
    uint8_t focused;
    uint8_t active;
    uint8_t selected;
    uint8_t disabled;
} mlui_style_state_cond;

typedef struct mlui_style_cond {
    uint8_t bp;
    uint8_t scheme;
    uint8_t motion;
    mlui_style_state_cond state;
} mlui_style_cond;

typedef struct mlui_style_track {
    uint8_t kind;
    double a;
    double b;
} mlui_style_track;

typedef struct mlui_style_atom {
    uint16_t kind;
    double a;
    double b;
    mlui_color color;
    uint32_t track_first;
    uint32_t track_count;
} mlui_style_atom;

typedef struct mlui_style_token {
    mlui_style_cond cond;
    mlui_style_atom atom;
} mlui_style_token;

typedef struct mlui_style_token_buffer {
    mlui_style_token *tokens;
    size_t n;
    size_t cap;
    mlui_style_track *tracks;
    size_t n_track;
    size_t cap_track;
} mlui_style_token_buffer;

typedef struct mlui_program_op {
    mlui_id id;
    uint8_t kind;
    uint8_t role;
    uint8_t scroll_axis;
    uint8_t focus_policy;
    uint8_t layer_kind;
    uint8_t overlay_placement;
    mlui_id anchor_id;
    double order;
    mlui_bool modal;
    uint32_t first_child;
    uint32_t n_child;
    uint32_t token_first;
    uint32_t token_count;
    mlui_content_ref content;
    uint32_t paint_first;
    uint32_t paint_count;
    mlui_state state;
} mlui_program_op;

typedef mlui_program_op mlui_auth_node;

typedef struct mlui_auth_buffer {
    mlui_auth_node *nodes;
    size_t n_node;
    size_t cap_node;
    uint32_t *children;
    size_t n_child;
    size_t cap_child;
    mlui_style_token_buffer styles;
} mlui_auth_buffer;

typedef struct mlui_compose_node {
    mlui_id id;
    uint8_t kind;
    mlui_id scroll_id;
    uint8_t scroll_axis;
    uint32_t first_child;
    uint32_t n_child;
    mlui_node_ref raw_auth;
    uint32_t style_first;
    uint32_t style_count;
    uint32_t header_style_first;
    uint32_t header_style_count;
    uint32_t body_style_first;
    uint32_t body_style_count;
    uint32_t footer_style_first;
    uint32_t footer_style_count;
} mlui_compose_node;

typedef struct mlui_compose_buffer {
    mlui_compose_node *nodes;
    size_t n_node;
    size_t cap_node;
    uint32_t *children;
    size_t n_child;
    size_t cap_child;
    mlui_style_token_buffer styles;
} mlui_compose_buffer;

typedef struct mlui_paint_stroke {
    mlui_color color;
    double width;
} mlui_paint_stroke;

typedef struct mlui_paint_fill {
    uint8_t kind;
    mlui_color color;
} mlui_paint_fill;

typedef struct mlui_paint_vertex {
    double x;
    double y;
    double u;
    double v;
} mlui_paint_vertex;

typedef struct mlui_paint_program {
    uint8_t kind;
    uint8_t mode;
    mlui_rect rect;
    mlui_paint_stroke stroke;
    mlui_paint_fill fill;
    mlui_image_ref image;
    mlui_color tint;
    double opacity;
    uint32_t point_first;
    uint32_t point_count;
    uint32_t vertex_first;
    uint32_t vertex_count;
    uint32_t segments;
} mlui_paint_program;

typedef struct mlui_paint_store {
    mlui_paint_program *programs;
    size_t n_program;
    size_t cap_program;
    double *points;
    size_t n_point;
    size_t cap_point;
    mlui_paint_vertex *vertices;
    size_t n_vertex;
    size_t cap_vertex;
} mlui_paint_store;

typedef struct mlui_program {
    mlui_program_header header;
    mlui_auth_buffer *auth;
    mlui_compose_buffer *compose;
    mlui_paint_store *paint;
    mlui_content_ref *content_refs;
    size_t n_content;
    mlui_image_ref *image_refs;
    size_t n_image;
    mlui_font_ref *font_refs;
    size_t n_font;
    mlui_value_ref *value_refs;
    size_t n_value;
} mlui_program;

typedef struct mlui_view_op {
    uint8_t kind;
    mlui_id id;
    mlui_rect rect;
    mlui_id other_id;
    uint32_t first;
    uint32_t count;
    uint8_t axis;
    uint8_t role;
    uint8_t policy;
    uint8_t cursor;
    uint8_t layer_kind;
    uint8_t placement;
    uint8_t flags;
    double order;
    double dx;
    double dy;
    double content_w;
    double content_h;
} mlui_view_op;

typedef struct mlui_raw_input {
    uint8_t kind;
    uint8_t button;
    uint32_t key;
    uint32_t mods;
    uint8_t direction;
    mlui_bool repeat_;
    double x;
    double y;
    double dx;
    double dy;
    mlui_view_u8 text;
    uint32_t text_start;
    uint32_t text_length;
} mlui_raw_input;

typedef struct mlui_event {
    uint8_t kind;
    mlui_id id;
    mlui_id other;
    double x;
    double y;
    int64_t a;
    mlui_view_u8 text;
} mlui_event;

typedef struct mlui_hit_box {
    mlui_id id;
    mlui_rect rect;
} mlui_hit_box;

typedef struct mlui_focus_box {
    mlui_id id;
    uint32_t slot;
    mlui_rect rect;
} mlui_focus_box;

typedef struct mlui_scroll_box {
    mlui_id id;
    uint8_t axis;
    mlui_rect viewport;
    double content_w;
    double content_h;
    double max_x;
    double max_y;
} mlui_scroll_box;

typedef struct mlui_layer_box {
    mlui_id id;
    uint8_t kind;
    double order;
    mlui_rect rect;
} mlui_layer_box;

typedef struct mlui_overlay_box {
    mlui_id id;
    mlui_id anchor_id;
    uint8_t placement;
    mlui_bool modal;
    mlui_rect rect;
} mlui_overlay_box;

typedef struct mlui_focus_scope_box {
    mlui_id id;
    uint8_t policy;
    uint32_t first_slot;
    uint32_t last_slot;
} mlui_focus_scope_box;

typedef mlui_hit_box mlui_drag_source_box;
typedef mlui_hit_box mlui_drop_target_box;
typedef mlui_hit_box mlui_drop_slot_box;
typedef mlui_hit_box mlui_modal_barrier_box;

typedef struct mlui_report {
    mlui_id hover_id;
    mlui_id cursor_id;
    uint8_t cursor;
    mlui_id scroll_id;
    mlui_hit_box *hits;
    size_t n_hit;
    mlui_focus_box *focusables;
    size_t n_focus;
    mlui_scroll_box *scrollables;
    size_t n_scroll;
    mlui_drag_source_box *drag_sources;
    size_t n_drag_source;
    mlui_drop_target_box *drop_targets;
    size_t n_drop_target;
    mlui_drop_slot_box *drop_slots;
    size_t n_drop_slot;
    mlui_hit_box *hit_stack;
    size_t n_hit_stack;
    mlui_layer_box *layers;
    size_t n_layer;
    mlui_overlay_box *overlays;
    size_t n_overlay;
    mlui_modal_barrier_box *modal_barriers;
    size_t n_modal_barrier;
    mlui_focus_scope_box *focus_scopes;
    size_t n_focus_scope;
} mlui_report;

MLUI_API uint32_t mlui_abi_version(void);
MLUI_API int32_t mlui_kernel_init(mlui_kernel **out_kernel);
MLUI_API mlui_status mlui_kernel_init_ex(const mlui_kernel_config *config, mlui_kernel **out_kernel);
MLUI_API int32_t mlui_kernel_close(mlui_kernel *kernel);
MLUI_API mlui_status mlui_kernel_reset_frame(mlui_kernel *kernel);
MLUI_API mlui_status mlui_import_auth_buffer(mlui_kernel *kernel, const mlui_auth_buffer *auth, mlui_node_ref *out_root);
MLUI_API mlui_status mlui_load_program(mlui_kernel *kernel, const mlui_program *program, mlui_node_ref *out_root);
MLUI_API mlui_status mlui_validate_program(mlui_kernel *kernel, const mlui_program *program);
MLUI_API int32_t mlui_lower_solve_render(mlui_kernel *kernel, double env_w, double env_h);
MLUI_API mlui_status mlui_frame(mlui_kernel *kernel, mlui_node_ref root, double env_w, double env_h, const mlui_raw_input *raw);
MLUI_API int32_t mlui_runtime_report(mlui_kernel *kernel);
MLUI_API int32_t mlui_interact_step(mlui_kernel *kernel, const mlui_raw_input *raw);
MLUI_API int32_t mlui_view_ops(mlui_kernel *kernel, const mlui_view_op **out_ops, size_t *out_n);
MLUI_API int32_t mlui_events(mlui_kernel *kernel, const mlui_event **out_events, size_t *out_n);
MLUI_API mlui_status mlui_report_get(mlui_kernel *kernel, const mlui_report **out_report);
MLUI_API mlui_status mlui_clear_events(mlui_kernel *kernel);

#ifdef __cplusplus
}
#endif

#endif
