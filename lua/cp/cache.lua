local M = {}

local cache_file = vim.fn.stdpath("data") .. "/cp-contest-cache.json"
local cache_data = {}

local function get_expiry_date(contest_type)
	if contest_type == "cses" then
		return os.time() + (30 * 24 * 60 * 60)
	end
	return nil
end

local function is_cache_valid(contest_data, contest_type)
	if contest_type ~= "cses" then
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

function M.get_contest_data(contest_type, contest_id)
	if not cache_data[contest_type] then
		return nil
	end

	local contest_data = cache_data[contest_type][contest_id]
	if not contest_data then
		return nil
	end

	if not is_cache_valid(contest_data, contest_type) then
		return nil
	end

	return contest_data
end

function M.set_contest_data(contest_type, contest_id, problems)
	if not cache_data[contest_type] then
		cache_data[contest_type] = {}
	end

	cache_data[contest_type][contest_id] = {
		problems = problems,
		scraped_at = os.date("%Y-%m-%d"),
		expires_at = get_expiry_date(contest_type),
	}

	M.save()
end

function M.clear_contest_data(contest_type, contest_id)
	if cache_data[contest_type] and cache_data[contest_type][contest_id] then
		cache_data[contest_type][contest_id] = nil
		M.save()
	end
end

return M