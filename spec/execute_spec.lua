---@diagnostic disable: undefined-global, undefined-field
local exec = require('cp.runner.execute')
local helpers = require('spec._helpers')

describe('cp.runner.execute', function()
  it('returns stdout/stderr/code for success', function()
    local restore = helpers.capture_system({
      ['echo hi'] = { stdout = 'hi\n', code = 0 },
    })
    local r = exec.run({ 'echo', 'hi' }, '', 0, 0)
    assert.are.same('hi\n', r.stdout)
    assert.are.same('', r.stderr or '')
    local code = r.code or r.exit_code or r.status or 0
    assert.are.same(0, code)
    restore()
  end)

  it('propagates non-zero exit codes', function()
    local restore = helpers.capture_system({
      ['false'] = { stdout = '', stderr = '', code = 1 },
    })
    local r = exec.run({ 'false' }, '', 0, 0)
    local code = r.code or r.exit_code or r.status or 0
    assert.is_true(code ~= 0)
    restore()
  end)

  it('passes stdin to vim.system', function()
    local restore = helpers.capture_system({
      ['cat'] = { stdout = 'ok', code = 0 },
    })
    local input = 'abc\n'
    local r = exec.run({ 'cat' }, input, 0, 0)
    local calls = restore()
    assert.are.same(input, calls[1].opts and calls[1].opts.stdin or '')
    assert.are.same('ok', r.stdout)
  end)
end)
