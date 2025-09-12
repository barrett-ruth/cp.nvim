local M = {}

function M.setup(config)
	local ok, ls = pcall(require, "luasnip")
	if not ok then
		vim.notify("[cp.nvim]: LuaSnip not available - snippets disabled", vim.log.levels.INFO)
		return
	end

	local s, i, fmt = ls.snippet, ls.insert_node, require('luasnip.extras.fmt').fmt

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
	}

	local user_snippets = {}
	for _, snippet in pairs(config.snippets or {}) do
		table.insert(user_snippets, snippet)
	end

	local all_snippets = vim.list_extend(default_snippets, user_snippets)
	ls.add_snippets("cpp", all_snippets)
end

return M
