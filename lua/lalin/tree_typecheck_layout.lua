return function(T)
    local Sem = T.LalinSem
    local Ty = T.LalinType

    function Sem.TypeLayout:typecheck_tree_matches_ref(ref)
        return false
    end

    function Sem.LayoutNamed:typecheck_tree_matches_ref(ref)
        return ref:typecheck_tree_matches_named_layout(self)
    end

    function Sem.LayoutLocal:typecheck_tree_matches_ref(ref)
        return ref:typecheck_tree_matches_local_layout(self)
    end

    function Sem.TypeLayout:typecheck_tree_field_layout(field_name)
        for i = 1, #self.fields do
            if self.fields[i].field_name == field_name then return self.fields[i] end
        end
        return nil
    end

    function Ty.TypeRef:typecheck_tree_matches_named_layout(layout)
        return false
    end

    function Ty.TypeRefGlobal:typecheck_tree_matches_named_layout(layout)
        return layout.module_name == self.module_name and layout.type_name == self.type_name
    end

    function Ty.TypeRefPath:typecheck_tree_matches_named_layout(layout)
        return layout.type_name == self:typecheck_tree_ref_leaf()
    end

    function Ty.TypeRef:typecheck_tree_matches_local_layout(layout)
        return false
    end

    function Ty.TypeRefLocal:typecheck_tree_matches_local_layout(layout)
        return layout.sym == self.sym
    end
end
