local pvm = require("lalin.pvm")
local bit = require("bit")

local function stable_hash32(s)
    local h = 2166136261
    for i = 1, #s do h = (bit.bxor(h, s:byte(i)) * 16777619) % 4294967296 end
    return string.format("%08x", h)
end

local function stable_repr(v, seen)
    local tv = type(v)
    if tv == "nil" then return "nil" end
    if tv == "boolean" or tv == "number" then return tostring(v) end
    if tv == "string" then return string.format("%q", v) end
    if tv ~= "table" then return tv .. ":" .. tostring(v) end
    local cls = pvm.classof(v)
    if tostring(cls) == "Class(LalinCode.CodeValueId)" then return tostring(cls) .. "{_}" end
    seen = seen or {}
    if seen[v] then return "<cycle>" end
    seen[v] = true
    local out = {}
    if cls and cls.__fields then
        out[#out + 1] = tostring(cls)
        out[#out + 1] = "{"
        for i, field in ipairs(cls.__fields or {}) do
            if i > 1 then out[#out + 1] = "," end
            out[#out + 1] = field.name
            out[#out + 1] = "="
            out[#out + 1] = stable_repr(rawget(v, field.name), seen)
        end
        out[#out + 1] = "}"
    else
        local keys = {}
        for key in pairs(v) do keys[#keys + 1] = key end
        table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
        out[#out + 1] = "{"
        for i, key in ipairs(keys) do
            if i > 1 then out[#out + 1] = "," end
            out[#out + 1] = stable_repr(key, seen)
            out[#out + 1] = "="
            out[#out + 1] = stable_repr(v[key], seen)
        end
        out[#out + 1] = "}"
    end
    seen[v] = nil
    return table.concat(out)
end

local function bind_context(T)
    T._lalin_api_cache = T._lalin_api_cache or {}
    if T._lalin_api_cache.stencil_metastencil ~= nil then return T._lalin_api_cache.stencil_metastencil end

    local Stencil = T.LalinStencil
    local Plan = require("lalin.stencil_artifact_plan")(T)

    local api = {}

    local function same_value(a, b)
        return stable_repr(a) == stable_repr(b)
    end

    local function node_id(id)
        if pvm.classof(id) == Stencil.StencilMetastencilNodeId then return id end
        return Stencil.StencilMetastencilNodeId(id)
    end

    local function wire_id(id)
        if pvm.classof(id) == Stencil.StencilMetastencilWireId then return id end
        return Stencil.StencilMetastencilWireId(id)
    end

    local function meta_id(id)
        if pvm.classof(id) == Stencil.StencilMetastencilId then return id end
        return Stencil.StencilMetastencilId(id)
    end

    local function port_ref(node, name)
        if node ~= nil then node = node_id(node) end
        return Stencil.StencilMetastencilPortRef(node, name)
    end

    local function port_key(ref)
        return (ref.node and ref.node.text or "$external") .. ":" .. ref.name
    end

    local function port(node, name, flow, ty, access)
        return Stencil.StencilMetastencilPort(
            port_ref(node, name),
            flow,
            ty,
            access and Stencil.StencilAccessRef(access) or nil
        )
    end

    local function access_port_flow(role)
        if role == Stencil.StencilAccessRead or role == Stencil.StencilAccessIndex then return Stencil.StencilMetastencilPortInput end
        if role == Stencil.StencilAccessWrite
            or role == Stencil.StencilAccessReduce
            or role == Stencil.StencilAccessControlResult then return Stencil.StencilMetastencilPortOutput end
        if role == Stencil.StencilAccessReadWrite then return Stencil.StencilMetastencilPortInOut end
        return Stencil.StencilMetastencilPortInput
    end

    local function node_from_artifact(id, artifact)
        id = node_id(id)
        local inputs, outputs = {}, {}
        for _, access in ipairs(Plan.descriptor_accesses(artifact.instance.descriptor)) do
            local flow = access_port_flow(access.role)
            local p = port(id, access.name, flow, access.ty, access.name)
            if flow == Stencil.StencilMetastencilPortInput then
                inputs[#inputs + 1] = p
            elseif flow == Stencil.StencilMetastencilPortOutput then
                outputs[#outputs + 1] = p
            else
                inputs[#inputs + 1] = p
                outputs[#outputs + 1] = p
            end
        end
        return Stencil.StencilMetastencilNode(id, artifact, inputs, outputs)
    end

    local function wire(id, src_node, src_name, dst_node, dst_name, ty)
        return Stencil.StencilMetastencilWire(wire_id(id), port_ref(src_node, src_name), port_ref(dst_node, dst_name), ty)
    end

    local function build_port_map(external_ports, nodes)
        local ports = {}
        for _, p in ipairs(external_ports or {}) do ports[port_key(p.ref)] = p end
        for _, node in ipairs(nodes or {}) do
            for _, p in ipairs(node.inputs or {}) do ports[port_key(p.ref)] = p end
            for _, p in ipairs(node.outputs or {}) do ports[port_key(p.ref)] = p end
        end
        return ports
    end

    local function append_same_domain_fact_or_reject(facts, rejects, wire0, nodes_by_id)
        local src_node = wire0.src.node and nodes_by_id[wire0.src.node.text] or nil
        local dst_node = wire0.dst.node and nodes_by_id[wire0.dst.node.text] or nil
        if src_node == nil or dst_node == nil or src_node == dst_node then return end
        local src_domain = Plan.descriptor_domain(src_node.artifact.instance.descriptor)
        local dst_domain = Plan.descriptor_domain(dst_node.artifact.instance.descriptor)
        if same_value(src_domain, dst_domain) then
            facts[#facts + 1] = Stencil.StencilFusionSameDomain(src_node.id, dst_node.id)
        else
            rejects[#rejects + 1] = Stencil.StencilFusionRejectUnsupportedComposition(
                src_node.id,
                dst_node.id,
                "fused stencil nodes must share the same iteration domain"
            )
        end
    end

    local function append_cycle_rejects(rejects, wires, nodes)
        local indegree, out_edges, present = {}, {}, {}
        for _, node in ipairs(nodes or {}) do
            indegree[node.id.text] = 0
            out_edges[node.id.text] = {}
            present[node.id.text] = true
        end
        for _, wire0 in ipairs(wires or {}) do
            local src = wire0.src.node and wire0.src.node.text or nil
            local dst = wire0.dst.node and wire0.dst.node.text or nil
            if src ~= nil and dst ~= nil and src ~= dst and present[src] and present[dst] then
                out_edges[src][#out_edges[src] + 1] = dst
                indegree[dst] = indegree[dst] + 1
            end
        end
        local queue = {}
        for id, degree in pairs(indegree) do
            if degree == 0 then queue[#queue + 1] = id end
        end
        local seen = 0
        local qi = 1
        while queue[qi] ~= nil do
            local id = queue[qi]
            qi = qi + 1
            seen = seen + 1
            for _, dst in ipairs(out_edges[id] or {}) do
                indegree[dst] = indegree[dst] - 1
                if indegree[dst] == 0 then queue[#queue + 1] = dst end
            end
        end
        if seen == #(nodes or {}) then return end
        for _, wire0 in ipairs(wires or {}) do
            if wire0.src.node ~= nil and wire0.dst.node ~= nil then
                rejects[#rejects + 1] = Stencil.StencilFusionRejectCycle(wire0.id, "metastencil dataflow must be acyclic")
                return
            end
        end
    end

    local function legality(external_ports, nodes, wires, opts)
        opts = opts or {}
        local facts, proof_obligations, rejects = {}, {}, {}
        local ports = build_port_map(external_ports, nodes)
        local nodes_by_id = {}
        for _, node in ipairs(nodes or {}) do nodes_by_id[node.id.text] = node end
        for _, wire0 in ipairs(wires or {}) do
            local src, dst = ports[port_key(wire0.src)], ports[port_key(wire0.dst)]
            if src == nil then rejects[#rejects + 1] = Stencil.StencilFusionRejectMissingPort(wire0.src) end
            if dst == nil then rejects[#rejects + 1] = Stencil.StencilFusionRejectMissingPort(wire0.dst) end
            if src ~= nil and dst ~= nil then
                if same_value(src.ty, wire0.ty) and same_value(dst.ty, wire0.ty) then
                    facts[#facts + 1] = Stencil.StencilFusionCompatibleAbi(wire0.id, wire0.ty)
                    facts[#facts + 1] = Stencil.StencilFusionNoIntermediateMaterialization(wire0.id)
                else
                    rejects[#rejects + 1] = Stencil.StencilFusionRejectTypeMismatch(wire0.id, src.ty, dst.ty)
                end
                append_same_domain_fact_or_reject(facts, rejects, wire0, nodes_by_id)
            end
        end
        append_cycle_rejects(rejects, wires, nodes)
        for _, fact in ipairs(opts.alias_facts or {}) do
            facts[#facts + 1] = Stencil.StencilFusionAliasRelation(fact.left, fact.right, fact.relation)
        end
        for _, obligation in ipairs(opts.proof_obligations or {}) do
            proof_obligations[#proof_obligations + 1] = obligation
            facts[#facts + 1] = Stencil.StencilFusionProofObligation(obligation)
        end
        for _, reject in ipairs(opts.rejects or {}) do rejects[#rejects + 1] = reject end
        return Stencil.StencilFusionLegality(facts, proof_obligations, rejects)
    end

    local function descriptor(id, external_ports, nodes, wires, abi, opts)
        return Stencil.StencilMetastencilDescriptor(
            meta_id(id),
            external_ports or {},
            nodes or {},
            wires or {},
            assert(abi, "stencil_metastencil.descriptor requires abi"),
            legality(external_ports, nodes, wires, opts)
        )
    end

    local function fingerprint(desc)
        return Stencil.StencilMetastencilFingerprint(
            "stencil-metastencil-v1:" .. stable_hash32("stencil-metastencil-v1\n" .. stable_repr(desc))
        )
    end

    local function candidate(desc, opts)
        opts = opts or {}
        local rejects = {}
        for _, reject in ipairs(desc.legality.rejects or {}) do rejects[#rejects + 1] = reject end
        for _, reject in ipairs(opts.rejects or {}) do rejects[#rejects + 1] = reject end
        local status = opts.status
        if status == nil then
            status = #rejects == 0 and Stencil.StencilMetastencilCandidateViable or Stencil.StencilMetastencilCandidateRejected
        end
        return Stencil.StencilMetastencilCandidate(
            desc,
            opts.fingerprint or fingerprint(desc),
            opts.covered_nodes or #(desc.nodes or {}),
            opts.cost or #(desc.wires or {}),
            status,
            rejects,
            opts.reason or (#rejects == 0 and "metastencil cover is legal" or "metastencil cover rejected by legality facts")
        )
    end

    local function candidate_is_legal(candidate0)
        return #candidate0.rejects == 0 and candidate0.status ~= Stencil.StencilMetastencilCandidateRejected
    end

    local function ranked_better(a, b)
        if b == nil then return true end
        if a.covered_nodes ~= b.covered_nodes then return a.covered_nodes > b.covered_nodes end
        if a.cost ~= b.cost then return a.cost < b.cost end
        return a.fingerprint.text < b.fingerprint.text
    end

    local function normalize_candidate(x)
        if pvm.classof(x) == Stencil.StencilMetastencilCandidate then return x end
        return candidate(x)
    end

    local function restatus(candidate0, status, reason)
        return Stencil.StencilMetastencilCandidate(
            candidate0.descriptor,
            candidate0.fingerprint,
            candidate0.covered_nodes,
            candidate0.cost,
            status,
            candidate0.rejects,
            reason or candidate0.reason
        )
    end

    local function select_longest_legal_cover(candidates0)
        local candidates, winner = {}, nil
        for _, c0 in ipairs(candidates0 or {}) do
            local c = normalize_candidate(c0)
            candidates[#candidates + 1] = c
            if candidate_is_legal(c) and ranked_better(c, winner) then winner = c end
        end
        local final_candidates, rejects = {}, {}
        for _, c in ipairs(candidates) do
            if c == winner then
                final_candidates[#final_candidates + 1] = restatus(c, Stencil.StencilMetastencilCandidateSelected, "selected longest legal metastencil cover")
            elseif candidate_is_legal(c) then
                final_candidates[#final_candidates + 1] = restatus(c, Stencil.StencilMetastencilCandidateViable, "legal cover superseded by a longer legal cover")
            else
                final_candidates[#final_candidates + 1] = restatus(c, Stencil.StencilMetastencilCandidateRejected, c.reason)
                for _, reject in ipairs(c.rejects or {}) do rejects[#rejects + 1] = reject end
            end
        end
        if winner ~= nil then
            local selected = final_candidates[1]
            for _, c in ipairs(final_candidates) do
                if c.descriptor == winner.descriptor then
                    selected = c
                    break
                end
            end
            local provenance = Stencil.StencilMetastencilCoverProvenance(
                Stencil.StencilScheduleSelectionHeuristic,
                selected.descriptor.id.text,
                final_candidates,
                "selected the legal cover with maximal node coverage, then lowest cost"
            )
            return Stencil.StencilMetastencilCoverSelected(selected, provenance)
        end
        local provenance = Stencil.StencilMetastencilCoverProvenance(
            Stencil.StencilScheduleSelectionFallback,
            "none",
            final_candidates,
            "no legal metastencil cover was available"
        )
        return Stencil.StencilMetastencilNoCover(rejects, provenance)
    end

    local function descriptor_artifacts(desc, out)
        out = out or {}
        for _, node in ipairs(desc.nodes or {}) do out[#out + 1] = node.artifact end
        return out
    end

    local function access_by_name(desc)
        local out = {}
        for _, access in ipairs(Plan.descriptor_accesses(desc)) do out[access.name] = access end
        return out
    end

    local function descriptor_access_role(desc, role)
        for _, access in ipairs(Plan.descriptor_accesses(desc)) do
            if access.role == role then return access end
        end
        return nil
    end

    local function node_by_id(desc)
        local out = {}
        for _, node in ipairs(desc.nodes or {}) do out[node.id.text] = node end
        return out
    end

    local function node_is_apply(node)
        return pvm.classof(node.artifact.instance.descriptor) == Stencil.StencilDescriptorApply
    end

    local function node_is_reduce_fold(node)
        local d = node.artifact.instance.descriptor
        return pvm.classof(d) == Stencil.StencilDescriptorReduce
            and pvm.classof(d.mode) == Stencil.StencilReduceFold
    end

    local function cover_tag(desc)
        return "meta_" .. desc.id.text:gsub("[^%w_]", "_")
    end

    local function fused_apply_reduce_artifact(desc)
        if #(desc.nodes or {}) ~= 2 then return nil, "fused cover currently requires exactly Apply -> Reduce" end
        local nodes = node_by_id(desc)
        local apply_node, reduce_node, apply_out, reduce_in
        for _, wire0 in ipairs(desc.wires or {}) do
            local src_node = wire0.src.node and nodes[wire0.src.node.text] or nil
            local dst_node = wire0.dst.node and nodes[wire0.dst.node.text] or nil
            if src_node ~= nil and dst_node ~= nil and node_is_apply(src_node) and node_is_reduce_fold(dst_node) then
                apply_node, reduce_node = src_node, dst_node
                apply_out, reduce_in = wire0.src.name, wire0.dst.name
                break
            end
        end
        if apply_node == nil then return nil, "fused cover is not an Apply -> Reduce dataflow" end
        local apply_desc = apply_node.artifact.instance.descriptor
        local reduce_desc = reduce_node.artifact.instance.descriptor
        local apply_accesses = access_by_name(apply_desc)
        local reduce_accesses = access_by_name(reduce_desc)
        local out_access = apply_accesses[apply_out]
        local in_access = reduce_accesses[reduce_in]
        if out_access == nil or in_access == nil then return nil, "fused cover wire references missing Apply/Reduce access" end
        if not same_value(out_access.ty, in_access.ty) then return nil, "fused Apply output type does not match Reduce input type" end
        local inputs = {}
        for _, access in ipairs(Plan.descriptor_accesses(apply_desc)) do
            if access.name ~= apply_out and access.role ~= Stencil.StencilAccessWrite then
                inputs[#inputs + 1] = { name = access.name, ty = access.ty, topology = access.topology }
            end
        end
        local reducer = reduce_desc.mode.reducer
        local apply_shape = Plan.artifact_shape(apply_node.artifact)
        return Plan.reduce_n_array_artifact({
            kind = reducer.reduction,
            int_semantics = reducer.int_semantics,
            float_mode = reducer.float_mode,
        }, nil, {
            tag = cover_tag(desc),
            item_ty = out_access.ty,
            result_ty = reducer.result_ty,
            inputs = inputs,
            expr = apply_desc.expr,
            step_num = apply_shape.stride or 1,
        })
    end

    local function cover_descriptor(cover)
        local cls = pvm.classof(cover)
        if cls == Stencil.StencilMetastencilDescriptor then return cover end
        if cls == Stencil.StencilMetastencilCandidate then return cover.descriptor end
        if cls == Stencil.StencilMetastencilCoverSelected then return cover.candidate.descriptor end
        return nil
    end

    local function cover_fingerprint(cover)
        local cls = pvm.classof(cover)
        if cls == Stencil.StencilMetastencilCandidate then return cover.fingerprint end
        if cls == Stencil.StencilMetastencilCoverSelected then return cover.candidate.fingerprint end
        local desc = cover_descriptor(cover)
        if desc ~= nil then return fingerprint(desc) end
        return nil
    end

    local function cover_rejects(cover)
        local cls = pvm.classof(cover)
        if cls == Stencil.StencilMetastencilNoCover then return cover.rejects or {} end
        if cls == Stencil.StencilMetastencilCandidate then return cover.rejects or {} end
        if cls == Stencil.StencilMetastencilCoverSelected then return cover.candidate.rejects or {} end
        local desc = cover_descriptor(cover)
        if desc ~= nil then return desc.legality.rejects or {} end
        return {}
    end

    local function cover_is_legal(cover)
        if pvm.classof(cover) == Stencil.StencilMetastencilNoCover then return false end
        return cover_descriptor(cover) ~= nil and #cover_rejects(cover) == 0
    end

    local function cover_record(cover)
        local cls = pvm.classof(cover)
        if cls == Stencil.StencilMetastencilCandidate then return cover end
        if cls == Stencil.StencilMetastencilCoverSelected then return cover.candidate end
        local desc = cover_descriptor(cover)
        if desc == nil then return nil end
        return candidate(desc)
    end

    local function normalize_artifact_inputs(inputs)
        local artifacts, covers = {}, {}
        for _, item in ipairs(inputs or {}) do
            local cls = pvm.classof(item)
            if cls == Stencil.StencilArtifact then
                artifacts[#artifacts + 1] = item
            elseif cls == Stencil.StencilMetastencilDescriptor
                or cls == Stencil.StencilMetastencilCandidate
                or cls == Stencil.StencilMetastencilCoverSelected then
                if not cover_is_legal(item) then
                    error("stencil_metastencil: cannot materialize rejected metastencil cover", 3)
                end
                covers[#covers + 1] = cover_record(item)
                local fused, reason = fused_apply_reduce_artifact(cover_descriptor(item))
                if fused == nil then
                    error("stencil_metastencil: selected cover is not yet fusible: " .. tostring(reason), 3)
                end
                artifacts[#artifacts + 1] = fused
            elseif cls == Stencil.StencilMetastencilNoCover then
                error("stencil_metastencil: cannot materialize StencilMetastencilNoCover", 3)
            else
                error("stencil_metastencil: unsupported materializer input " .. tostring(cls or type(item)), 3)
            end
        end
        return artifacts, covers
    end

    api.node_id = node_id
    api.wire_id = wire_id
    api.meta_id = meta_id
    api.port_ref = port_ref
    api.port = port
    api.external_port = function(name, flow, ty) return port(nil, name, flow, ty, nil) end
    api.node_from_artifact = node_from_artifact
    api.wire = wire
    api.legality = legality
    api.descriptor = descriptor
    api.fingerprint = fingerprint
    api.candidate = candidate
    api.select_longest_legal_cover = select_longest_legal_cover
    api.descriptor_artifacts = descriptor_artifacts
    api.fused_apply_reduce_artifact = fused_apply_reduce_artifact
    api.cover_descriptor = cover_descriptor
    api.cover_fingerprint = cover_fingerprint
    api.cover_rejects = cover_rejects
    api.cover_is_legal = cover_is_legal
    api.cover_record = cover_record
    api.normalize_artifact_inputs = normalize_artifact_inputs
    api.stable_hash32_for_test = stable_hash32
    api.stable_repr_for_test = stable_repr

    T._lalin_api_cache.stencil_metastencil = api
    return api
end

return bind_context
