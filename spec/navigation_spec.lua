---@diagnostic disable: undefined-global, undefined-field
describe('navigation commands', function()
  before_each(function()
    pending('ensure contest is set up (fixture); start at problem A')
  end)

  it(':CP next moves to next problem; stops at last', function()
    pending('invoke next repeatedly; assert no wrap past last')
  end)

  it(':CP prev moves to previous problem; stops at first', function()
    pending('invoke prev repeatedly; assert no wrap before first')
  end)

  it(':CP {problem_id} jumps to problem within loaded contest', function()
    pending('jump to C (or any); assert buffer/state')
  end)
end)
