# 󰅩 FileMatrix.nvim

[![Neovim](https://img.shields.io/badge/Neovim-0.11+-blue?logo=neovim)](https://neovim.io/)
[![License](https://img.shields.io/badge/License-MIT-green)](LICENSE)
[![Lua](https://img.shields.io/badge/Language-Lua-blue?logo=lua)](https://www.lua.org/)

A lightweight, matrix-like file and resource manager for Neovim. `FileMatrix.nvim` provides a set of unified view primitives to explore your workspace, buffers, recent files, and diagnostics in a consistent, high-performance interface.

## 󰏗 Features

- 󰉖 **Filesystem Exploration**: A fast, editable view of your directories. Rename, move, or delete files directly within the buffer.
- 󱔗 **Buffer & Recent Management**: Quickly switch between open buffers or jump back to recently edited files.
- 󰅚 **Workspace Diagnostics**: A comprehensive view of all diagnostics across your project, grouped by root directory.
- 󰊄 **Live Previews**: Peek into files or directories in a side-pane without leaving your current position.
- 󰓧 **Dynamic Iconography**: Beautiful, color-coded icons based on file types and names, with support for Catppuccin palettes.
- 󱎫 **High Performance**: Built for speed using Neovim 0.11+ APIs and optimized with debounced disk I/O.

## 󱘚 Installation

Using [vim.pack](https://github.com/folke/lazy.nvim):

```lua
{
    vim.pack.add({ src = "https://github.com/Jlesster/FileMatrix.nvim"})
    require("FileMatrix").setup({
        -- your configuration here
    })
}
```

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
    "Jlesster/FileMatrix.nvim",
    config = function()
        require("FileMatrix").setup({
            -- your configuration here
        })
    end,
}
```

## 󰒓 Configuration

```lua
require("FileMatrix").setup({
    border = "rounded",                                -- Window border style
    float = { width = 0.6, height = 0.4 },               -- Float window dimensions (relative to editor)
    win_opts = {
        cursorline = true,
        number = false,
        relativenumber = false,
        signcolumn = "no",
        wrap = false,
        winhighlight = "CursorLine:Visual,Winbar:Title",
    },
    preview = {
        enabled = true,
        max_height = 17,
        debounce = 30
    },
    icons = { enabled = true },                        -- Toggle built-in icons
    diagnostics = {
        size = 10,                                      -- Height of diagnostics window
        workspace = true,                               -- Scan entire project for diagnostics
        roots = { ".git", "Cargo.toml", "package.json" }, -- Project root markers
    },
    keys = {
        open = "<leader>fm",                             -- Open filesystem explorer
        buffers = "<leader>fb",                        -- View open buffers
        oldfiles = "<leader>fo",                        -- View recent files
        diagnostics = "<leader>fd",                     -- View diagnostics
    },
})
```

## 󱎚 Keybindings (Default)

### Filesystem Explorer (`open`)
- `l` or `<CR>`: Enter directory or open file.
- `h`: Go to parent directory.
- `q`: Save changes and close (or close if unmodified).
- `P`: Toggle preview panes.

### Resource Lists (`buffers`, `oldfiles`, `diagnostics`)
- `<CR>` or `l`: Select item and close.
- `q`: Close window.
- `[[` / `]]`: Jump between diagnostic groups.

## 󰑭 Requirements
- Neovim `0.11.0` or newer.
- A Nerd Font for icons.

## 󰑭 License
Distributed under the MIT License. See `LICENSE` for more information.
