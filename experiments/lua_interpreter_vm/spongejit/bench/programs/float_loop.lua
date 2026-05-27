local n = tonumber(arg[1]) or 50000000
local s = 0.0
for i = 1, n do
  s = s + i * 1.5
end
print(string.format("%.0f", s))
