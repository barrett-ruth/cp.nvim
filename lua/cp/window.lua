local M = {}

function M.clearcol()
	vim.api.nvim_set_option_value("number", false, { scope = "local" })
	vim.api.nvim_set_option_value("relativenumber", false, { scope = "local" })
	vim.api.nvim_set_option_value("statuscolumn", "", { scope = "local" })
	vim.api.nvim_set_option_value("signcolumn", "no", { scope = "local" })
	vim.api.nvim_set_option_value("equalalways", false, { scope = "global" })
end

function M.save_layout()
	local windows = {}
	for _, win in ipairs(vim.api.nvim_list_wins()) do
		if vim.api.nvim_win_is_valid(win) then
			local bufnr = vim.api.nvim_win_get_buf(win)
			windows[win] = {
				bufnr = bufnr,
				view = vim.fn.winsaveview(),
				width = vim.api.nvim_win_get_width(win),
				height = vim.api.nvim_win_get_height(win),
			}
		end
	end

	return {
		windows = windows,
		current_win = vim.api.nvim_get_current_win(),
		layout = vim.fn.winrestcmd(),
	}
end

function M.restore_layout(state)
	if not state then
		return
	end

	vim.cmd.diffoff()
	
	local problem_id = vim.fn.expand("%:t:r")
	if problem_id == "" then
		for win, win_state in pairs(state.windows) do
			if vim.api.nvim_win_is_valid(win) and vim.api.nvim_buf_is_valid(win_state.bufnr) then
				local bufname = vim.api.nvim_buf_get_name(win_state.bufnr)
				if bufname:match("%.cc$") then
					problem_id = vim.fn.fnamemodify(bufname, ":t:r")
					break
				end
			end
		end
	end

	if problem_id ~= "" then
		vim.cmd('silent only')
		
		local base_fp = vim.fn.getcwd()
		local input = ("%s/io/%s.in"):format(base_fp, problem_id)
		local output = ("%s/io/%s.out"):format(base_fp, problem_id)
		local source = problem_id .. ".cc"
		
		vim.cmd.edit(source)
		vim.cmd.vsplit(output)
		vim.bo.filetype = "cp"
		M.clearcol()
		vim.cmd(("vertical resize %d"):format(math.floor(vim.o.columns * 0.3)))
		vim.cmd.split(input)
		vim.bo.filetype = "cp"
		M.clearcol()
		vim.cmd.wincmd("h")
	else
		vim.cmd(state.layout)
		
		for win, win_state in pairs(state.windows) do
			if vim.api.nvim_win_is_valid(win) then
				vim.api.nvim_set_current_win(win)
				if vim.api.nvim_get_current_buf() == win_state.bufnr then
					vim.fn.winrestview(win_state.view)
				end
			end
		end

		if vim.api.nvim_win_is_valid(state.current_win) then
			vim.api.nvim_set_current_win(state.current_win)
		end
	end
end

function M.setup_diff_layout(actual_output, expected_output, input_file)
	vim.cmd.diffoff()
	vim.cmd('silent only')

	local output_lines = vim.split(actual_output, "\n")
	local output_buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(output_buf, 0, -1, false, output_lines)
	vim.bo[output_buf].filetype = "cp"

	vim.cmd.edit()
	vim.api.nvim_set_current_buf(output_buf)
	M.clearcol()
	vim.cmd.diffthis()

	vim.cmd.vsplit(expected_output)
	vim.bo.filetype = "cp"
	M.clearcol()
	vim.cmd.diffthis()

	vim.cmd.wincmd("h")
	vim.cmd(("botright split %s"):format(input_file))
	vim.bo.filetype = "cp"
	M.clearcol()
	vim.cmd.wincmd("k")
end

return M
