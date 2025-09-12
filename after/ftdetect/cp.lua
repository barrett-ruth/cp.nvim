vim.api.nvim_create_autocmd({ 'BufRead', 'BufNewFile' }, {
    pattern = '*/io/*.in',
    callback = function()
        vim.bo.filetype = 'cpinput'
    end,
})

vim.api.nvim_create_autocmd({ 'BufRead', 'BufNewFile' }, {
    pattern = '*/io/*.out',
    callback = function()
        vim.bo.filetype = 'cpoutput'
    end,
})
