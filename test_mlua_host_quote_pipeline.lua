package.path = "./?.lua;./?/init.lua;./moonlift/lua/?.lua;./moonlift/lua/?/init.lua;./moonlift/lua/?.lua;./moonlift/lua/?/init.lua;" .. package.path

local Host = require("moonlift.host_quote")

local translated = Host.translate [[
struct User
    id: i32
    active: bool32
end

expose Users: view(User)

function User:is_active()
    return self.active
end

func User:always(self: ptr(User)) -> bool
    return true
end

local m = module UserKernels
    export func forty_two() -> i32
        return 42
    end
end
return User, Users, m
]]
assert(translated:find("local User = __moonlift_host%.struct_from_source"))
assert(translated:find("local Users = __moonlift_host%.expose_from_source"))
assert(translated:find("User%.always = __moonlift_host%.func_from_source"))
assert(translated:find("__moonlift_host%.module_from_source"))

local User, Users, mod = Host.eval [[
struct User
    id: i32
    active: bool32
end

expose Users: view(User)

function User:is_active()
    return self.active
end

func User:always(self: ptr(User)) -> bool
    return true
end

local m = module UserKernels
    export func forty_two() -> i32
        return 42
    end
end
return User, Users, m
]]

assert(tostring(User) == "MoonliftStructDecl(User)")
assert(type(User.is_active) == "function")
local user_decls = User:host_decl_set()
assert(#user_decls.decls == 3)
assert(user_decls.decls[2].decl.name == "is_active")
assert(user_decls.decls[3].decl.name == "always")
assert(tostring(User.always) == "MoonliftFuncQuote(User_always)")
assert(tostring(Users) == "MoonliftExposeDecl(Users)")
assert(tostring(mod) == "MoonliftModuleQuote")
local runtime, RuntimeUser, RuntimeUsers = Host.eval_with_runtime([[struct RuntimeUser
    id: i32
end
expose RuntimeUsers: view(RuntimeUser)
function RuntimeUser:lua_method()
    return self.id
end
func RuntimeUser:native_method(self: ptr(RuntimeUser)) -> bool
    return true
end
return RuntimeUser, RuntimeUsers]], "runtime_decls")
local runtime_decls = runtime:host_decl_set()
assert(tostring(RuntimeUser) == "MoonliftStructDecl(RuntimeUser)")
assert(tostring(RuntimeUsers) == "MoonliftExposeDecl(RuntimeUsers)")
assert(#runtime_decls.decls == 4)
assert(runtime_decls.decls[3].decl.name == "lua_method")
assert(runtime_decls.decls[4].decl.name == "native_method")
local runtime_pipeline = runtime:host_pipeline_result("runtime_decls")
assert(#runtime_pipeline.report.issues == 0)
assert(#runtime_pipeline.layout_env.layouts == 1)
assert(#runtime_pipeline.lua.cdefs >= 2)
local cm = mod:compile()
assert(cm:get("forty_two")() == 42)
cm:free()

local parsed = Host.parse [[
struct User
    id: i32
    active: bool32
end
expose Users: view(User)
function User:is_active()
    return self.active
end
]]
assert(#parsed.issues == 0, tostring(parsed.issues[1]))
assert(#parsed.decls.decls == 2)

local parsed_module = Host.parse [[
module Math
    export func two() -> i32
        return 2
    end
end
]]
assert(#parsed_module.issues == 0, tostring(parsed_module.issues[1]))
assert(#parsed_module.module.items == 1)
assert(parsed_module.module.items[1].func.name == "two")

print("moonlift mlua host quote pipeline ok")
