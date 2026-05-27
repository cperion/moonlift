local n = tonumber(arg[1]) or 5000000
local function fib(x)
  if x <= 1 then return x end
  return fib(x-1) + fib(x-2)
end
print(fib(40))
