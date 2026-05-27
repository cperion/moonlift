local n = tonumber(arg[1]) or 5000000
local t = { x = 0, y = 1 }
local s = 0
for i = 1, n do
  s = s + t.x + t.y
  t.x = t.x + 1
  t.y = t.y + 1
end
print(s)
