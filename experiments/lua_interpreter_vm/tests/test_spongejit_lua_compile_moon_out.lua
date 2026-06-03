#!/usr/bin/env luajit
-- Compatibility entry point for the pre-reset test name. The maintained test is
-- MoonCFG because accepted kernels are MoonCFG.Kernel, not legacy MoonOut.
dofile("experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_moon_cfg.lua")
