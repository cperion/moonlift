-- Lua Interpreter VM — Constants
-- All value tags, opcodes, TM events, frame modes, statuses, error codes, GC state.

local Tag = {}
Tag.NIL = 0
Tag.FALSE = 1
Tag.TRUE = 2
Tag.LIGHTUD = 3
Tag.NUM = 4
Tag.STR = 5
Tag.TABLE = 6
Tag.LCLOSURE = 7
Tag.CCLOSURE = 8
Tag.USERDATA = 9
Tag.THREAD = 10
Tag.PROTO = 11

local Op = {}
Op.MOVE = 0
Op.LOADK = 1
Op.LOADBOOL = 2
Op.LOADNIL = 3
Op.GETUPVAL = 4
Op.GETGLOBAL = 5
Op.GETTABLE = 6
Op.SETGLOBAL = 7
Op.SETUPVAL = 8
Op.SETTABLE = 9
Op.NEWTABLE = 10
Op.SELF = 11
Op.ADD = 12
Op.SUB = 13
Op.MUL = 14
Op.DIV = 15
Op.MOD = 16
Op.POW = 17
Op.UNM = 18
Op.NOT = 19
Op.LEN = 20
Op.CONCAT = 21
Op.JMP = 22
Op.EQ = 23
Op.LT = 24
Op.LE = 25
Op.TEST = 26
Op.TESTSET = 27
Op.CALL = 28
Op.TAILCALL = 29
Op.RETURN = 30
Op.FORLOOP = 31
Op.FORPREP = 32
Op.TFORLOOP = 33
Op.SETLIST = 34
Op.CLOSE = 35
Op.CLOSURE = 36
Op.VARARG = 37
-- Note: Lua 5.1 has 38 opcodes (0..37). The table above has 38 entries.

local TM = {}
TM.INDEX = 0
TM.NEWINDEX = 1
TM.GC = 2
TM.MODE = 3
TM.EQ = 4
TM.ADD = 5
TM.SUB = 6
TM.MUL = 7
TM.DIV = 8
TM.MOD = 9
TM.POW = 10
TM.UNM = 11
TM.LEN = 12
TM.LT = 13
TM.LE = 14
TM.CONCAT = 15
TM.CALL = 16
TM.N = 17

local Resume = {}
Resume.NORMAL = 0
Resume.TAILCALL = 1
Resume.PCALL = 2
Resume.XPCALL = 3
Resume.GETTABLE_MM = 4
Resume.SETTABLE_MM = 5
Resume.BINOP_MM = 6
Resume.UNOP_MM = 7
Resume.LEN_MM = 8
Resume.CONCAT_MM = 9
Resume.EQ_MM = 10
Resume.LT_MM = 11
Resume.LE_MM = 12
Resume.CALL_MM = 13
Resume.TFORLOOP_CALL = 14
Resume.NATIVE_CONT = 15

local Status = {}
Status.OK = 0
Status.YIELDED = 1
Status.RUNTIME_ERROR = 2
Status.OOM = 3
Status.DEAD = 4

local Err = {}
Err.NONE = 0
Err.RUNTIME = 1
Err.SYNTAX = 2
Err.MEMORY = 3
Err.HANDLER = 4
Err.YIELD = 5
Err.BAD_OPCODE = 6
Err.STACK_OVERFLOW = 7
Err.C_STACK_OVERFLOW = 8
Err.TYPE = 9
Err.ARITH = 10
Err.COMPARE = 11
Err.CONCAT = 12
Err.INDEX = 13
Err.CALL = 14
Err.LOOP = 15
Err.API = 16

local GCColor = {}
GCColor.WHITE0 = 0
GCColor.WHITE1 = 1
GCColor.GRAY = 2
GCColor.BLACK = 3

local GCState = {}
GCState.PAUSE = 0
GCState.PROPAGATE = 1
GCState.SWEEP = 2
GCState.FINALIZE = 3

local MAX_STACK_SIZE = 1000000
local MAX_FRAMES = 1000

return {
    Tag = Tag,
    Op = Op,
    TM = TM,
    Resume = Resume,
    Status = Status,
    Err = Err,
    GCColor = GCColor,
    GCState = GCState,
    MAX_STACK_SIZE = MAX_STACK_SIZE,
    MAX_FRAMES = MAX_FRAMES,
}
