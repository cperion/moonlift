package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local moon = require("moonlift.host")

local H = moon.T.Moon2Host
local issue = H.HostIssueDuplicateType("Demo", "Pair")
local report = moon.host_report({ issue })
assert(pvm.classof(report) == H.HostReport)
assert(#report.issues == 1)
assert(report.issues[1] == issue)
assert(moon.host_issue_to_string(issue):match("duplicate type"))

local M = moon.module("IssueDemo")
M:struct("Pair", {})
local ok, err = pcall(function() M:struct("Pair", {}) end)
assert(not ok and tostring(err):match("duplicate type"))

local frag = moon.region_frag("needs_out", {}, { out = moon.cont({}) }, function(r)
    r:entry("start", {}, function(start) start:jump(r.conts.out, {}) end)
end)
local M2 = moon.module("IssueRegion")
local ok2, err2 = pcall(function()
    M2:export_func("f", {}, moon.i32, function(fn)
        fn:return_region(moon.i32, function(r)
            r:entry("start", {}, function(start)
                start:emit(frag, {}, {})
            end)
        end)
    end)
end)
assert(not ok2 and tostring(err2):match("missing continuation fill"))

print("moonlift host issue values ok")
