local M = {}
local logger = require("cp.log")

function M.setup(config)
	local ok, ls = pcall(require, "luasnip")
	if not ok then
		logger.log("LuaSnip not available - snippets disabled", vim.log.levels.INFO)
		return
	end

	local s, i, fmt = ls.snippet, ls.insert_node, require("luasnip.extras.fmt").fmt

	local filetype_to_language = {
		cc = "cpp",
		c = "cpp",
		py = "python",
		py3 = "python",
	}

	local language_to_filetype = {}
	for ext, lang in pairs(filetype_to_language) do
		language_to_filetype[lang] = ext
	end

	local template_definitions = {
		cpp = {
			codeforces = [[#include <bits/stdc++.h>

using namespace std;

void solve() {
  {}
}

int main() {
  std::cin.tie(nullptr)->sync_with_stdio(false);

  int tc = 1;
  std::cin >> tc;

  for (int t = 0; t < tc; ++t) {
    solve();
  }

  return 0;
}]],

			atcoder = [[#include <bits/stdc++.h>

using namespace std;

void solve() {
  {}
}

int main() {
  std::cin.tie(nullptr)->sync_with_stdio(false);

#ifdef LOCAL
  int tc;
  std::cin >> tc;

  for (int t = 0; t < tc; ++t) {
    solve();
  }
#else
  solve();
#endif

  return 0;
}]],

			cses = [[#include <bits/stdc++.h>

using namespace std;

int main() {
  std::cin.tie(nullptr)->sync_with_stdio(false);

  {}

  return 0;
}]],
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

	for language, filetype in pairs(language_to_filetype) do
		local snippets = {}

		for contest, template in pairs(template_definitions[language] or {}) do
			table.insert(snippets, s(contest, fmt(template, { i(1) })))
		end

		for _, snippet in ipairs(config.snippets or {}) do
			if snippet.filetype == filetype then
				table.insert(snippets, snippet)
			end
		end

		ls.add_snippets(filetype, snippets)
	end
end

return M
