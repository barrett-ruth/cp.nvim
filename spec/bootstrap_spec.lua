---@diagnostic disable: undefined-global, undefined-field
describe('cp.nvim bootstrap', function()
  it('registers :CP user command without error', function()
    pending('ensure :CP exists and no load errors')
  end)

  it(':checkhealth cp reports status (no crash)', function()
    pending('run :checkhealth cp and assert buffer opens, minimal expectations')
  end)
end)
