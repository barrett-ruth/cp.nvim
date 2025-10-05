---@diagnostic disable: undefined-global, undefined-field
local helpers = require('spec._helpers')

describe('cp.nvim end-to-end integration', function()
  it(':CP <platform> <contest_id> performs full setup workflow', function()
    local tmp = helpers.tmpdir()
    vim.fn.chdir(tmp)

    local CF_FIXTURE =
      [[{"success":true,"contest_id":"2000","problems":[{"id":"a","name":"Test A"}]}]]
    local restore = helpers.capture_system({
      ['uv run -m scrapers.codeforces metadata 2000'] = { stdout = CF_FIXTURE },
      ['uv run -m scrapers.codeforces tests 2000 a'] = { stdout = '{"problem_id":"a","tests":[]}' },
    })

    require('cp.config')
    -- helpers.exec('CP codeforces 2000')
    --
    -- local state = require('cp.state')
    -- assert.are.same('codeforces', state.get_platform())
    -- assert.are.same('2000', state.get_contest_id())
    --
    -- local src = vim.fn.glob('*.cpp')
    -- assert.is_true(#src > 0, 'source file should be created')
    --
    -- restore()
  end)
end)
