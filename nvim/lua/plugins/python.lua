return {
  -- Use basedpyright instead of pyright for better type checking
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        basedpyright = {},
        pyright = false,
        ruff = {},
      },
    },
  },
}
