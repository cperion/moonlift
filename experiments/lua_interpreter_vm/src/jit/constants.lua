-- Moonlift Lua VM JIT — constants for product fields.
--
-- Plain tables are acceptable here because they feed Moonlift product/machine
-- construction; they are not hidden runtime semantics.

local ExecutionStatus = {
    OK = 0,
    SIDE_EXIT = 1,
    RETURN = 2,
    ERROR = 3,
    CALL_BOUNDARY = 4,
    RUNTIME_BOUNDARY = 5,
}

local Effect = {
    PURE = 0x00000000,
    MAY_BRANCH = 0x00000001,
    MAY_THROW = 0x00000002,
    MAY_ALLOC = 0x00000004,
    MAY_GC = 0x00000008,
    MAY_CALL_LUA = 0x00000010,
    MAY_YIELD = 0x00000020,
    MAY_RUN_HOOK = 0x00000040,
    MAY_CALL_METAMETHOD = 0x00000080,
    MAY_OBSERVE_STACK = 0x00000100,
    MAY_READ_MUTABLE_HEAP = 0x00000200,
    MAY_WRITE_HEAP = 0x00000400,
    MAY_NEED_BARRIER = 0x00000800,
    MAY_INVALIDATE_DEPS = 0x00001000,
}

local ProjectionKind = {
    INTERPRETER = 1,
    ROOTS = 2,
    RESUME = 3,
    DEBUG = 4,
    ERROR = 5,
    BARRIER = 6,
    TARGET = 7,
}

local ProjectionReq = {
    NONE = 0x00,
    INTERPRETER = 0x01,
    ROOTS = 0x02,
    RESUME = 0x04,
    DEBUG = 0x08,
    ERROR = 0x10,
    BARRIER = 0x20,
    TARGET = 0x40,
}

local BoundaryReq = {
    NONE = 0x00,
    HELPER = 0x01,
    ALLOCATOR = 0x02,
    GC_SAFEPOINT = 0x04,
    LUA_CALL = 0x08,
    NATIVE_CALL = 0x10,
    METAMETHOD = 0x20,
    VM_RETURN = 0x40,
}

local RangeShape = {
    BLOCK = 1,
    LOOP = 2,
    TRACE = 3,
    CALL_ENTRY = 4,
    RESUME = 5,
}

local TraceAnchorKind = {
    LOOP = 1,
    SIDE_EXIT = 2,
    BRANCH_TARGET = 3,
    CALL_TARGET = 4,
}

local TraceStatus = {
    COLD = 0,
    RECORDING = 1,
    COMPLETE = 2,
    BLACKLISTED = 3,
}

local TraceSelectStatus = {
    OK = 0,
    EMPTY = 1,
    NO_STENCIL = 2,
    INVALID = 3,
}

local StencilKind = {
    PRIMITIVE = 1,
    COMPOUND = 2,
    PROJECTION = 3,
    BOUNDARY = 4,
    EDGE = 5,
}

local RewriteKind = {
    DCE = 1,
    REDUNDANT_GUARD = 2,
    FUSE = 3,
    BUNDLE_PROJECTION = 4,
    FALLTHROUGH = 5,
}

local ReplacementKind = {
    EMPTY = 0,
    CODE_STENCIL = 1,
    NODE_SEQUENCE = 2,
}

return {
    ExecutionStatus = ExecutionStatus,
    Effect = Effect,
    ProjectionKind = ProjectionKind,
    ProjectionReq = ProjectionReq,
    BoundaryReq = BoundaryReq,
    RangeShape = RangeShape,
    TraceAnchorKind = TraceAnchorKind,
    TraceStatus = TraceStatus,
    TraceSelectStatus = TraceSelectStatus,
    StencilKind = StencilKind,
    RewriteKind = RewriteKind,
    ReplacementKind = ReplacementKind,
}
