local pvm = require("moonlift.pvm")

local M = {}

function M.Define(T)
    local H = T.MoonHost

    local function field_read_op(field)
        if pvm.classof(field.rep) == H.HostRepBool then return H.HostAccessDecodeBool(field) end
        return H.HostAccessDirectField(field)
    end

    local function record_entries(subject, layout, include_ptr)
        local entries = {}
        if include_ptr then entries[#entries + 1] = H.HostAccessEntry(H.HostAccessMethod("ptr"), H.HostAccessPointerCast(layout)) end
        for i = 1, #layout.fields do
            local field = layout.fields[i]
            entries[#entries + 1] = H.HostAccessEntry(H.HostAccessField(field.name), field_read_op(field))
        end
        entries[#entries + 1] = H.HostAccessEntry(H.HostAccessPairs, H.HostAccessIterateFields(layout.id))
        entries[#entries + 1] = H.HostAccessEntry(H.HostAccessToTable, H.HostAccessMaterializeTable(subject))
        return entries
    end

    local function view_entries(subject, descriptor)
        local elem_layout = descriptor.abi.elem_layout
        local entries = {
            H.HostAccessEntry(H.HostAccessLen, H.HostAccessViewLen(descriptor)),
            H.HostAccessEntry(H.HostAccessData, H.HostAccessViewData(descriptor)),
            H.HostAccessEntry(H.HostAccessStride, H.HostAccessViewStride(descriptor)),
            H.HostAccessEntry(H.HostAccessIndex, H.HostAccessViewIndex(descriptor)),
        }
        for i = 1, #elem_layout.fields do
            local field = elem_layout.fields[i]
            entries[#entries + 1] = H.HostAccessEntry(H.HostAccessMethod("get_" .. field.name), H.HostAccessViewFieldAt(descriptor, field))
        end
        entries[#entries + 1] = H.HostAccessEntry(H.HostAccessToTable, H.HostAccessMaterializeTable(subject))
        return entries
    end

    local phase = pvm.phase("moonlift_host_access_plan", {
        [H.HostAccessRecord] = function(self)
            return pvm.once(H.HostAccessPlan(self, record_entries(self, self.layout, true)))
        end,
        [H.HostAccessPtr] = function(self)
            return pvm.once(H.HostAccessPlan(self, record_entries(self, self.layout, true)))
        end,
        [H.HostAccessView] = function(self)
            return pvm.once(H.HostAccessPlan(self, view_entries(self, self.descriptor)))
        end,
        [H.HostTypeLayout] = function(self)
            local subject = H.HostAccessRecord(self)
            return pvm.once(H.HostAccessPlan(subject, record_entries(subject, self, true)))
        end,
        [H.HostViewDescriptor] = function(self)
            local subject = H.HostAccessView(self)
            return pvm.once(H.HostAccessPlan(subject, view_entries(subject, self)))
        end,
    })

    local function plan(subject)
        return pvm.one(phase(subject))
    end

    return {
        phase = phase,
        plan = plan,
    }
end

return M
