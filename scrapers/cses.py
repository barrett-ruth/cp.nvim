#!/usr/bin/env python3

import json
import re
import sys
from dataclasses import asdict

import backoff
import requests
from bs4 import BeautifulSoup, Tag

from .base import BaseScraper
from .models import (
    ContestListResult,
    ContestSummary,
    MetadataResult,
    ProblemSummary,
    TestCase,
    TestsResult,
)


def normalize_category_name(category_name: str) -> str:
    return category_name.lower().replace(" ", "_").replace("&", "and")


def snake_to_title(name: str) -> str:
    small_words = {
        "a",
        "an",
        "the",
        "and",
        "but",
        "or",
        "nor",
        "for",
        "so",
        "yet",
        "at",
        "by",
        "in",
        "of",
        "on",
        "per",
        "to",
        "vs",
        "via",
    }
    words: list[str] = name.split("_")
    n = len(words)

    def fix_word(i_word):
        i, word = i_word
        lw = word.lower()
        return lw.capitalize() if i == 0 or i == n - 1 or lw not in small_words else lw

    return " ".join(map(fix_word, enumerate(words)))


@backoff.on_exception(
    backoff.expo,
    (requests.exceptions.RequestException, requests.exceptions.HTTPError),
    max_tries=4,
    jitter=backoff.random_jitter,
    on_backoff=lambda details: print(
        f"Request failed (attempt {details['tries']}), retrying in {details['wait']:.1f}s: {details['exception']}",
        file=sys.stderr,
    ),
)
@backoff.on_predicate(
    backoff.expo,
    lambda response: response.status_code == 429,
    max_tries=4,
    jitter=backoff.random_jitter,
    on_backoff=lambda details: print(
        f"Rate limited, retrying in {details['wait']:.1f}s", file=sys.stderr
    ),
)
def make_request(url: str, headers: dict) -> requests.Response:
    response = requests.get(url, headers=headers, timeout=10)
    response.raise_for_status()
    return response


def scrape_category_problems(category_id: str) -> list[ProblemSummary]:
    category_name = snake_to_title(category_id)
    try:
        problemset_url = "https://cses.fi/problemset/"
        headers = {
            "User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
        }
        response = make_request(problemset_url, headers)
        soup = BeautifulSoup(response.text, "html.parser")
        current_category = None
        problems = []
        target_found = False
        for element in soup.find_all(["h1", "h2", "ul"]):
            if not isinstance(element, Tag):
                continue
            if element.name in ["h1", "h2"]:
                text = element.get_text(strip=True)
                if not text or text.startswith("CSES") or text == "CSES Problem Set":
                    continue
                if target_found and current_category != text:
                    break
                current_category = text
                if text.lower() == category_name.lower():
                    target_found = True
            elif element.name == "ul" and current_category and target_found:
                problem_links = element.find_all(
                    "a", href=lambda x: x and "/problemset/task/" in x
                )
                for link in problem_links:
                    href = link.get("href", "")
                    if not href:
                        continue
                    problem_id = href.split("/")[-1]
                    problem_name = link.get_text(strip=True)
                    if not problem_id.isdigit() or not problem_name:
                        continue
                    problems.append(ProblemSummary(id=problem_id, name=problem_name))
        return problems
    except Exception as e:
        print(f"Failed to scrape CSES category {category_id}: {e}", file=sys.stderr)
        return []


def parse_problem_url(problem_input: str) -> str | None:
    if problem_input.startswith("https://cses.fi/problemset/task/"):
        return problem_input.rstrip("/")
    elif problem_input.isdigit():
        return f"https://cses.fi/problemset/task/{problem_input}"
    return None


def extract_problem_limits(soup: BeautifulSoup) -> tuple[int, float]:
    timeout_ms = None
    memory_mb = None
    constraints_ul = soup.find("ul", class_="task-constraints")
    if not constraints_ul or not isinstance(constraints_ul, Tag):
        raise ValueError("Could not find task-constraints section")
    for li in constraints_ul.find_all("li"):
        text = li.get_text()
        if "Time limit:" in text:
            match = re.search(r"Time limit:\s*(\d+(?:\.\d+)?)\s*s", text)
            if match:
                seconds = float(match.group(1))
                timeout_ms = int(seconds * 1000)
        if "Memory limit:" in text:
            match = re.search(r"Memory limit:\s*(\d+)\s*MB", text)
            if match:
                memory_mb = float(match.group(1))
    if timeout_ms is None:
        raise ValueError("Could not find valid timeout in task-constraints section")
    if memory_mb is None:
        raise ValueError(
            "Could not find valid memory limit in task-constraints section"
        )
    return timeout_ms, memory_mb


def scrape_categories() -> list[ContestSummary]:
    try:
        headers = {
            "User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
        }
        response = make_request("https://cses.fi/problemset/", headers)
        soup = BeautifulSoup(response.text, "html.parser")
        categories = []
        for h2 in soup.find_all("h2"):
            category_name = h2.get_text().strip()
            if category_name == "General":
                continue
            category_id = normalize_category_name(category_name)
            display_name = category_name
            categories.append(
                ContestSummary(
                    id=category_id, name=category_name, display_name=display_name
                )
            )
        return categories
    except Exception as e:
        print(f"Failed to scrape CSES categories: {e}", file=sys.stderr)
        return []


def process_problem_element(
    element,
    current_category: str | None,
    all_categories: dict[str, list[ProblemSummary]],
) -> str | None:
    if element.name == "h1":
        category_name = element.get_text().strip()
        if category_name not in all_categories:
            all_categories[category_name] = []
        return category_name
    if element.name != "a" or "/problemset/task/" not in element.get("href", ""):
        return current_category
    href = element.get("href", "")
    if not href:
        return current_category
    problem_id = href.split("/")[-1]
    problem_name = element.get_text(strip=True)
    if not (problem_id.isdigit() and problem_name and current_category):
        return current_category
    problem = ProblemSummary(id=problem_id, name=problem_name)
    all_categories[current_category].append(problem)
    return current_category


def scrape_all_problems() -> dict[str, list[ProblemSummary]]:
    try:
        problemset_url = "https://cses.fi/problemset/"
        headers = {
            "User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
        }
        response = requests.get(problemset_url, headers=headers, timeout=10)
        response.raise_for_status()
        soup = BeautifulSoup(response.text, "html.parser")
        all_categories: dict[str, list[ProblemSummary]] = {}
        current_category = None
        for element in soup.find_all(["h1", "h2", "ul"]):
            if not isinstance(element, Tag):
                continue
            if element.name in ["h1", "h2"]:
                text = element.get_text(strip=True)
                if text and not text.startswith("CSES") and text != "CSES Problem Set":
                    current_category = text
                    if current_category not in all_categories:
                        all_categories[current_category] = []
                        print(f"Found category: {current_category}", file=sys.stderr)
            elif element.name == "ul" and current_category:
                problem_links = element.find_all(
                    "a", href=lambda x: x and "/problemset/task/" in x
                )
                for link in problem_links:
                    href = link.get("href", "")
                    if href:
                        problem_id = href.split("/")[-1]
                        problem_name = link.get_text(strip=True)
                        if problem_id.isdigit() and problem_name:
                            problem = ProblemSummary(id=problem_id, name=problem_name)
                            all_categories[current_category].append(problem)
        print(
            f"Found {len(all_categories)} categories with {sum(len(probs) for probs in all_categories.values())} problems",
            file=sys.stderr,
        )
        return all_categories
    except Exception as e:
        print(f"Failed to scrape CSES problems: {e}", file=sys.stderr)
        return {}


def _collect_section_after(header: Tag) -> list[Tag]:
    out: list[Tag] = []
    cur = header.find_next_sibling()
    while cur and not (isinstance(cur, Tag) and cur.name in ("h1", "h2", "h3")):
        if isinstance(cur, Tag):
            out.append(cur)
        cur = cur.find_next_sibling()
    return out


def extract_example_test_cases(soup: BeautifulSoup) -> list[tuple[str, str]]:
    example_headers = soup.find_all(
        lambda t: isinstance(t, Tag)
        and t.name in ("h1", "h2", "h3")
        and t.get_text(strip=True).lower().startswith("example")
    )
    cases: list[tuple[str, str]] = []
    for hdr in example_headers:
        section = _collect_section_after(hdr)

        def find_labeled(label: str) -> str | None:
            for node in section:
                if not isinstance(node, Tag):
                    continue
                if node.name in ("p", "h4", "h5", "h6"):
                    txt = node.get_text(strip=True).lower().rstrip(":")
                    if txt == label:
                        pre = node.find_next_sibling("pre")
                        if pre:
                            return pre.get_text().strip()
            return None

        inp = find_labeled("input")
        out = find_labeled("output")
        if not inp or not out:
            pres = [n for n in section if isinstance(n, Tag) and n.name == "pre"]
            if len(pres) >= 2:
                inp = inp or pres[0].get_text().strip()
                out = out or pres[1].get_text().strip()
        if inp and out:
            cases.append((inp, out))
    return cases


def scrape(url: str) -> list[TestCase]:
    try:
        headers = {
            "User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
        }
        response = make_request(url, headers)
        soup = BeautifulSoup(response.text, "html.parser")
        pairs = extract_example_test_cases(soup)
        return [TestCase(input=inp, expected=out) for (inp, out) in pairs]
    except Exception as e:
        print(f"Error scraping CSES: {e}", file=sys.stderr)
        return []


class CSESScraper(BaseScraper):
    @property
    def platform_name(self) -> str:
        return "cses"

    def scrape_contest_metadata(self, contest_id: str) -> MetadataResult:
        return self._safe_execute("metadata", self._scrape_metadata_impl, contest_id)

    def scrape_problem_tests(self, contest_id: str, problem_id: str) -> TestsResult:
        return self._safe_execute(
            "tests", self._scrape_tests_impl, contest_id, problem_id
        )

    def scrape_contest_list(self) -> ContestListResult:
        return self._safe_execute("contests", self._scrape_contests_impl)

    def _safe_execute(self, operation: str, func, *args):
        try:
            return func(*args)
        except Exception as e:
            error_msg = f"{self.platform_name}: {str(e)}"
            if operation == "metadata":
                return MetadataResult(success=False, error=error_msg)
            elif operation == "tests":
                return TestsResult(
                    success=False,
                    error=error_msg,
                    problem_id="",
                    url="",
                    tests=[],
                    timeout_ms=0,
                    memory_mb=0,
                )
            elif operation == "contests":
                return ContestListResult(success=False, error=error_msg)

    def _scrape_metadata_impl(self, category_id: str) -> MetadataResult:
        problems = scrape_category_problems(category_id)
        if not problems:
            return MetadataResult(
                success=False,
                error=f"{self.platform_name}: No problems found for category: {category_id}",
            )
        return MetadataResult(
            success=True, error="", contest_id=category_id, problems=problems
        )

    def _scrape_tests_impl(self, category: str, problem_id: str) -> TestsResult:
        url = parse_problem_url(problem_id)
        if not url:
            return TestsResult(
                success=False,
                error=f"{self.platform_name}: Invalid problem input: {problem_id}. Use either problem ID (e.g., 1068) or full URL",
                problem_id=problem_id if problem_id.isdigit() else "",
                url="",
                tests=[],
                timeout_ms=0,
                memory_mb=0,
            )
        tests = scrape(url)
        m = re.search(r"/task/(\d+)", url)
        actual_problem_id = (
            problem_id if problem_id.isdigit() else (m.group(1) if m else "")
        )
        headers = {
            "User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
        }
        response = requests.get(url, headers=headers, timeout=10)
        response.raise_for_status()
        soup = BeautifulSoup(response.text, "html.parser")
        timeout_ms, memory_mb = extract_problem_limits(soup)
        if not tests:
            return TestsResult(
                success=False,
                error=f"{self.platform_name}: No tests found for {problem_id}",
                problem_id=actual_problem_id,
                url=url,
                tests=[],
                timeout_ms=timeout_ms,
                memory_mb=memory_mb,
            )
        return TestsResult(
            success=True,
            error="",
            problem_id=actual_problem_id,
            url=url,
            tests=tests,
            timeout_ms=timeout_ms,
            memory_mb=memory_mb,
        )

    def _scrape_contests_impl(self) -> ContestListResult:
        categories = scrape_categories()
        if not categories:
            return ContestListResult(
                success=False, error=f"{self.platform_name}: No contests found"
            )
        return ContestListResult(success=True, error="", contests=categories)


def main() -> None:
    if len(sys.argv) < 2:
        result = MetadataResult(
            success=False,
            error="Usage: cses.py metadata <category_id> OR cses.py tests <category> <problem_id> OR cses.py contests",
        )
        print(json.dumps(asdict(result)))
        sys.exit(1)
    mode: str = sys.argv[1]
    scraper = CSESScraper()
    if mode == "metadata":
        if len(sys.argv) != 3:
            result = MetadataResult(
                success=False,
                error="Usage: cses.py metadata <category_id>",
            )
            print(json.dumps(asdict(result)))
            sys.exit(1)
        category_id = sys.argv[2]
        result = scraper.scrape_contest_metadata(category_id)
        print(json.dumps(asdict(result)))
        if not result.success:
            sys.exit(1)
    elif mode == "tests":
        if len(sys.argv) != 4:
            tests_result = TestsResult(
                success=False,
                error="Usage: cses.py tests <category> <problem_id>",
                problem_id="",
                url="",
                tests=[],
                timeout_ms=0,
                memory_mb=0,
            )
            print(json.dumps(asdict(tests_result)))
            sys.exit(1)
        category = sys.argv[2]
        problem_id = sys.argv[3]
        tests_result = scraper.scrape_problem_tests(category, problem_id)
        print(json.dumps(asdict(tests_result)))
        if not tests_result.success:
            sys.exit(1)
    elif mode == "contests":
        if len(sys.argv) != 2:
            contest_result = ContestListResult(
                success=False, error="Usage: cses.py contests"
            )
            print(json.dumps(asdict(contest_result)))
            sys.exit(1)
        contest_result = scraper.scrape_contest_list()
        print(json.dumps(asdict(contest_result)))
        if not contest_result.success:
            sys.exit(1)
    else:
        result = MetadataResult(
            success=False,
            error=f"Unknown mode: {mode}. Use 'metadata <category>', 'tests <category> <problem_id>', or 'contests'",
        )
        print(json.dumps(asdict(result)))
        sys.exit(1)


if __name__ == "__main__":
    main()
