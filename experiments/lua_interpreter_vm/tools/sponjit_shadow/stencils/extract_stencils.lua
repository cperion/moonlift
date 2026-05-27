#!/usr/bin/env luajit
-- extract_stencils.lua — Compile stencils.c with GCC, extract .text bytes
-- and relocation records, produce stencil_library.json for the foundry.
--
-- Usage:
--   luajit extract_stencils.lua [--cc gcc] [--cflags "-O2 -fPIC"] \
--     stencils/src/stencils.c stencils/stencil_library.json

local source = debug.getinfo(1, "S").source
local base = source and source:sub(1, 1) == "@" and source:sub(2):match("^(.*)/tools/sponjit_shadow/") or "."
local root = base or "."
-- root is experiments/lua_interpreter_vm
-- repo root is two levels up from root
local repo_root = root .. "/../.."

package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. repo_root .. "/?.lua;" .. repo_root .. "/?/init.lua;" .. repo_root .. "/lua/?.lua;" .. package.path

local function bytes_to_hex(s)
    local out = {}
    for i = 1, #s do out[#out + 1] = string.format("%02x", s:byte(i)) end
    return table.concat(out, " ")
end

local ElfParser = require("experiments.lua_interpreter_vm.src.jit.elf_parser")
local Util = require("experiments.lua_interpreter_vm.tools.jit_harness.util")

local function shell(cmd)
    local p = io.popen(cmd .. " 2>&1", "r")
    if not p then return nil, "popen failed" end
    local out = p:read("*a")
    local ok, _, code = p:close()
    if ok then return out end
    return nil, (out or "") .. " exit=" .. tostring(code)
end

local function parse_args(argv)
    local opts = { cc = "gcc", cflags = "-O2 -fomit-frame-pointer -fPIC" }
    local positional = {}
    local i = 1
    argv = argv or arg or {}
    while i <= #argv do
        local a = argv[i]
        if a == "--cc" then opts.cc = argv[i + 1]; i = i + 1
        elseif a == "--cflags" then opts.cflags = argv[i + 1]; i = i + 1
        elseif a:sub(1, 1) ~= "-" then positional[#positional + 1] = a
        end
        i = i + 1
    end
    return opts, positional
end

local function main()
    local opts, args = parse_args(arg or {})
    local src = args[1] or "experiments/lua_interpreter_vm/tools/sponjit_shadow/stencils/src/stencils.c"
    local out_json = args[2] or "experiments/lua_interpreter_vm/tools/sponjit_shadow/stencils/stencil_library.json"
    local out_dir = Util.dirname(out_json)

    Util.mkdir_p(out_dir)

    local obj = out_dir .. "/stencils.o"
    local cmd = string.format("%s %s -c %s -o %s", opts.cc, opts.cflags, Util.shell_quote(src), Util.shell_quote(obj))
    print("[extract] " .. cmd)
    local compile_out, compile_err = shell(cmd)
    if compile_err then
        print("[extract] compile failed: " .. tostring(compile_err))
        if compile_out then print(compile_out) end
        os.exit(1)
    end

    local bytes = assert(Util.read_file(obj), "could not read " .. obj)
    local elf, err = ElfParser.parse(bytes)
    if not elf then
        print("[extract] ELF parse failed: " .. tostring(err))
        -- Fallback: try objdump
        local dis = shell(string.format("objdump -d -r %s", Util.shell_quote(obj)))
        print(dis)
        os.exit(1)
    end

    -- Map each stencil function to its bytes + relocations
    local stencils = {}
    local prefix = "stencil_"
    for _, fn in ipairs(elf.functions or {}) do
        local name = fn.name
        if name and name:sub(1, #prefix) == prefix then
            local holes = {}
            for _, reloc in ipairs(fn.relocations or {}) do
                local sym = reloc.sym_name or ""
                if sym:match("^hole_") then
                    -- Map relocation symbol to hole kind
                    local hole_kind_map = {
                        hole_slot_offset = "slot_offset",
                        hole_field_offset = "field_offset",
                        hole_array_base = "array_base",
                        hole_const_idx = "const_idx",
                        hole_shape_id = "shape_id",
                        hole_call_target = "call_target",
                        hole_barrier_color = "barrier_color",
                        hole_target_pc = "target_pc",
                        hole_exit_addr = "exit_addr",
                        hole_resume_pc = "resume_pc",
                        hole_immediate_i64 = "immediate_i64",
                        hole_index_scale = "index_scale",
                    }
                    holes[#holes + 1] = {
                        offset = reloc.offset or 0,
                        size = reloc.type:match("32") and 4 or 8,
                        kind = hole_kind_map[sym] or sym,
                    }
                end
            end

            stencils[name] = {
                name = name,
                bytes_hex = bytes_to_hex(fn.bytes or ""),
                size = #(fn.bytes or ""),
                holes = holes,
                cost = math.max(1, #(fn.bytes or "")),  -- crude: ~1 cycle per byte for simple stencils
            }
        end
    end

    local library = {
        generated_at = os.date("!%Y-%m-%dT%H:%M:%SZ"),
        cc = opts.cc,
        cflags = opts.cflags,
        source_file = src,
        stencils = stencils,
        stencil_count = 0,
    }
    -- Count
    for _ in pairs(stencils) do library.stencil_count = library.stencil_count + 1 end

    Util.write_json(out_json, library)
    print(string.format("[extract] wrote %s (%d stencils, %s bytes)",
        out_json, library.stencil_count, tostring(#Util.to_json(library))))
end

if arg and arg[0] and tostring(arg[0]):match("extract_stencils") then
    main()
end

return { main = main }
