local M = {}

function M.compile(T, artifacts, opts)
    opts = opts or {}
    local Bank = require("lalin.copy_patch_mc")(T)
    local bank, bank_err, source = Bank.build_mc_bank(artifacts, opts)
    if bank == nil then return nil, bank_err, source end
    local realization, realize_err = Bank.realize_mc_artifacts(artifacts, {
        mc_bank = bank,
        ffi_preamble = opts.ffi_preamble,
        patch_values = opts.patch_values,
    })
    if realization == nil then return nil, realize_err, source end
    return {
        kind = "MCStencilTestBuild",
        mc_bank = bank,
        realization = realization,
        symbols = realization.symbols,
        source = source,
    }, nil, source
end

return M
