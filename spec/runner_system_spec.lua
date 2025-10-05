---@diagnostic disable: undefined-global, undefined-field
describe('runner / system integration', function()
  it('expands {source} and {binary} in command templates', function()
    pending('assert final argv contains substituted paths')
  end)

  it('captures stdout/stderr/exit code via vim.system', function()
    pending('stub vim.system to return deterministic result; assert panel shows it')
  end)

  it('handles timeouts and non-zero exits (maps to RTE/TLE)', function()
    pending('force timeout/exit 1 and assert status mapping')
  end)
end)
