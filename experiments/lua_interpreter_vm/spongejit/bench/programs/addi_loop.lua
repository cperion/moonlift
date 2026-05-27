local n = tonumber(arg[1]) or 50000000
local s = 0
for i = 1, n do
  s = s + 1  -- ADDI: constant add, hits our stencil cache
end
print(s)
