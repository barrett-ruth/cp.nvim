local M = {}
local logger = require("cp.log")

function M.setup(config)
	local ok, ls = pcall(require, "luasnip")
	if not ok then
		logger.log("LuaSnip not available - snippets disabled", vim.log.levels.INFO)
		return
	end

	local s, i, fmt = ls.snippet, ls.insert_node, require("luasnip.extras.fmt").fmt

	local constants = require("cp.constants")
	local filetype_to_language = constants.filetype_to_language

	local language_to_filetype = {}
	for ext, lang in pairs(filetype_to_language) do
		if not language_to_filetype[lang] then
			language_to_filetype[lang] = ext
		end
	end

	local template_definitions = {
		cpp = {
			codeforces = [[#include <bits/stdc++.h>

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

			atcoder = [[#include <bits/stdc++.h>

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

			cses = [[#include <bits/stdc++.h>

using namespace std;

int main() {{
  std::cin.tie(nullptr)->sync_with_stdio(false);

  {}

  return 0;
}}]],
		},

		python = {
			codeforces = [[def solve():
    {}

if __name__ == "__main__":
    tc = int(input())
    for _ in range(tc):
        solve()]],

			atcoder = [[def solve():
    {}

if __name__ == "__main__":
    solve()]],

			cses = [[{}]],
		},
	}

	local user_overrides = {}
	for _, snippet in ipairs(config.snippets or {}) do
		user_overrides[snippet.trigger] = snippet
	end

	for language, template_set in pairs(template_definitions) do
		local snippets = {}
		local filetype = constants.canonical_filetypes[language]

		for contest, template in pairs(template_set) do
			local prefixed_trigger = ("cp.nvim/%s.%s"):format(contest, language)
			if not user_overrides[prefixed_trigger] then
				table.insert(snippets, s(prefixed_trigger, fmt(template, { i(1) })))
			end
		end

		for trigger, snippet in pairs(user_overrides) do
			local prefix_match = trigger:match("^cp%.nvim/[^.]+%.(.+)$")
			if prefix_match == language then
				table.insert(snippets, snippet)
			end
		end

		ls.add_snippets(filetype, snippets)
	end
end

return M
