-- Test basic control region lowering via CLI mom run.
-- Path to mom binary (adjust if needed)
local mom_bin = "./target/release/mom"

local src = [[
func main(): i32
    return block loop(i: i32 = 0, acc: i32 = 0)
        if i >= 4 then yield acc end
        jump loop(i = i + 1, acc = acc + 1)
    end
end
]]

-- Write source to temp file
local tmpfile = os.tmpname() .. ".mlua"
local f = io.open(tmpfile, "w")
f:write(src)
f:close()

-- Run mom and capture output
local cmd = mom_bin .. " run --call main " .. tmpfile
local h = io.popen(cmd, "r")
local output = h:read("*a")
local ok_close, _, exit_code = h:close()

os.remove(tmpfile)

if exit_code ~= 0 or (ok_close ~= nil and not ok_close) then
    io.stderr:write("FAIL: mom run exited with code ", tostring(exit_code), "\n")
    io.stderr:write(output)
    os.exit(1)
end

local result = tonumber(output:match("%d+"))
if result ~= 4 then
    io.stderr:write("FAIL: expected 4, got ", tostring(result), "\n")
    os.exit(1)
end
print("PASS: test_mom_control_lower -- result = " .. tostring(result))
