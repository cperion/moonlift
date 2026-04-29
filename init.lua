package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path
return dofile("lua/moonlift/init.lua")
