-- Loaded by review.sh on a unified diff read from stdin: c (or <leader>c) comments on the line or selection by
-- typing "path:line — comment" into the Claude pane's input box (not submitted); r marks the file read and goes back
-- to the list, q or Esc goes back without.
local agent_pane = vim.env.REVIEW_AGENT_PANE
local path = vim.env.REVIEW_PATH
local diff_buf = vim.api.nvim_get_current_buf()
local marks = vim.api.nvim_create_namespace("review")
local sent = 0

vim.bo.buftype = "nofile"
vim.bo.modifiable = false
vim.bo.filetype = "diff"
vim.wo.number = false
vim.wo.relativenumber = false
vim.wo.signcolumn = "yes"
-- Wrapped continuations are indented and marked so they don't read as context lines; unwrapped, scroll a column at a time.
vim.wo.breakindent = true
vim.wo.showbreak = "↪ "
vim.wo.linebreak = true
vim.o.sidescroll = 1

-- Diff buffer line -> { old = n } for removed lines, { new = n } for added, both for context lines.
local numbers = {}
do
  local old, new
  for lnum, line in ipairs(vim.api.nvim_buf_get_lines(diff_buf, 0, -1, false)) do
    local old_start, new_start = line:match("^@@ %-(%d+),?%d* %+(%d+)")
    if old_start then
      old, new = tonumber(old_start), tonumber(new_start)
    elseif old and line:match("^%-") then
      numbers[lnum] = { old = old }
      old = old + 1
    elseif old and line:match("^%+") then
      numbers[lnum] = { new = new }
      new = new + 1
    elseif old and line:match("^ ") then
      numbers[lnum] = { old = old, new = new }
      old, new = old + 1, new + 1
    end
  end
end

-- path:12, path:12-14, or path:7 (before) when the selection only covers removed lines.
local function location(first, last)
  local function span(side)
    local low, high
    for lnum = first, last do
      local n = numbers[lnum] and numbers[lnum][side]
      if n then low, high = low or n, n end
    end
    if low then return low == high and tostring(low) or (low .. "-" .. high) end
  end
  local new = span("new")
  if new then return path .. ":" .. new end
  local old = span("old")
  if old then return path .. ":" .. old .. " (before)" end
  return path
end

local function update_winbar()
  local note = sent > 0 and ("  ·  " .. sent .. " sent to Claude") or ""
  vim.wo.winbar = " " .. path .. note .. "%=c comment  ·  w wrap  ·  r read  ·  q back "
end

local function show_sent(last, text, ok)
  local label = ok and ("  ✓ sent: " .. text) or ("  ✗ not sent: " .. text)
  vim.api.nvim_buf_set_extmark(diff_buf, marks, last - 1, 0, {
    sign_text = ok and "✓" or "✗",
    sign_hl_group = ok and "DiagnosticOk" or "DiagnosticError",
    virt_lines = { { { label, ok and "DiagnosticOk" or "DiagnosticError" } } },
  })
end

local function send(last, where, text)
  local result = vim.system({ "herdr", "pane", "send-text", agent_pane, where .. " — " .. text .. "\n" }):wait()
  local ok = result.code == 0
  show_sent(last, text, ok)
  if ok then
    sent = sent + 1
    update_winbar()
  else
    vim.notify("herdr send-text failed: " .. (result.stderr or ""), vim.log.levels.ERROR)
  end
end

-- A centred box: Enter sends, Esc cancels.
local function comment(first, last)
  if not agent_pane or agent_pane == "" then
    vim.notify("No Claude pane to send to", vim.log.levels.WARN)
    return
  end
  local where = location(first, last)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.b[buf].copilot_enabled = false
  local width = math.min(90, vim.o.columns - 8)
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = 3,
    row = math.floor((vim.o.lines - 5) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    style = "minimal",
    border = "rounded",
    title = " " .. where .. " ",
    title_pos = "center",
    footer = " enter: send to Claude  ·  esc: cancel ",
    footer_pos = "center",
  })
  vim.wo[win].wrap = true
  pcall(function() require("cmp").setup.buffer({ enabled = false }) end)

  local function close()
    vim.cmd.stopinsert()
    if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
  end
  vim.keymap.set({ "i", "n" }, "<CR>", function()
    local text = vim.trim(table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), " "))
    close()
    if text ~= "" then send(last, where, text) end
  end, { buffer = buf })
  vim.keymap.set({ "i", "n" }, "<Esc>", close, { buffer = buf })
  vim.cmd.startinsert()
end

local function comment_on_line()
  local line = vim.fn.line(".")
  comment(line, line)
end

local function comment_on_selection()
  local first, last = vim.fn.line("v"), vim.fn.line(".")
  if first > last then first, last = last, first end
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "n", false)
  comment(first, last)
end

for _, lhs in ipairs({ "c", "<leader>c" }) do
  vim.keymap.set("n", lhs, comment_on_line, { buffer = diff_buf, desc = "Comment to Claude" })
  vim.keymap.set("x", lhs, comment_on_selection, { buffer = diff_buf, desc = "Comment to Claude" })
end
for _, lhs in ipairs({ "q", "<Esc>" }) do
  vim.keymap.set("n", lhs, "<cmd>qa!<CR>", { buffer = diff_buf, desc = "Back to the file list" })
end

vim.keymap.set("n", "r", function()
  local result = vim.system({ "sh", vim.env.REVIEW_SCRIPT, "mark-read", path }):wait()
  if result.code ~= 0 then
    vim.notify("Could not mark read: " .. (result.stderr or ""), vim.log.levels.ERROR)
    return
  end
  vim.cmd("qa!")
end, { buffer = diff_buf, desc = "Mark read and go back to the list" })
vim.keymap.set("n", "w", function() vim.wo.wrap = not vim.wo.wrap end, { buffer = diff_buf, desc = "Toggle line wrap" })

update_winbar()
