local n = tonumber(arg[1]) or 10000000
local a, b, c, d, e = 3, 0, 0, 1, 0
for i = 1, n do
  b = -a
  c = ~b
  d = d * d
  e = d + 1
end
print(e)
