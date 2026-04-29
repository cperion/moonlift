local pvm = require("moonlift.pvm")

local M = {}

function M.Define(T)
    T._moonlift_api_cache = T._moonlift_api_cache or {}
    if T._moonlift_api_cache.type_func_abi_plan ~= nil then return T._moonlift_api_cache.type_func_abi_plan end

    local C = T.MoonCore
    local Ty = T.MoonType
    local B = T.MoonBind
    local Back = T.MoonBack

    local scalar_api = require("moonlift.type_to_back_scalar").Define(T)

    local function arg_binding_for_param(func_name, param, index)
        return B.Binding(C.Id("arg:" .. func_name .. ":" .. param.name), param.name, param.ty, B.BindingClassArg(index - 1))
    end

    local function back_scalar(ty)
        local r = scalar_api.result(ty)
        if pvm.classof(r) == Ty.TypeBackScalarKnown then return r.scalar end
        return nil
    end

    local function param_plan(func_name, param, index)
        local binding = arg_binding_for_param(func_name, param, index)
        if pvm.classof(param.ty) == Ty.TView then
            return Ty.AbiParamView(
                param.name,
                binding,
                Back.BackValId("arg:" .. func_name .. ":" .. param.name .. ":data"),
                Back.BackValId("arg:" .. func_name .. ":" .. param.name .. ":len"),
                Back.BackValId("arg:" .. func_name .. ":" .. param.name .. ":stride")
            )
        end
        local scalar = back_scalar(param.ty)
        if scalar ~= nil and scalar ~= Back.BackVoid then
            return Ty.AbiParamScalar(param.name, binding, scalar, Back.BackValId("arg:" .. func_name .. ":" .. param.name))
        end
        return Ty.AbiParamRejected(param.name, param.ty, "parameter type has no direct executable ABI yet")
    end

    local function result_plan(func_name, result_ty)
        if pvm.classof(result_ty) == Ty.TScalar and result_ty.scalar == C.ScalarVoid then return Ty.AbiResultVoid end
        if pvm.classof(result_ty) == Ty.TView then return Ty.AbiResultView(result_ty.elem, Back.BackValId("arg:" .. func_name .. ":return:out")) end
        local scalar = back_scalar(result_ty)
        if scalar ~= nil then return Ty.AbiResultScalar(scalar) end
        return Ty.AbiResultRejected(result_ty, "result type has no direct executable ABI yet")
    end

    local function func_plan(func_name, params, result_ty)
        local plans = {}
        for i = 1, #(params or {}) do
            plans[#plans + 1] = param_plan(func_name, params[i], i)
        end
        return Ty.FuncAbiPlan(func_name, plans, result_plan(func_name, result_ty))
    end

    local api = {
        param_plan = param_plan,
        result_plan = result_plan,
        func_plan = func_plan,
        plan = func_plan,
        arg_binding_for_param = arg_binding_for_param,
    }
    T._moonlift_api_cache.type_func_abi_plan = api
    return api
end

return M
