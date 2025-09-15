local M = {}
local logger = require('cp.log')
local cache = require('cp.cache')

local function get_plugin_path()
    local plugin_path = debug.getinfo(1, 'S').source:sub(2)
    return vim.fn.fnamemodify(plugin_path, ':h:h:h')
end

local function ensure_io_directory()
    vim.fn.mkdir('io', 'p')
end

local function check_internet_connectivity()
    local result = vim.system(
        { 'ping', '-c', '1', '-W', '3', '8.8.8.8' },
        { text = true }
    ):wait()
    return result.code == 0
end

local function setup_python_env()
    local plugin_path = get_plugin_path()
    local venv_dir = plugin_path .. '/.venv'

    if vim.fn.executable('uv') == 0 then
        logger.log(
            'uv is not installed. Install it to enable problem scraping: https://docs.astral.sh/uv/',
            vim.log.levels.WARN
        )
        return false
    end

    if vim.fn.isdirectory(venv_dir) == 0 then
        logger.log('setting up Python environment for scrapers...')
        local result = vim.system(
            { 'uv', 'sync' },
            { cwd = plugin_path, text = true }
        )
            :wait()
        if result.code ~= 0 then
            logger.log(
                'failed to setup Python environment: ' .. result.stderr,
                vim.log.levels.ERROR
            )
            return false
        end
        logger.log('python environment setup complete')
    end

    return true
end

---@param platform string
---@param contest_id string
---@return {success: boolean, problems?: table[], error?: string}
function M.scrape_contest_metadata(platform, contest_id)
    vim.validate({
        platform = { platform, 'string' },
        contest_id = { contest_id, 'string' },
    })

    cache.load()

    local cached_data = cache.get_contest_data(platform, contest_id)
    if cached_data then
        return {
            success = true,
            problems = cached_data.problems,
        }
    end

    if not check_internet_connectivity() then
        return {
            success = false,
            error = 'No internet connection available',
        }
    end

    if not setup_python_env() then
        return {
            success = false,
            error = 'Python environment setup failed',
        }
    end

    local plugin_path = get_plugin_path()
    local scraper_path = plugin_path .. '/scrapers/' .. platform .. '.py'

    local args
    if platform == 'cses' then
        args = {
            'uv',
            'run',
            '--directory',
            plugin_path,
            scraper_path,
            'metadata',
        }
    else
        args = {
            'uv',
            'run',
            '--directory',
            plugin_path,
            scraper_path,
            'metadata',
            contest_id,
        }
    end

    local result = vim.system(args, {
        cwd = plugin_path,
        text = true,
        timeout = 30000,
    }):wait()

    if result.code ~= 0 then
        return {
            success = false,
            error = 'Failed to run metadata scraper: '
                .. (result.stderr or 'Unknown error'),
        }
    end

    local ok, data = pcall(vim.json.decode, result.stdout)
    if not ok then
        return {
            success = false,
            error = 'Failed to parse metadata scraper output: '
                .. tostring(data),
        }
    end

    if not data.success then
        return data
    end

    local problems_list
    if platform == 'cses' then
        problems_list = data.categories and data.categories['CSES Problem Set']
            or {}
    else
        problems_list = data.problems or {}
    end

    cache.set_contest_data(platform, contest_id, problems_list)
    return {
        success = true,
        problems = problems_list,
    }
end

---@param ctx ProblemContext
---@return {success: boolean, problem_id: string, test_count?: number, test_cases?: table[], url?: string, error?: string}
function M.scrape_problem(ctx)
    vim.validate({
        ctx = { ctx, 'table' },
    })

    ensure_io_directory()

    if
        vim.fn.filereadable(ctx.input_file) == 1
        and vim.fn.filereadable(ctx.expected_file) == 1
    then
        return {
            success = true,
            problem_id = ctx.problem_name,
            test_count = 1,
        }
    end

    if not check_internet_connectivity() then
        return {
            success = false,
            problem_id = ctx.problem_name,
            error = 'No internet connection available',
        }
    end

    if not setup_python_env() then
        return {
            success = false,
            problem_id = ctx.problem_name,
            error = 'Python environment setup failed',
        }
    end

    local plugin_path = get_plugin_path()
    local scraper_path = plugin_path .. '/scrapers/' .. ctx.contest .. '.py'

    local args
    if ctx.contest == 'cses' then
        args = {
            'uv',
            'run',
            '--directory',
            plugin_path,
            scraper_path,
            'tests',
            ctx.contest_id,
        }
    else
        args = {
            'uv',
            'run',
            '--directory',
            plugin_path,
            scraper_path,
            'tests',
            ctx.contest_id,
            ctx.problem_id,
        }
    end

    local result = vim.system(args, {
        cwd = plugin_path,
        text = true,
        timeout = 30000,
    }):wait()

    if result.code ~= 0 then
        return {
            success = false,
            problem_id = ctx.problem_name,
            error = 'Failed to run tests scraper: '
                .. (result.stderr or 'Unknown error'),
        }
    end

    local ok, data = pcall(vim.json.decode, result.stdout)
    if not ok then
        return {
            success = false,
            problem_id = ctx.problem_name,
            error = 'Failed to parse tests scraper output: ' .. tostring(data),
        }
    end

    if not data.success then
        return data
    end

    if data.test_cases and #data.test_cases > 0 then
        local combined_input = data.test_cases[1].input:gsub('\r', '')
        local combined_output = data.test_cases[1].output:gsub('\r', '')

        vim.fn.writefile(vim.split(combined_input, '\n', true), ctx.input_file)
        vim.fn.writefile(
            vim.split(combined_output, '\n', true),
            ctx.expected_file
        )
    end

    return {
        success = true,
        problem_id = ctx.problem_name,
        test_count = data.test_cases and #data.test_cases or 0,
        test_cases = data.test_cases,
        url = data.url,
    }
end

return M
