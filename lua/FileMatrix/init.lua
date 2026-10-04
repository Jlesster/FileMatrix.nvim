local api, uv = vim.api, vim.uv
local M = {}
local grp = api.nvim_create_augroup("FileMatrix", { clear = true })

local ns = api.nvim_create_namespace("FileMatrix_view")

---@class FileMatrix.Config
---@field border string
---@field float { width: number, height: number }
---@field win_opts table<string, any>
---@field preview { enabled: boolean, max_height: integer, debounce: integer }
---@field icons { enabled: boolean, dir?: string[], file?: string[], by_name?: table<string, string[]>, by_ext?: table<string, string[]> }
---@field diagnostics { size: integer, workspace: boolean, roots: string[] }
---@field keys table<string, string|false>
local defaults = {
    border = "rounded",
    float = { width = 0.6, height = 0.4 },
    win_opts = {
        cursorline = true,
        number = false,
        relativenumber = false,
        signcolumn = "no",
        wrap = false,
        winhighlight = "CursorLine:Visual,Winbar:Title",
    },
    preview = { enabled = true, max_height = 17, debounce = 30 },
    -- icons: built-in set lives in FileMatrix.nvim/icons_data.lua. Everything below is an optional override:
    --   dir / file          = { glyph, "#rrggbb" } replacing the folder / fallback-file icon
    --   by_name / by_ext    = tables merged over the built-in ones, { [key] = { glyph, "#rrggbb" } }
    icons = { enabled = true },
    diagnostics = {
        size = 10,
        workspace = true,
        -- workspace mode: ask running LSP clients for every project file's diagnostics, not just open buffers
        roots = {
            ".git", "Cargo.toml", "go.mod",
            "package.json", "meson.build",
            "Makefile", ".luarc.json",
            "CMakeLists.txt",
        },
    },
    keys = { open = false, buffers = false, oldfiles = false, diagnostics = false }, -- e.g. open = "<leader>e"
}

local cfg = vim.deepcopy(defaults)

local layouts = {
    pane = function(o)
        return {
            relative = "win",
            win = o.parent,
            row = 0,
            col = o.col,
            width = o.width,
            height = o.height,
            border = cfg.border,
            focusable = false,
        }
    end,
    float = function(o)
        local w = math.floor(vim.o.columns * cfg.float.width)
        local h = math.floor(vim.o.lines * cfg.float.height)
        return {
            relative = "editor",
            width = w,
            height = h,
            col = math.floor((vim.o.columns - w) / 2),
            row = math.floor((vim.o.lines - h) / 2),
            border = cfg.border,
            title = o.title,
            title_pos = "center",
        }
    end,
    auto = function(o)
        local h = #o.lines
        local w = 0
        for _, l in ipairs(o.lines) do
            w = math.max(w, #l)
        end
        return {
            relative = "editor",
            width = w,
            height = h,
            col = math.floor((vim.o.columns - w) / 2),
            row = math.floor((vim.o.lines - h) / 2),
            border = cfg.border,
            title = o.title,
            title_pos = "center",
        }
    end,
}

local function fill(buf, lines, marks)
    vim.bo[buf].modifiable = true
    api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false
    api.nvim_buf_clear_namespace(buf, ns, 0, -1)
    for _, m in ipairs(marks or {}) do
        api.nvim_buf_set_extmark(buf, ns, m[1], m[2], { end_col = m[3], hl_group = m[4] })
    end
end

function M.view(o)
    local layout, enter, prev = o.layout or "below", o.enter ~= false, api.nvim_get_current_win()
    local buf = api.nvim_create_buf(false, true)
    vim.bo[buf].bufhidden = "wipe"
    fill(buf, o.lines, o.marks)

    local horiz = layout == "below" or layout == "above"
    local wincfg = layouts[layout] and layouts[layout](o)
        or { split = layout, win = -1, [horiz and "height" or "width"] = o.size or (horiz and 10 or 40) }
    local win = api.nvim_open_win(buf, enter, wincfg)
    for k, val in pairs(cfg.win_opts) do
        local ok, err = pcall(function() vim.wo[win][k] = val end)
        if not ok then
            vim.notify_once(("FileMatrix: invalid win_opts.%s: %s"):format(k, err), vim.log.levels.WARN)
        end
    end
    if o.title and not layouts[layout] then vim.wo[win].winbar = " " .. o.title .. " " end

    local v = { buf = buf, win = win }
    function v.close()
        if api.nvim_win_is_valid(win) then api.nvim_win_close(win, true) end
        if enter and api.nvim_win_is_valid(prev) then api.nvim_set_current_win(prev) end
    end

    function v.set(lines, marks) fill(buf, lines, marks) end

    for lhs, fn in pairs(o.keys or {}) do
        vim.keymap.set("n", lhs, function() fn(v) end, { buffer = buf, nowait = true })
    end
    return v
end

local SEV = { "E", "W", "I", "H" }
local SEVHL = { "DiagnosticError", "DiagnosticWarn", "DiagnosticInfo", "DiagnosticHint" }
local diag

function M.diagnostics(opts)
    local ws = cfg.diagnostics.workspace
    if opts and opts.workspace ~= nil then ws = opts.workspace end
    if diag and api.nvim_win_is_valid(diag.win) then diag.close() end
    local src_win = api.nvim_get_current_win()
    local src_buf = api.nvim_win_get_buf(src_win)
    local items = {}

    local function collect()
        local by_root, roots, count = {}, {}, 0
        for _, d in ipairs(vim.diagnostic.get(not ws and src_buf or nil)) do
            local name = api.nvim_buf_get_name(d.bufnr)
            local root = ws and name ~= "" and vim.fs.root(name, cfg.diagnostics.roots) or vim.fn.getcwd()
            local list = by_root[root]
            if not list then
                list = {}
                by_root[root] = list
                roots[#roots + 1] = root
            end
            list[#list + 1] = { d = d, name = name }
            count = count + 1
        end
        table.sort(roots)

        local lines, marks = {}, {}
        items = {}
        local function push(item, line, mark)
            items[#items + 1], lines[#lines + 1] = item, line
            if mark then marks[#marks + 1] = { #lines - 1, mark[1], mark[2], mark[3] } end
        end

        for _, root in ipairs(roots) do
            local list = by_root[root]
            table.sort(list, function(a, b)
                if a.name ~= b.name then return a.name < b.name end
                if a.d.lnum ~= b.d.lnum then return a.d.lnum < b.d.lnum end
                return a.d.col < b.d.col
            end)
            if ws then
                local head = "▸ " .. vim.fn.fnamemodify(root, ":~")
                push({ root = root }, head, { 0, #head, "Title" })
            end
            for _, e in ipairs(list) do
                local d = e.d
                local file = e.name:sub(1, #root) == root and e.name:sub(#root + 2) or e.name
                local msg = (d.message:gsub("\n.*", ""))
                push(e, ("%s %s:%d:%d %s"):format(SEV[d.severity], file, d.lnum + 1, d.col + 1, msg),
                    { 0, 1, SEVHL[d.severity] })
            end
        end
        if #lines == 0 then lines = { "No Diagnostics" } end
        return lines, marks, count
    end

    local function peek()
        local e = items[api.nvim_win_get_cursor(0)[1]]
        if not e or not e.d or not api.nvim_win_is_valid(src_win) then return end
        local d = e.d
        if api.nvim_win_get_buf(src_win) ~= d.bufnr then api.nvim_win_set_buf(src_win, d.bufnr) end
        pcall(api.nvim_win_set_cursor, src_win, { d.lnum + 1, d.col })
        api.nvim_win_call(src_win, function() vim.cmd("normal! zz") end)
    end

    local function hop(dir)
        local row = api.nvim_win_get_cursor(0)[1]
        for i = row + dir, dir > 0 and #items or 1, dir do
            if items[i] and items[i].root then return api.nvim_win_set_cursor(0, { i, 0 }) end
        end
    end

    local lines, marks, count = collect()
    local v = M.view({
        lines = lines,
        marks = marks,
        layout = "below",
        size = cfg.diagnostics.size,
        title = "Diagnostics (" .. count .. ")",
        keys = {
            q = function(v) v.close() end,
            ["]]"] = function() hop(1) end,
            ["[["] = function() hop(-1) end,
            ["<CR>"] = function()
                peek()
                if api.nvim_win_is_valid(src_win) then api.nvim_set_current_win(src_win) end
            end,
        },
    })
    diag = v

    local g = api.nvim_create_augroup("FileMatrix_diag", { clear = true })
    api.nvim_create_autocmd("CursorMoved", { group = g, buffer = v.buf, callback = peek })
    api.nvim_create_autocmd("DiagnosticChanged", {
        group = g,
        buffer = not ws and src_buf or nil,
        callback = function()
            if not api.nvim_win_is_valid(v.win) then return true end
            local l, m, n = collect()
            v.set(l, m)
            vim.wo[v.win].winbar = " Diagnostics (" .. n .. ") "
        end,
    })
    return v
end

local function build(o, items)
    local lines = vim.iter(items):map(o.format):totable()
    local marks = o.marks and o.marks(lines) or {}
    if o.icons and cfg.icons.enabled then
        for i, item in ipairs(items) do
            local name = type(item) == "table" and item.name or tostring(item)
            local icon, hl = M.icon(name ~= "" and name or "[No Name]")
            lines[i] = icon .. " " .. lines[i]
            marks[#marks+1] = { i - 1, 0, #icon + 1, hl }
        end
    end
    return lines, marks
end

function M.list(o)
    local items = o.items
    local v
    local function pick()
        local item = items[api.nvim_win_get_cursor(v.win)[1]]
        if not item then return end
        v.close()
        o.on_select(item)
    end
    local lines, marks = build(o, items)
    v = M.view({
        lines = lines,
        marks = marks,
        layout = o.layout,
        title = o.title,
        keys = { q = function() v.close() end, ["<CR>"] = pick, l = pick },
    })
    v.pick = pick
    function v.refresh(new)
        items = new
        v.set(build(o, new))
    end
    return v
end

---@type { by_name: table<string, string[]>, by_ext: table<string, string[]> }?
local data
local ready, cache, ncache = false, {}, 0
local DEFAULT_DIR, DEFAULT_FILE = { "\u{f07b}", "#89b4fa" }, { "\u{f15b}", "#a6adc8" }
local DIR, FILE = DEFAULT_DIR, DEFAULT_FILE
local NAMES = { "red", "peach", "yellow", "green", "teal", "sky", "sapphire", "blue", "lavender", "mauve", "pink" }
local MOCHA = {
    red = "#f38ba8",
    peach = "#fab387",
    yellow = "#f9e2af",
    green = "#a6e3a1",
    teal = "#94e2d5",
    sky = "#89dceb",
    sapphire = "#74c7ec",
    blue = "#89b4fa",
    lavender = "#b4befe",
    mauve = "#cba6f7",
    pink = "#f5c2e7",
    subtext0 = "#a6adc8",
    text = "#cdd6f4",
}

local function hsv(hex)
    local rs, gs, bs = hex:match("#(%x%x)(%x%x)(%x%x)")
    local r, g, b = tonumber(rs, 16) / 255, tonumber(gs, 16) / 255, tonumber(bs, 16) / 255
    local max, d = math.max(r, g, b), math.max(r, g, b) - math.min(r, g, b)
    local h = 0
    if d > 0 then
        if max == r then
            h = ((g - b) / d) % 6
        elseif max == g then
            h = (b - r) / d + 2
        else
            h = (r - g) / d + 4
        end
    end
    return h * 60, max == 0 and 0 or d / max, max
end

local pal, accents, groups = MOCHA, {}, {}

local function pastel(color)
    local h, s, v = hsv(color)
    if s < 0.25 then return v > 0.8 and pal.text or pal.subtext0 end
    local best, dist = nil, 361
    for _, a in ipairs(accents) do
        local d = math.abs(a[1] - h)
        d = math.min(d, 360 - d)
        if d < dist then best, dist = a[2], d end
    end
    return best
end

local function palette()
    local ok, p = pcall(function() return require("catppuccin.palettes").get_palette() end)
    pal = ok and p or MOCHA
    accents = vim.iter(NAMES):map(function(n) return { (hsv(pal[n])), pal[n] } end):totable()
    for color, g in pairs(groups) do api.nvim_set_hl(0, g, { fg = pastel(color) }) end
end
api.nvim_create_autocmd("ColorScheme", { group = grp, callback = function() if ready then palette() end end })

-- exact -> lowercase -> longest dotted suffix ("a.test.ts" tries "test.ts", then "ts")
local function find(name)
    local d = assert(data)
    local hit = d.by_name[name] or d.by_name[name:lower()]
    local i = name:find(".", 1, true)
    while not hit and i do
        local ext = name:sub(i + 1)
        hit = d.by_ext[ext] or d.by_ext[ext:lower()]
        i = name:find(".", i + 1, true)
    end
    return hit
end

local function group(color)
    local g = groups[color]
    if not g then
        g = "Icon_" .. color:sub(2)
        groups[color] = g
        api.nvim_set_hl(0, g, { fg = pastel(color) })
    end
    return g
end

local function init()
    local ic = cfg.icons
    local base = require("FileMatrix.icons_data")
    -- built-in data stays the default; the config block only overrides on top of it
    data = {
        by_name = vim.tbl_extend("force", base.by_name, ic.by_name or {}),
        by_ext = vim.tbl_extend("force", base.by_ext, ic.by_ext or {}),
    }
    DIR, FILE = ic.dir or DEFAULT_DIR, ic.file or DEFAULT_FILE
    ready = true
    palette()
    -- create every hl group now, so nothing calls nvim_set_hl during a redraw
    for _, t in ipairs({ data.by_name, data.by_ext, { DIR, FILE } }) do
        for _, i in pairs(t) do group(i[2]) end
    end
end

function M.icon(name)
    local c = cache[name]
    if c then return c[1], c[2] end
    if not ready then init() end
    local i = name:sub(-1) == "/" and DIR or find(name) or FILE
    if ncache >= 4096 then cache, ncache = {}, 0 end
    ncache = ncache + 1
    c = { i[1], groups[i[2]] }
    cache[name] = c
    return c[1], c[2]
end

local function rel(p) return vim.fn.fnamemodify(p, ":~:.") end

function M.buffers()
    local bufs = vim.fn.getbufinfo({ buflisted = 1 })
    table.sort(bufs, function(a, b) return a.lastused > b.lastused end)
    return M.list({
        items = bufs,
        title = ("buffers (%d)"):format(#bufs),
        format = function(b) return b.name ~= "" and vim.fs.basename(b.name) or "[No Name]" end,
        on_select = function(b) api.nvim_set_current_buf(b.bufnr) end,
        icons = true,
    })
end

local MAX_ROWS = 200
function M.fuzzy_files()
    local cwd = vim.fn.getcwd()
    local ok, res = pcall(function ()
        return vim.system(
            { "rg", "--files", "--hidden", "-g", "!.git" }, { text = true, cwd = cwd}
        ):wait()
    end)
    if not ok or not res.stdout or res.stdout == "" then
        return vim.notify("FileMatrix: no file found ~ (Is rg Installed?)", vim.log.levels.WARN)
    end
    local files = vim.split(res.stdout, "\n", { trimempty = true })
    local function top(list) return vim.list_slice(list, 1, MAX_ROWS) end
    local v
    local function show(q)
        local matches = q == "" and files or vim.fn.matchfuzzy(files, q)
        v.refresh(top(matches))
        api.nvim_win_set_cursor(v.win, { 1, 0 })
        api.nvim_win_set_config(v.win, {
            title = ("files (%d%d)"):format(#matches, #files), title_pos = "center",
            footer = " / " .. q .. " ", footer_pos = "left",
        })
        vim.cmd.redraw()
    end
    local function move(d)
        local n = api.nvim_buf_line_count(v.buf)
        local row = math.min(math.max(api.nvim_win_get_cursor(v.win)[1] + d, 1), n)
        api.nvim_win_set_cursor(v.win, { row, 0 })
        vim.cmd.redraw()
    end
    local function search()
        local q = ""
        local had_cl = vim.wo[v.win].cursorline
        vim.wo[v.win].cursorline = true
        show(q)
        while api.nvim_win_is_valid(v.win) do
            local got, c = pcall(vim.fn.getcharstr)
            if not got or c == vim.keycode("<CR>") then
                v.pick()
                return
            elseif c == vim.keycode("<BS>") or c == vim.keycode("<C-h>") then
                q = vim.fn.strcharpart(q, 0, vim.fn.strchars(q) - 1)
            elseif c == vim.keycode("<C-u>") then
                q = ""
            elseif c == vim.keycode("<C-w>") or c == vim.keycode("<C-BS>") then
                q = q:gsub("%s*%S*$", "")
            elseif c == vim.keycode("<C-j>") or c == vim.keycode("<Down>") then
                move(1); changed = false
            elseif c == vim.keycode("<C-k>") or c == vim.keycode("<Up>") then
                move(-1); changed = false
            elseif c:byte(1) ~= 0x80 and not c:find("%c") then
                q = q .. c
            else
                changed = false
            end
            if changed then show(q) end
        end
        if api.nvim_win_is_valid(v.win) then vim.wo[v.win].cursorline = had_cl end
    end
    v = M.list({
        items = top(files),
        layout = "float",
        title = ("files (%d)"):format(#files),
        format = function (f) return f end,
        marks = function (lines)
            local m = {}
            for i, l in ipairs(lines) do m[i] = { i - 1, 0, #(l:match("^.*/") or ""), "Comment" } end
            return m
        end,
        on_select = function (f) vim.cmd.edit({ args = { vim.fs.joinpath(cwd, f) } }) end,
        icons = true,
        keys = { ["/"] = function() search() end },
    })
end

function M.oldfiles()
    local files = vim.tbl_filter(function(f)
        local s = uv.fs_stat(f)
        return s ~= nil and s.type == "file"
    end, vim.v.oldfiles)
    return M.list({
        items = files,
        layout = "float",
        title = ("recent files (%d)"):format(#files),
        format = rel,
        marks = function(lines)
            local m = {}
            for i, l in ipairs(lines) do m[i] = { i - 1, 0, #(l:match("^.*/") or ""), "Comment" } end
            return m
        end,
        on_select = function(f) vim.cmd.edit({ args = { f } }) end,
        icons = true,
    })
end

local S, by_dir, last = {}, {}, {}

local function quote(name)
    return name:match("^[%w%._%-/+]+$") and name or vim.fn.shellescape(name)
end

local function unquote(s)
    s = vim.trim(s)
    if #s >= 2 and s:sub(1, 1) == "'" and s:sub(-1) == "'" then
        return (s:sub(2, -2):gsub("'\\''", "'"))
    end
    return (s:gsub("\\(.)", "%1"))
end

local function name_of(line)
    if line:match("%S") and not line:match("^%s*#") then return unquote(line) end
end

local function parse(lines)
    return vim.iter(lines):map(name_of):totable()
end

local function path(dir, name) return vim.fs.joinpath(dir, (name:gsub("/$", ""))) end

local function entries(dir, limit)
    local dirs, files, n = {}, {}, 0
    for name, type in vim.fs.dir(dir) do
        if type == "directory" then dirs[#dirs + 1] = name .. "/" else files[#files + 1] = name end
        n = n + 1
        if limit and n >= limit then break end
    end
    table.sort(dirs)
    table.sort(files)
    return vim.list_extend(dirs, files)
end

local function place(buf)
    local want = last[S[buf].dir]
    local i = want and vim.fn.index(S[buf].names, want) or -1
    if i >= 0 and api.nvim_get_current_buf() == buf then pcall(api.nvim_win_set_cursor, 0, { i + 1, 0 }) end
end

local function remember(buf)
    if api.nvim_get_current_buf() ~= buf then return end
    local line = api.nvim_get_current_line()
    local name = name_of(line)
    if name then last[S[buf].dir] = name end
end

local inl = api.nvim_create_namespace("FileMatrix_icons")
local function decorate(buf)
    if not cfg.icons.enabled then return end
    if not S[buf] or not api.nvim_buf_is_valid(buf) then return end
    api.nvim_buf_clear_namespace(buf, inl, 0, -1)
    for row, line in ipairs(api.nvim_buf_get_lines(buf, 0, -1, false)) do
        local name = name_of(line)
        if name then
            local icon, hl = M.icon(name)
            api.nvim_buf_set_extmark(buf, inl, row - 1, 0, {
                virt_text = { { icon .. " ", hl } },
                virt_text_pos = "inline",
                end_col = #line,
                hl_group = hl,
            })
        end
    end
end

local function render(buf)
    local st = S[buf]
    st.names = entries(st.dir)
    vim.bo[buf].undolevels = -1
    api.nvim_buf_set_lines(buf, 0, -1, false, vim.iter(st.names):map(quote):totable())
    vim.bo[buf].undolevels = vim.o.undolevels
    vim.bo[buf].modified = false
    st.shown = nil
    decorate(buf)
end

local diff = (vim.text and vim.text.diff)
local function text(t) return #t > 0 and table.concat(t, "\n") .. "\n" or "" end

local function plan(old, new)
    local rm, mv, add = {}, {}, {}
    local hunks = diff(text(old), text(new), { result_type = "indices" }) --[[@as integer[][] ]]
    for _, h in ipairs(hunks) do
        local a, ac, b, bc = unpack(h)
        local paired = math.min(ac, bc)
        for i = 0, paired - 1 do mv[#mv + 1] = { "mv", old[a + i], new[b + i] } end
        for i = paired, ac - 1 do rm[#rm + 1] = { "rm", old[a + i] } end
        for i = paired, bc - 1 do add[#add + 1] = { "new", new[b + i] } end
    end
    return vim.list_extend(vim.list_extend(rm, mv), add)
end

local function bash(op)
    local k, a, b = unpack(op)
    local q = vim.fn.shellescape
    if k == "mv" then return ("mv -- %s %s"):format(q(a), q(b)) end
    if k == "rm" then return ("rm -r -- %s"):format(q(a)) end
    return ((a:sub(-1) == "/" and "mkdir -p -- %s" or "touch -- %s"):format(q(a)))
end

local function run(dir, op)
    local k, p1 = op[1], path(dir, op[2])
    if k == "rm" then
        vim.fs.rm(p1, { recursive = true })
    elseif k == "mv" then
        local p2 = path(dir, op[3])
        if uv.fs_stat(p2) then error("already exists: " .. op[3]) end
        assert(uv.fs_rename(p1, p2))
    elseif op[2]:sub(-1) == "/" then
        vim.fn.mkdir(p1, "p")
    else
        vim.fn.mkdir(vim.fs.dirname(p1), "p")
        assert(io.open(p1, "a")):close()
    end
end

local function apply(buf, ops)
    local errs = {}
    for _, op in ipairs(ops) do
        local ok, err = pcall(run, S[buf].dir, op)
        if not ok then errs[#errs + 1] = err end
    end
    render(buf)
    place(buf)
    if #errs > 0 then vim.notify(table.concat(errs, "\n"), vim.log.levels.ERROR) end
end

local function preview(buf, ops)
    local v = M.view({
        lines = vim.tbl_map(bash, ops),
        layout = "float",
        title = "  enter: apply     q: cancel ",
        keys = {
            q = function(v) v.close() end,
            ["<CR>"] = function(v)
                v.close(); apply(buf, ops)
            end,
        },
    })
    vim.bo[v.buf].filetype = "bash"
    api.nvim_set_current_win(v.win)
end

local function save(buf)
    local ops = plan(S[buf].names, parse(api.nvim_buf_get_lines(buf, 0, -1, false)))
    if #ops == 0 then
        vim.bo[buf].modified = false; return
    end
    vim.schedule(function() preview(buf, ops) end)
end

local function content(p, max, enabled)
    if not enabled then return end
    local st = uv.fs_stat(p)
    if not st then return { "" } end
    if st.type == "directory" then
        local n = entries(p, 500)
        return vim.list_slice(n, 1, max), n
    end
    if st.type ~= "file" then return { "(" .. st.type .. ")" } end
    local f = io.open(p, "rb")
    if not f then return { "(unreachable)" } end
    local head = f:read(4096) or ""
    f:close()
    if head:find("\0", 1, true) then return { "(binary)" } end
    return vim.list_slice(vim.split((head:gsub("\r", "")), "\n", { plain = true }), 1, max)
end

local function close_panes(buf)
    local st = S[buf]
    if not st then return end
    st.shown = nil
    for _, k in ipairs({ "p1", "p2" }) do
        if st[k] then
            st[k].close(); st[k] = nil
        end
    end
end

local function update_panes(buf)
    if not cfg.preview.enabled then return end
    local st, win = S[buf], api.nvim_get_current_win()
    if not st or api.nvim_get_current_buf() ~= buf then return end
    local name = name_of(api.nvim_get_current_line())
    if not name then return close_panes(buf) end

    local preview_enabled = st.preview_enabled
    local p = path(st.dir, name)
    if st.shown == p and st.p1 and api.nvim_win_is_valid(st.p1.win) then return end
    st.shown = p
    local pw, ph = api.nvim_win_get_width(win), api.nvim_win_get_height(win)
    local h = math.min(ph - 2, cfg.preview.max_height)
    local l1, kids = content(p, h, preview_enabled)
    local first = kids and kids[1]
    local l2 = first and first:sub(-1) == "/" and (content(path(p, first), h, preview_enabled)) or nil
    if not l2 and st.p2 then
        st.p2.close(); st.p2 = nil
    end
    local w, c1 = math.floor(pw * 0.3), math.floor(pw * 0.36)

    for key, spec in pairs({ p1 = { c1, l1 }, p2 = l2 and { c1 + w + 2, l2 } }) do
        local v = st[key]
        if v and api.nvim_win_is_valid(v.win) then
            v.set(spec[2])
        else
            st[key] = M.view({
                lines = spec[2],
                layout = "pane",
                parent = win,
                col = spec[1],
                width = w,
                height = h,
                enter = false,
            })
        end
    end
end

-- debounce: holding j in a big directory must not hit the disk on every row
local function update_panes_soon(buf)
    if not cfg.preview.enabled then return end
    local st = S[buf]
    st.timer = st.timer or uv.new_timer()
    st.timer:start(cfg.preview.debounce, 0, vim.schedule_wrap(function() update_panes(buf) end))
end

local function keymaps(buf)
    local st = S[buf]
    local function map(lhs, fn) vim.keymap.set("n", lhs, fn, { buffer = buf }) end

    local function enter()
        local name = name_of(api.nvim_get_current_line())
        if not name then return end
        local p = path(st.dir, name)
        local s = uv.fs_stat(p)
        if s and s.type == "directory" then M.open(p) else vim.cmd.edit(vim.fn.fnameescape(p)) end
    end

    map("q", function()
        if vim.bo[buf].modified then return save(buf) end
        if pcall(api.nvim_win_close, 0, false) then return end
        if st.origin > 0 and api.nvim_buf_is_valid(st.origin) then vim.cmd.buffer(st.origin) else vim.cmd.enew() end
    end)
    map("h", function()
        local parent = vim.fs.dirname(st.dir)
        if parent == st.dir then return end
        last[parent] = vim.fs.basename(st.dir) .. "/"
        M.open(parent)
    end)
    map("P", function()
        st.preview_enabled = not st.preview_enabled
        update_panes(buf)
    end)
    map("l", enter)
    map("<CR>", enter)
end

function M.open(dir)
    if cfg.icons.enabled and not ready then init() end
    local cur = api.nvim_get_current_buf()
    local origin = S[cur] and S[cur].origin or cur
    dir = vim.fs.normalize(dir)

    local buf = by_dir[dir]
    if buf and api.nvim_buf_is_valid(buf) then
        S[buf].origin = origin
        api.nvim_set_current_buf(buf)
        if not vim.bo[buf].modified then
            render(buf); place(buf)
        end
        return
    end

    local name = "fs://" .. dir
    for _, b in ipairs(api.nvim_list_bufs()) do
        if api.nvim_buf_get_name(b) == name and not S[b] then api.nvim_buf_delete(b, { force = true }) end
    end

    buf = api.nvim_create_buf(false, true)
    api.nvim_buf_set_name(buf, name)
    for opt, val in pairs({ buftype = "acwrite", filetype = "bash", bufhidden = "hide", undofile = false }) do
        vim.bo[buf][opt] = val
    end
    S[buf], by_dir[dir] = { dir = dir, origin = origin, preview_enabled = cfg.preview.enabled }, buf

    local function au(ev, fn)
        api.nvim_create_autocmd(ev, { group = grp, buffer = buf, callback = fn })
    end
    au("CursorMoved", function() update_panes_soon(buf) end)
    au("BufEnter", function() update_panes(buf) end)
    au("BufLeave", function()
        remember(buf); close_panes(buf)
    end)
    au({ "TextChanged", "TextChangedI", "TextChangedP" }, function() decorate(buf) end)
    au("BufWipeout", function()
        close_panes(buf)
        local st = S[buf]
        if st.timer then st.timer:close() end
        S[buf], by_dir[st.dir] = nil, nil
    end)

    keymaps(buf)
    render(buf)
    api.nvim_set_current_buf(buf)
    place(buf)
end

api.nvim_create_autocmd("BufWriteCmd", { group = grp, pattern = "fs://*", callback = function(ev) save(ev.buf) end })

---@param opts? table partial FileMatrix.Config; anything omitted keeps its default
function M.setup(opts)
    if vim.fn.has("nvim-0.11") == 0 then
        return vim.notify("FileMatrix.nvim needs Neovim 0.11+", vim.log.levels.ERROR)
    end
    cfg = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
    ready, cache, ncache = false, {}, 0 -- icons re-init lazily with the new overrides

    local acts = {
        open = function()
            local cur = api.nvim_get_current_buf()
            local name = api.nvim_buf_get_name(cur)
            M.open(S[cur] and S[cur].dir or (name ~= "" and vim.fs.dirname(name)) or vim.fn.getcwd())
        end,
        buffers = M.buffers,
        oldfiles = M.oldfiles,
        diagnostics = M.diagnostics,
    }
    for name, lhs in pairs(cfg.keys) do
        if lhs and acts[name] then
            vim.keymap.set("n", lhs, function() acts[name]() end, { desc = "FileMatrix: " .. name })
        end
    end
end

M.plan, M.parse = plan, parse
return M
