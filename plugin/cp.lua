if vim.g.loaded_cp then
	return
end
vim.g.loaded_cp = 1

require("cp").setup()
