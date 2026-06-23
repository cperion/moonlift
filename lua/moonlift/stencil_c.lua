local pvm = require("moonlift.pvm")

local function sanitize(s)
    s = tostring(s or "x"):gsub("[^%w_]", "_")
    if s == "" then s = "x" end
    if s:match("^%d") then s = "_" .. s end
    return s
end

local function bind_context(T)
    T._moonlift_api_cache = T._moonlift_api_cache or {}
    if T._moonlift_api_cache.stencil_c ~= nil then return T._moonlift_api_cache.stencil_c end

    local Core = T.MoonCore
    local Code = T.MoonCode
    local Value = T.MoonValue
    local Kernel = T.MoonKernel
    local Stencil = T.MoonStencil

    local api = {}

    local function type_name(ty)
        local cls = pvm.classof(ty)
        if cls == Code.CodeTyInt then return (ty.signedness == Code.CodeSigned and "i" or "u") .. tostring(ty.bits) end
        if cls == Code.CodeTyFloat then return "f" .. tostring(ty.bits) end
        if ty == Code.CodeTyIndex then return "index" end
        if ty == Code.CodeTyBool8 then return "bool8" end
        return "ty"
    end

    local function c_type(ty)
        local cls = pvm.classof(ty)
        if cls == Code.CodeTyInt then
            local prefix = ty.signedness == Code.CodeSigned and "int" or "uint"
            if ty.bits == 8 or ty.bits == 16 or ty.bits == 32 or ty.bits == 64 then return prefix .. tostring(ty.bits) .. "_t" end
        elseif cls == Code.CodeTyFloat then
            if ty.bits == 32 then return "float" end
            if ty.bits == 64 then return "double" end
        end
        error("stencil_c: unsupported C stencil type", 3)
    end

    local function unsigned_c_type(ty)
        local cls = pvm.classof(ty)
        if cls == Code.CodeTyInt and (ty.bits == 8 or ty.bits == 16 or ty.bits == 32 or ty.bits == 64) then return "uint" .. tostring(ty.bits) .. "_t" end
        return c_type(ty)
    end

    local function reduction_name(kind)
        if kind == Value.ReductionAdd then return "add" end
        if kind == Value.ReductionMul then return "mul" end
        if kind == Value.ReductionAnd then return "and" end
        if kind == Value.ReductionOr then return "or" end
        if kind == Value.ReductionXor then return "xor" end
        if kind == Value.ReductionMin then return "min" end
        if kind == Value.ReductionMax then return "max" end
        return "reduction"
    end

    local function proof_list(plan)
        local eq = plan and plan.body and plan.body.equivalence or nil
        if pvm.classof(eq) == Kernel.KernelEquivalenceProof then return eq.proofs or {} end
        return {}
    end

    local function instance_id(elem_ty, result_ty, reduction, stride)
        return Stencil.StencilInstanceId("stencil:reduce_array:" .. type_name(elem_ty) .. ":" .. reduction_name(reduction) .. ":to:" .. type_name(result_ty) .. ":stride" .. tostring(stride))
    end

    local function symbol_id(elem_ty, result_ty, reduction, stride)
        return Stencil.StencilSymbolId("ml_stencil_reduce_array_" .. type_name(elem_ty) .. "_" .. reduction_name(reduction) .. "_to_" .. type_name(result_ty) .. "_s" .. tostring(stride))
    end

    local function c_decl(symbol, elem_ty, result_ty)
        local elem = c_type(elem_ty)
        local result = c_type(result_ty)
        return result .. " " .. symbol.text .. "(const " .. elem .. " *xs, int32_t start, int32_t stop, " .. result .. " init);"
    end

    function api.reduce_array_artifact(reduction, plan, info)
        local elem_ty = assert(info.elem_ty, "stencil_c.reduce_array_artifact requires elem_ty")
        local result_ty = assert(info.result_ty, "stencil_c.reduce_array_artifact requires result_ty")
        local stride = assert(info.step_num, "stencil_c.reduce_array_artifact requires step_num")
        local id = instance_id(elem_ty, result_ty, reduction.kind, stride)
        local symbol = symbol_id(elem_ty, result_ty, reduction.kind, stride)
        local instance = Stencil.StencilInstance(
            id,
            Stencil.StencilReduceArray,
            Stencil.StencilShapeReduceArray(
                elem_ty,
                result_ty,
                reduction.kind,
                reduction.int_semantics,
                reduction.float_mode,
                reduction.init,
                stride
            ),
            {
                Stencil.StencilParamType("elem_ty", elem_ty),
                Stencil.StencilParamType("result_ty", result_ty),
                Stencil.StencilParamReduction("reduction", reduction.kind),
                Stencil.StencilParamNumber("stride", stride),
                Stencil.StencilParamValueExpr("init", reduction.init),
            },
            Stencil.StencilAbi({ Code.CodeTyDataPtr(elem_ty), Code.CodeTyInt(32, Code.CodeSigned), Code.CodeTyInt(32, Code.CodeSigned), result_ty }, result_ty),
            proof_list(plan)
        )
        return Stencil.StencilArtifact(instance, Stencil.StencilProviderC, symbol, c_decl(symbol, elem_ty, result_ty))
    end

    local function reduce_array_source(artifact)
        local shape = artifact.instance.shape
        local elem_ty, result_ty = shape.elem_ty, shape.result_ty
        local ct = c_type(result_ty)
        local et = c_type(elem_ty)
        local acc_ty = (shape.reduction == Value.ReductionMin or shape.reduction == Value.ReductionMax) and ct or unsigned_c_type(result_ty)
        local stride = tonumber(shape.stride) or 1
        local lines = {}
        lines[#lines + 1] = ct .. " " .. artifact.symbol.text .. "(const " .. et .. " *xs, int32_t start, int32_t stop, " .. ct .. " init) {"
        lines[#lines + 1] = "    " .. acc_ty .. " acc = (" .. acc_ty .. ")init;"
        lines[#lines + 1] = "    for (int32_t i = start; i < stop; i += " .. tostring(stride) .. ") {"
        if shape.reduction == Value.ReductionAdd then
            lines[#lines + 1] = "        acc = (" .. acc_ty .. ")(acc + (" .. acc_ty .. ")xs[i]);"
        elseif shape.reduction == Value.ReductionMul then
            lines[#lines + 1] = "        acc = (" .. acc_ty .. ")(acc * (" .. acc_ty .. ")xs[i]);"
        elseif shape.reduction == Value.ReductionAnd then
            lines[#lines + 1] = "        acc = (" .. acc_ty .. ")(acc & (" .. acc_ty .. ")xs[i]);"
        elseif shape.reduction == Value.ReductionOr then
            lines[#lines + 1] = "        acc = (" .. acc_ty .. ")(acc | (" .. acc_ty .. ")xs[i]);"
        elseif shape.reduction == Value.ReductionXor then
            lines[#lines + 1] = "        acc = (" .. acc_ty .. ")(acc ^ (" .. acc_ty .. ")xs[i]);"
        elseif shape.reduction == Value.ReductionMin then
            lines[#lines + 1] = "        if (xs[i] < acc) acc = xs[i];"
        elseif shape.reduction == Value.ReductionMax then
            lines[#lines + 1] = "        if (xs[i] > acc) acc = xs[i];"
        else
            error("stencil_c: unsupported reduce_array reduction " .. reduction_name(shape.reduction), 3)
        end
        lines[#lines + 1] = "    }"
        lines[#lines + 1] = "    return (" .. ct .. ")acc;"
        lines[#lines + 1] = "}"
        return table.concat(lines, "\n")
    end

    function api.source(artifacts)
        local out = { "#include <stdint.h>" }
        local seen = {}
        for _, artifact in ipairs(artifacts or {}) do
            local key = artifact.symbol.text
            if not seen[key] then
                out[#out + 1] = reduce_array_source(artifact)
                seen[key] = true
            end
        end
        return table.concat(out, "\n\n") .. "\n"
    end

    local function shell_quote(s)
        return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
    end

    local function write_file(path, source)
        local f = assert(io.open(path, "wb"))
        f:write(source)
        f:close()
    end

    function api.compile_artifacts(artifacts, opts)
        opts = opts or {}
        local ffi = require("ffi")
        local dir = opts.dir or "target/stencil"
        os.execute("mkdir -p " .. shell_quote(dir))
        local stem = opts.stem or ("moonlift_stencil_" .. tostring(os.time()) .. "_" .. sanitize(tostring(os.clock())))
        local c_path = dir .. "/" .. stem .. ".c"
        local so_path = dir .. "/" .. stem .. ".so"
        local source = api.source(artifacts)
        write_file(c_path, source)
        local cc = opts.cc or os.getenv("CC") or "gcc"
        local cflags = opts.cflags or "-std=c99 -O3 -march=native -fPIC -shared"
        local cmd = table.concat({ shell_quote(cc), cflags, shell_quote(c_path), "-o", shell_quote(so_path) }, " ")
        local ok = os.execute(cmd)
        if not (ok == true or ok == 0) then return nil, "stencil_c: compile failed: " .. cmd, source end
        local decls = {}
        local seen = {}
        for _, artifact in ipairs(artifacts or {}) do
            if not seen[artifact.symbol.text] then
                decls[#decls + 1] = artifact.c_signature
                seen[artifact.symbol.text] = true
            end
        end
        if #decls > 0 then ffi.cdef(table.concat(decls, "\n")) end
        local lib = ffi.load(so_path)
        local symbols = {}
        for _, artifact in ipairs(artifacts or {}) do symbols[artifact.symbol.text] = lib[artifact.symbol.text] end
        return {
            c_path = c_path,
            so_path = so_path,
            source = source,
            command = cmd,
            symbols = symbols,
        }, nil, source
    end

    T._moonlift_api_cache.stencil_c = api
    return api
end

return bind_context
