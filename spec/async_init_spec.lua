describe('cp.async.init', function()
  local async
  local spec_helper = require('spec.spec_helper')

  before_each(function()
    spec_helper.setup()
    async = spec_helper.fresh_require('cp.async.init')
  end)

  after_each(function()
    spec_helper.teardown()
  end)

  describe('contest operation guard', function()
    it('allows starting operation when none active', function()
      assert.has_no_errors(function()
        async.start_contest_operation('test_operation')
      end)
      assert.equals('test_operation', async.get_active_operation())
    end)

    it('throws error when starting operation while one is active', function()
      async.start_contest_operation('first_operation')

      assert.has_error(function()
        async.start_contest_operation('second_operation')
      end, "Contest operation 'first_operation' already active, cannot start 'second_operation'")
    end)

    it('allows starting operation after finishing previous one', function()
      async.start_contest_operation('first_operation')
      async.finish_contest_operation()

      assert.has_no_errors(function()
        async.start_contest_operation('second_operation')
      end)
      assert.equals('second_operation', async.get_active_operation())
    end)

    it('correctly reports active operation status', function()
      assert.is_nil(async.get_active_operation())

      async.start_contest_operation('test_operation')
      assert.equals('test_operation', async.get_active_operation())

      async.finish_contest_operation()
      assert.is_nil(async.get_active_operation())
    end)
  end)
end)
