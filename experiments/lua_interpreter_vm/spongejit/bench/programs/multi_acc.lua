local n = tonumber(arg[1]) or 50000000
local s = 0
local a, b, c, d = 1, 2, 3, 4
for i = 1, n do
  s = s + a + b + c + d
  a = a + 1
  b = b + 1
  c = c + 1
  d = d + 1
end
print(s)
