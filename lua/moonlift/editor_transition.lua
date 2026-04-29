-- Transition planning currently lives with the pure workspace apply boundary.
-- This module keeps the file-family name promised by the LSP integration
-- checklist while preserving one semantic implementation of
-- Apply(state,event)->Transition(before,event,after).

return require("moonlift.editor_workspace_apply")
