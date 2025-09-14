local M = {}
local logger = require("cp.log")

function M.setup(config)
	local ok, ls = pcall(require, "luasnip")
	if not ok then
		logger.log("LuaSnip not available - snippets disabled", vim.log.levels.INFO)
		return
	end

	local s, i, fmt = ls.snippet, ls.insert_node, require("luasnip.extras.fmt").fmt

	local default_snippets = {
		s(
			"codeforces",
			fmt(
				[[#include <bits/stdc++.h>

using namespace std;

void solve() {{
  {}
}}

int main() {{
  std::cin.tie(nullptr)->sync_with_stdio(false);

  int tc = 1;
  std::cin >> tc;

  for (int t = 0; t < tc; ++t) {{
    solve();
  }}

  return 0;
}}]],
				{ i(1) }
			)
		),

		s(
			"atcoder",
			fmt(
				[[#include <bits/stdc++.h>

using namespace std;

void solve() {{
  {}
}}

int main() {{
  std::cin.tie(nullptr)->sync_with_stdio(false);

#ifdef LOCAL
  int tc;
  std::cin >> tc;

  for (int t = 0; t < tc; ++t) {{
    solve();
  }}
#else
  solve();
#endif

  return 0;
}}]],
				{ i(1) }
			)
		),

		s(
			"cses",
			fmt(
				[[#include <bits/stdc++.h>

using namespace std;

int main() {{
  std::cin.tie(nullptr)->sync_with_stdio(false);

  {}

  return 0;
}}]],
				{ i(1) }
			)
		),
	}

	local default_map = {}
	for _, snippet in pairs(default_snippets) do
		default_map[snippet.trigger] = snippet
	end

	local user_map = {}
	for _, snippet in pairs(config.snippets or {}) do
		user_map[snippet.trigger] = snippet
	end

	local merged_map = vim.tbl_extend("force", default_map, user_map)

	local all_snippets = {}
	for _, snippet in pairs(merged_map) do
		table.insert(all_snippets, snippet)
	end

	ls.add_snippets("cpp", all_snippets)
end

return M
