if vim.g.loaded_fm then return end
vim.g.loaded_fm = true

local function cmd(name, fn, opts) vim.api.nvim_create_user_command(name, fn, opts or {}) end

cmd("Fm", function(a)
    local dir = a.args ~= "" and vim.fn.fnamemodify(a.args, ":p") or vim.fn.getcwd()
    require("fm").open(dir)
end, { nargs = "?", complete = "dir" })
cmd("FmBuffers", function() require("fm").buffers() end)
cmd("FmOldfiles", function() require("fm").oldfiles() end)
cmd("FmDiagnostics", function() require("fm").diagnostics() end)
