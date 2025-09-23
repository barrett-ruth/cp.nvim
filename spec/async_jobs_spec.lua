describe('cp.async.jobs', function()
  local jobs
  local spec_helper = require('spec.spec_helper')
  local mock_jobs = {}

  before_each(function()
    spec_helper.setup()
    mock_jobs = {}

    vim.system = function(args, opts, callback)
      local job = {
        kill = function() end,
        args = args,
        opts = opts,
        callback = callback,
      }
      mock_jobs[#mock_jobs + 1] = job
      return job
    end

    jobs = spec_helper.fresh_require('cp.async.jobs')
  end)

  after_each(function()
    spec_helper.teardown()
    mock_jobs = {}
  end)

  describe('job management', function()
    it('starts job with unique ID', function()
      local callback = function() end
      local args = { 'test', 'command' }
      local opts = { cwd = '/test' }

      local job = jobs.start_job('test_job', args, opts, callback)

      assert.is_not_nil(job)
      assert.equals(1, #mock_jobs)
      assert.same(args, mock_jobs[1].args)
      assert.same(opts, mock_jobs[1].opts)
      assert.is_function(mock_jobs[1].callback)
    end)

    it('kills existing job when starting new job with same ID', function()
      local killed = false
      vim.system = function(args, opts, callback)
        return {
          kill = function()
            killed = true
          end,
          args = args,
          opts = opts,
          callback = callback,
        }
      end

      jobs.start_job('same_id', { 'first' }, {}, function() end)
      jobs.start_job('same_id', { 'second' }, {}, function() end)

      assert.is_true(killed)
    end)

    it('kills specific job by ID', function()
      local killed = false
      vim.system = function()
        return {
          kill = function()
            killed = true
          end,
        }
      end

      jobs.start_job('target_job', { 'test' }, {}, function() end)
      jobs.kill_job('target_job')

      assert.is_true(killed)
    end)

    it('kills all active jobs', function()
      local kill_count = 0
      vim.system = function()
        return {
          kill = function()
            kill_count = kill_count + 1
          end,
        }
      end

      jobs.start_job('job1', { 'test1' }, {}, function() end)
      jobs.start_job('job2', { 'test2' }, {}, function() end)
      jobs.kill_all_jobs()

      assert.equals(2, kill_count)
    end)

    it('tracks active job IDs correctly', function()
      jobs.start_job('job1', { 'test1' }, {}, function() end)
      jobs.start_job('job2', { 'test2' }, {}, function() end)

      local active_jobs = jobs.get_active_jobs()
      assert.equals(2, #active_jobs)
      assert.is_true(vim.tbl_contains(active_jobs, 'job1'))
      assert.is_true(vim.tbl_contains(active_jobs, 'job2'))

      jobs.kill_job('job1')
      active_jobs = jobs.get_active_jobs()
      assert.equals(1, #active_jobs)
      assert.is_true(vim.tbl_contains(active_jobs, 'job2'))
    end)
  end)
end)
