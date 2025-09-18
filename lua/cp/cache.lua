---@class CacheData
---@field [string] table<string, ContestData>

---@class ContestData
---@field problems Problem[]
---@field scraped_at string
---@field expires_at? number
---@field test_cases? CachedTestCase[]
---@field test_cases_cached_at? number

---@class Problem
---@field id string
---@field name? string

---@class CachedTestCase
---@field index? number
---@field input string
---@field expected? string
---@field output? string

local M = {}

local cache_file = vim.fn.stdpath("data") .. "/cp-nvim.json"
local cache_data = {}

---@param platform string
---@return number?
local function get_expiry_date(platform)
	vim.validate({
		platform = { platform, "string" },
	})

	if platform == "cses" then
		return os.time() + (30 * 24 * 60 * 60)
	end
	return nil
end

---@param contest_data ContestData
---@param platform string
---@return boolean
local function is_cache_valid(contest_data, platform)
	vim.validate({
		contest_data = { contest_data, "table" },
		platform = { platform, "string" },
	})

	if platform ~= "cses" then
		return true
	end

	local expires_at = contest_data.expires_at
	if not expires_at then
		return false
	end

	return os.time() < expires_at
end

function M.load()
	if vim.fn.filereadable(cache_file) == 0 then
		cache_data = {}
		return
	end

	local content = vim.fn.readfile(cache_file)
	if #content == 0 then
		cache_data = {}
		return
	end

	local ok, decoded = pcall(vim.json.decode, table.concat(content, "\n"))
	if ok then
		cache_data = decoded
	else
		cache_data = {}
	end
end

function M.save()
	vim.fn.mkdir(vim.fn.fnamemodify(cache_file, ":h"), "p")
	local encoded = vim.json.encode(cache_data)
	vim.fn.writefile(vim.split(encoded, "\n"), cache_file)
end

---@param platform string
---@param contest_id string
---@return ContestData?
function M.get_contest_data(platform, contest_id)
	vim.validate({
		platform = { platform, "string" },
		contest_id = { contest_id, "string" },
	})

	if not cache_data[platform] then
		return nil
	end

	local contest_data = cache_data[platform][contest_id]
	if not contest_data then
		return nil
	end

	if not is_cache_valid(contest_data, platform) then
		return nil
	end

	return contest_data
end

---@param platform string
---@param contest_id string
---@param problems Problem[]
function M.set_contest_data(platform, contest_id, problems)
	vim.validate({
		platform = { platform, "string" },
		contest_id = { contest_id, "string" },
		problems = { problems, "table" },
	})

	if not cache_data[platform] then
		cache_data[platform] = {}
	end

	cache_data[platform][contest_id] = {
		problems = problems,
		scraped_at = os.date("%Y-%m-%d"),
		expires_at = get_expiry_date(platform),
	}

	M.save()
end

---@param platform string
---@param contest_id string
function M.clear_contest_data(platform, contest_id)
	vim.validate({
		platform = { platform, "string" },
		contest_id = { contest_id, "string" },
	})

	if cache_data[platform] and cache_data[platform][contest_id] then
		cache_data[platform][contest_id] = nil
		M.save()
	end
end

---@param platform string
---@param contest_id string
---@param problem_id? string
---@return CachedTestCase[]?
function M.get_test_cases(platform, contest_id, problem_id)
	vim.validate({
		platform = { platform, "string" },
		contest_id = { contest_id, "string" },
		problem_id = { problem_id, { "string", "nil" }, true },
	})

	local problem_key = problem_id and (contest_id .. "_" .. problem_id) or contest_id
	if not cache_data[platform] or not cache_data[platform][problem_key] then
		return nil
	end
	return cache_data[platform][problem_key].test_cases
end

---@param platform string
---@param contest_id string
---@param problem_id? string
---@param test_cases CachedTestCase[]
function M.set_test_cases(platform, contest_id, problem_id, test_cases)
	vim.validate({
		platform = { platform, "string" },
		contest_id = { contest_id, "string" },
		problem_id = { problem_id, { "string", "nil" }, true },
		test_cases = { test_cases, "table" },
	})

	local problem_key = problem_id and (contest_id .. "_" .. problem_id) or contest_id
	if not cache_data[platform] then
		cache_data[platform] = {}
	end
	if not cache_data[platform][problem_key] then
		cache_data[platform][problem_key] = {}
	end

	cache_data[platform][problem_key].test_cases = test_cases
	cache_data[platform][problem_key].test_cases_cached_at = os.time()
	M.save()
end

return M
