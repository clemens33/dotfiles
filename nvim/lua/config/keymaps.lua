-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua

-- Yank relative file path + selected lines to clipboard (for pasting into Claude Code)
vim.keymap.set("v", "<leader>yp", function()
  local start_line = vim.fn.line("v")
  local end_line = vim.fn.line(".")
  if start_line > end_line then
    start_line, end_line = end_line, start_line
  end
  local lines = vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false)
  local filepath = vim.fn.fnamemodify(vim.fn.expand("%"), ":.")
  local content = filepath .. ":" .. start_line .. "-" .. end_line .. "\n" .. table.concat(lines, "\n")
  vim.fn.setreg("+", content)
  vim.notify("Copied " .. #lines .. " lines with path to clipboard")
end, { desc = "Yank file path + selection to clipboard" })

-- Normal mode: yank just the relative file path
vim.keymap.set("n", "<leader>yp", function()
  local filepath = vim.fn.fnamemodify(vim.fn.expand("%"), ":.")
  local line = vim.fn.line(".")
  vim.fn.setreg("+", filepath .. ":" .. line)
  vim.notify("Copied: " .. filepath .. ":" .. line)
end, { desc = "Yank file path + line to clipboard" })

-- German QWERTZ keyboard aliases
-- Terminal toggle (Ctrl+/ is Shift+7 on German layout — unusable)
vim.keymap.set({ "n", "t" }, "<C-t>", function()
  Snacks.terminal()
end, { desc = "Toggle terminal" })

-- Bracket motions: ü/+ sit where [/] are on US layout
vim.keymap.set({ "n", "x", "o" }, "ü", "[", { remap = true })
vim.keymap.set({ "n", "x", "o" }, "+", "]", { remap = true })

-- Paragraph jumps: Ö/Ä since {/} are AltGr combos on German layout
vim.keymap.set({ "n", "x", "o" }, "Ö", "{", { remap = true })
vim.keymap.set({ "n", "x", "o" }, "Ä", "}", { remap = true })
