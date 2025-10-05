---@diagnostic disable: undefined-global, undefined-field
describe('run panel (:CP run / :CP debug)', function()
  it(':CP run opens/closes panel and renders rows', function()
    pending('toggle open/close; verify panel buffer/windows; minimal content checks')
  end)

  it('respects ui.run_panel.max_output_lines', function()
    pending('feed long output via fixture; ensure truncation/limit applied')
  end)

  it(':CP debug uses debug command template', function()
    pending('assert chosen command tokens differ from normal run/build')
  end)
end)
