---@diagnostic disable: undefined-global, undefined-field
describe('error handling & validation', function()
  it('unknown platform yields user-facing message (no crash)', function()
    pending('call :CP unknown 123; assert notification; no exception')
  end)

  it('bad contest id or unreachable scraper handled gracefully', function()
    pending('stub failing vim.system; assert message; no exception')
  end)

  it('missing language config surfaces actionable error', function()
    pending('platform enabled without default language; expect message')
  end)
end)
