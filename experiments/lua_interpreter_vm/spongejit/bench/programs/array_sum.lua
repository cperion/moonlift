local n = tonumber(arg[1]) or 5000000
local t = {}
for i = 1, n do
  t[i] = i * 2
end
local s = 0
for i = 1, n do
  s = s + t[i]
end
print(s)
