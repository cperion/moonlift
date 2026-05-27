local n = tonumber(arg[1]) or 50000000
local s = 0
for i = 1, n do
  s = s + i
  if s > 1e15 then s = 0 end
end
print(s)
