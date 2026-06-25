local path = "experiments/mlui/mlui_c_api.h"

local f = assert(io.open(path, "r"))
local src = f:read("*a")
f:close()

local function must(pattern, label)
    assert(src:find(pattern, 1, true), label or pattern)
end

must("#define MLUI_C_API_H", "header guard")
must("MLUI_ABI_VERSION = 1", "ABI version constant")
must("MLUI_MAGIC = 0x4d4c5549u", "magic constant")

must("MLUI_AUTH_EMPTY = 1", "auth opcode empty")
must("MLUI_AUTH_BOX = 3", "auth opcode box")
must("MLUI_AUTH_MODAL = 16", "auth opcode modal")
must("MLUI_COMPOSE_WORKBENCH = 5", "compose opcode workbench")
must("MLUI_PAINT_IMAGE = 8", "paint opcode image")
must("MLUI_VIEW_MODAL_BARRIER = 21", "view opcode modal barrier")
must("MLUI_RAW_CANCEL_INTERACTION = 13", "raw opcode cancel")
must("MLUI_EVENT_SCROLL_BY = 22", "event opcode scroll")

must("typedef struct mlui_program_header", "program header type")
must("typedef struct mlui_program_op", "program op type")
must("typedef struct mlui_program", "program container type")
must("mlui_status mlui_load_program", "program loader declaration")
must("mlui_status mlui_validate_program", "program validator declaration")

local has_cc = os.execute("command -v cc >/dev/null 2>&1")
if has_cc == true or has_cc == 0 then
    local tmp = os.tmpname() .. ".c"
    local tf = assert(io.open(tmp, "w"))
    tf:write('#include "experiments/mlui/mlui_c_api.h"\n')
    tf:write("int main(void) { return MLUI_AUTH_BOX == 3 ? 0 : 1; }\n")
    tf:close()
    local ok = os.execute("cc -I. -fsyntax-only " .. tmp)
    os.remove(tmp)
    assert(ok == true or ok == 0, "mlui_c_api.h should compile as C")
end

print("lalin mlui c api header ok")
