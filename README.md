# Example vim.pack configuration
## all options follow over to other plugin managers
```lua
vim.pack.add({ "https://github.com/Jlesster/FileMatrix.nvim" })

require("fm").setup({
    -- window chrome for every view (float, panes, splits)
    border = "rounded",                  -- any nvim_open_win border: "single", "double", "none", ...

    -- size of the float used by oldfiles and the rename/delete preview,
    -- as a fraction of the editor
    float = { width = 0.6, height = 0.4 },

    -- options applied to every fm window; merged over the defaults per key
    win_opts = {
        cursorline = true,
        number = false,
        relativenumber = false,
        signcolumn = "no",
        wrap = false,
        winhighlight = "CursorLine:Visual,Winbar:Title",
    },

    -- the two side panes shown while hovering an entry in the main view
    preview = {
        enabled = true,                  -- false: no panes, no timer, no disk reads on cursor moves
        max_height = 17,                 -- rows of content, clamped to the window height - 2
        debounce = 30,                   -- ms to wait after the last cursor move before reading disk
    },

    -- icons: the built-in set lives in fm/icons_data.lua; every key but `enabled` is an optional override
    icons = {
        enabled = true,                  -- false: no icons in the main view or pickers
        -- dir  = { "\u{f07b}", "#89b4fa" },    -- folder icon: { glyph, "#rrggbb" }
        -- file = { "\u{f15b}", "#a6adc8" },    -- fallback for unmatched files
        -- by_name = { ["Makefile"] = { "\u{e779}", "#fab387" } },   -- merged over the built-in exact names
        -- by_ext  = { lua = { "\u{e620}", "#51a0cf" } },            -- merged over the built-in extensions
    },

    -- diagnostics panel
    diagnostics = {
        size = 10,                       -- rows in the bottom split
        workspace = true,                -- false: only the current buffer
        roots = {                        -- markers that start a new group; replaces the list entirely
            ".git", "Cargo.toml", "go.mod", "package.json",
            "meson.build", "Makefile", ".luarc.json", "CMakeLists.txt",
        },
    },

    -- global keymaps, all off by default; set a lhs string to enable one
    keys = {
        open = "<leader>e",              -- open the file manager at the current file's directory
        buffers = "<leader>fb",          -- buffer picker
        oldfiles = "<leader>fr",         -- recent files picker
        diagnostics = "<leader>xd",      -- diagnostics panel
    },
})
```
