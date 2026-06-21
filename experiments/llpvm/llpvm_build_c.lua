-- llpvm_build_c.lua -- Build the LLPVM C artifact through the executed .mlua API.
--
-- LLPVM modules use moon.require, so the C backend boundary is the artifact
-- API. The artifact owns generated implementation C, generated header C, and
-- explicit support C that can be written as one includable/compilable blob.

package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;experiments/llpvm/?.lua;experiments/llpvm/?.mlua;" .. package.path

local moon = require("moonlift")

local M = {}

local LLPVM_SUPPORT_SOURCE = [[
#include <stdint.h>
#include <stddef.h>
#include <stdlib.h>

#ifndef LLPVM_MAX_VMS
#define LLPVM_MAX_VMS 64u
#endif

#define LLPVM_SLOT_BITS 16u
#define LLPVM_GEN_MASK ((1u << LLPVM_SLOT_BITS) - 1u)

static void *g_llpvm_vm_slots[LLPVM_MAX_VMS];
static uint32_t g_llpvm_vm_gens[LLPVM_MAX_VMS];

void *default_malloc(int64_t size)
{
    return malloc((size_t)size);
}

void *default_realloc(void *ptr, int64_t new_size)
{
    return realloc(ptr, (size_t)new_size);
}

void default_free(void *ptr)
{
    free(ptr);
}

uint32_t llpvm_vm_register(void *vm)
{
    if (!vm) return 0u;
    for (uint32_t slot = 0; slot < LLPVM_MAX_VMS; slot++) {
        if (!g_llpvm_vm_slots[slot]) {
            uint32_t gen = (g_llpvm_vm_gens[slot] + 1u) & LLPVM_GEN_MASK;
            if (gen == 0u) gen = 1u;
            g_llpvm_vm_gens[slot] = gen;
            g_llpvm_vm_slots[slot] = vm;
            return (slot << LLPVM_SLOT_BITS) | gen;
        }
    }
    return 0u;
}

void *llpvm_vm_get(uint32_t vm)
{
    uint32_t slot = vm >> LLPVM_SLOT_BITS;
    uint32_t gen = vm & LLPVM_GEN_MASK;
    if (vm == 0u) return NULL;
    if (slot >= LLPVM_MAX_VMS) return NULL;
    if (gen == 0u) return NULL;
    if (g_llpvm_vm_gens[slot] != gen) return NULL;
    return g_llpvm_vm_slots[slot];
}

void llpvm_vm_unregister(uint32_t vm)
{
    uint32_t slot = vm >> LLPVM_SLOT_BITS;
    uint32_t gen = vm & LLPVM_GEN_MASK;
    if (vm == 0u) return;
    if (slot >= LLPVM_MAX_VMS) return;
    if (gen == 0u) return;
    if (g_llpvm_vm_gens[slot] != gen) return;
    g_llpvm_vm_slots[slot] = NULL;
}
]]

local function shell_quote(s)
    return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

function M.emit_artifact(opts)
    opts = opts or {}
    local emit_opts = {}
    for k, v in pairs(opts) do emit_opts[k] = v end
    emit_opts.site = emit_opts.site or "llpvm C blob"
    emit_opts.support_source = emit_opts.support_source or LLPVM_SUPPORT_SOURCE
    return moon.emit_c_file_artifact("experiments/llpvm/llpvm_abi.mlua", opts.name or "llpvm", emit_opts)
end

function M.write_artifact(path, opts)
    path = path or "experiments/llpvm/llpvm_amalgam.c"
    opts = opts or {}
    local artifact = M.emit_artifact(opts)
    local write_opts = {
        combined_path = path,
        h_path = opts.h_path or "experiments/llpvm/llpvm_amalgam.h",
    }
    artifact:write(write_opts)
    return artifact.combined, path, artifact
end

function M.compile_object(opts)
    opts = opts or {}
    local c_path = opts.c_path or "experiments/llpvm/llpvm_amalgam.c"
    local o_path = opts.o_path or "experiments/llpvm/llpvm_amalgam.o"
    local cc = opts.cc or os.getenv("CC") or "gcc"
    local cflags = opts.cflags or "-O3 -std=c99 -Iexperiments/llpvm"
    local cmd1 = table.concat({ cc, cflags, "-c", shell_quote(c_path), "-o", shell_quote(o_path) }, " ")
    local ok1 = os.execute(cmd1)
    assert(ok1 == true or ok1 == 0, "C compile failed: " .. cmd1)
    return o_path
end

function M.compile_shared(opts)
    opts = opts or {}
    local c_path = opts.c_path or "experiments/llpvm/llpvm_amalgam.c"
    local so_path = opts.so_path or "experiments/llpvm/llpvm_amalgam.so"
    local cc = opts.cc or os.getenv("CC") or "gcc"
    local cflags = opts.cflags or "-O3 -std=c99 -fPIC -shared -Iexperiments/llpvm"
    local cmd = table.concat({ cc, cflags, shell_quote(c_path), "-o", shell_quote(so_path) }, " ")
    local ok = os.execute(cmd)
    assert(ok == true or ok == 0, "C shared compile failed: " .. cmd)
    return so_path
end

function M.build(opts)
    opts = opts or {}
    local src, c_path, artifact = M.write_artifact(opts.c_path, opts)
    local o_path
    if opts.compile ~= false then
        o_path = M.compile_object({
            c_path = c_path,
            o_path = opts.o_path,
            cc = opts.cc,
            cflags = opts.cflags,
        })
    end
    return {
        c_path = c_path,
        h_path = opts.h_path or "experiments/llpvm/llpvm_amalgam.h",
        o_path = o_path,
        header_bytes = #(artifact.header or ""),
        bytes = #src,
    }
end

function M.build_shared(opts)
    opts = opts or {}
    local src, c_path, artifact = M.write_artifact(opts.c_path, opts)
    local so_path = M.compile_shared({
        c_path = c_path,
        so_path = opts.so_path,
        cc = opts.cc,
        cflags = opts.cflags,
    })
    return {
        c_path = c_path,
        h_path = opts.h_path or "experiments/llpvm/llpvm_amalgam.h",
        so_path = so_path,
        header_bytes = #(artifact.header or ""),
        bytes = #src,
    }
end

if ... == nil then
    local result = M.build({})
    io.write(string.format("LLPVM C: %s (%d bytes)\n", result.c_path, result.bytes))
    io.write("LLPVM header: " .. result.h_path .. "\n")
    if result.o_path then io.write("LLPVM object: " .. result.o_path .. "\n") end
end

return M
