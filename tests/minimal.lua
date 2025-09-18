vim.env.XDG_CONFIG_HOME = vim.fn.getcwd() .. '/.tests/xdg/config'
vim.env.XDG_DATA_HOME = vim.fn.getcwd() .. '/.tests/xdg/data'
vim.env.XDG_STATE_HOME = vim.fn.getcwd() .. '/.tests/xdg/state'
vim.opt.runtimepath:append(vim.fn.getcwd())