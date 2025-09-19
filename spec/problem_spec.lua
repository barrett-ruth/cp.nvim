describe('cp.problem', function()
  local problem

  before_each(function()
    problem = require('cp.problem')
  end)

  describe('create_context', function()
    local base_config = {
      contests = {
        atcoder = {
          default_language = 'cpp',
          cpp = { extension = 'cpp' },
          python = { extension = 'py' },
        },
        codeforces = {
          default_language = 'cpp',
          cpp = { extension = 'cpp' },
        },
      },
    }

    it('creates basic context with required fields', function()
      local context = problem.create_context('atcoder', 'abc123', 'a', base_config)

      assert.equals('atcoder', context.contest)
      assert.equals('abc123', context.contest_id)
      assert.equals('a', context.problem_id)
      assert.equals('abc123a', context.problem_name)
      assert.equals('abc123a.cpp', context.source_file)
      assert.equals('build/abc123a.run', context.binary_file)
      assert.equals('io/abc123a.cpin', context.input_file)
      assert.equals('io/abc123a.cpout', context.output_file)
      assert.equals('io/abc123a.expected', context.expected_file)
    end)

    it('handles context without problem_id', function()
      local context = problem.create_context('codeforces', '1933', nil, base_config)

      assert.equals('codeforces', context.contest)
      assert.equals('1933', context.contest_id)
      assert.is_nil(context.problem_id)
      assert.equals('1933', context.problem_name)
      assert.equals('1933.cpp', context.source_file)
      assert.equals('build/1933.run', context.binary_file)
    end)

    it('uses default language from contest config', function()
      local context = problem.create_context('atcoder', 'abc123', 'a', base_config)
      assert.equals('abc123a.cpp', context.source_file)
    end)

    it('respects explicit language parameter', function()
      local context = problem.create_context('atcoder', 'abc123', 'a', base_config, 'python')
      assert.equals('abc123a.py', context.source_file)
    end)

    it('uses custom filename function when provided', function()
      local config_with_custom = vim.tbl_deep_extend('force', base_config, {
        filename = function(contest, contest_id, problem_id)
          return contest .. '_' .. contest_id .. (problem_id and ('_' .. problem_id) or '')
        end,
      })

      local context = problem.create_context('atcoder', 'abc123', 'a', config_with_custom)
      assert.equals('atcoder_abc123_a.cpp', context.source_file)
      assert.equals('atcoder_abc123_a', context.problem_name)
    end)

    it('validates required parameters', function()
      assert.has_error(function()
        problem.create_context(nil, 'abc123', 'a', base_config)
      end)

      assert.has_error(function()
        problem.create_context('atcoder', nil, 'a', base_config)
      end)

      assert.has_error(function()
        problem.create_context('atcoder', 'abc123', 'a', nil)
      end)
    end)

    it('validates contest exists in config', function()
      assert.has_error(function()
        problem.create_context('invalid_contest', 'abc123', 'a', base_config)
      end)
    end)

    it('validates language exists in contest config', function()
      assert.has_error(function()
        problem.create_context('atcoder', 'abc123', 'a', base_config, 'invalid_language')
      end)
    end)

    it('validates default language exists', function()
      local bad_config = {
        contests = {
          test_contest = {
            default_language = 'nonexistent',
          },
        },
      }

      assert.has_error(function()
        problem.create_context('test_contest', 'abc123', 'a', bad_config)
      end)
    end)

    it('validates language extension is configured', function()
      local bad_config = {
        contests = {
          test_contest = {
            default_language = 'cpp',
            cpp = {},
          },
        },
      }

      assert.has_error(function()
        problem.create_context('test_contest', 'abc123', 'a', bad_config)
      end)
    end)

    it('handles complex contest and problem ids', function()
      local context = problem.create_context('atcoder', 'arc123', 'f', base_config)
      assert.equals('arc123f', context.problem_name)
      assert.equals('arc123f.cpp', context.source_file)
      assert.equals('build/arc123f.run', context.binary_file)
    end)

    it('generates correct io file paths', function()
      local context = problem.create_context('atcoder', 'abc123', 'a', base_config)

      assert.equals('io/abc123a.cpin', context.input_file)
      assert.equals('io/abc123a.cpout', context.output_file)
      assert.equals('io/abc123a.expected', context.expected_file)
    end)
  end)
end)
