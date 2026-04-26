package.path = "./moonlift/lua/?.lua;./moonlift/lua/?/init.lua;" .. package.path
return dofile("moonlift/lua/moonlift/init.lua")
