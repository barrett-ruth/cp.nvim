local M = {}

local config = nil

function M.set_config(user_config)
	config = user_config
end

function M.log(msg, level)
	level = level or vim.log.levels.INFO
	if not config or config.debug or level >= vim.log.levels.WARN then
		vim.notify(("[cp.nvim]: %s"):format(msg), level)
	end
end

return M
