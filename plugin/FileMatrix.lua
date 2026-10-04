if vim.g.loaded_FileMatrix then return end
vim.g.loaded_FileMatrix = true

local function cmd(name, fn, opts) vim.api.nvim_create_user_command(name, fn, opts or {}) end

cmd("Fm", function(a)
    local dir = a.args ~= "" and vim.fn.fnamemodify(a.args, ":p") or vim.fn.getcwd()
    require("FileMatrix.nvim").open(dir)
end, { nargs = "?", complete = "dir" })
cmd("FmBuffers", function() require("FileMatrix.nvim").buffers() end)
cmd("FmOldfiles", function() require("FileMatrix.nvim").oldfiles() end)
cmd("FmDiagnostics", function() require("FileMatrix.nvim").diagnostics() end)
