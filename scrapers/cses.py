#!/usr/bin/env python3

import json
import re
import sys
from dataclasses import asdict

import backoff
import requests
from bs4 import BeautifulSoup, Tag

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


def denormalize_category_name(category_id: str) -> str:
    category_map = {
        "introductory_problems": "Introductory Problems",
        "sorting_and_searching": "Sorting and Searching",
        "dynamic_programming": "Dynamic Programming",
        "graph_algorithms": "Graph Algorithms",
        "range_queries": "Range Queries",
        "tree_algorithms": "Tree Algorithms",
        "mathematics": "Mathematics",
        "string_algorithms": "String Algorithms",
        "geometry": "Geometry",
        "advanced_techniques": "Advanced Techniques",
    }

    return category_map.get(category_id, category_id.replace("_", " ").title())


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
    category_name = denormalize_category_name(category_id)

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
        return problem_input
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

        # Preserve HTML document order - do not sort

        print(
            f"Found {len(all_categories)} categories with {sum(len(probs) for probs in all_categories.values())} problems",
            file=sys.stderr,
        )
        return all_categories

    except Exception as e:
        print(f"Failed to scrape CSES problems: {e}", file=sys.stderr)
        return {}


def extract_example_test_case(soup) -> tuple[str, str] | None:
    example_header = soup.find("h1", string="Example")
    if not example_header:
        return None

    current = example_header.find_next_sibling()
    input_text = None
    output_text = None

    while current:
        if current.name == "p" and "Input:" in current.get_text():
            input_pre = current.find_next_sibling("pre")
            if input_pre:
                input_text = input_pre.get_text().strip()
        elif current.name == "p" and "Output:" in current.get_text():
            output_pre = current.find_next_sibling("pre")
            if output_pre:
                output_text = output_pre.get_text().strip()
                break
        current = current.find_next_sibling()

    if not input_text or not output_text:
        return None

    return (input_text, output_text)


def scrape(url: str) -> list[TestCase]:
    try:
        headers = {
            "User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
        }

        response = make_request(url, headers)

        soup = BeautifulSoup(response.text, "html.parser")

        test_case = extract_example_test_case(soup)
        if not test_case:
            return []

        input_text, output_text = test_case
        return [TestCase(input=input_text, expected=output_text)]

    except Exception as e:
        print(f"Error scraping CSES: {e}", file=sys.stderr)
        return []


def main() -> None:
    if len(sys.argv) < 2:
        result = MetadataResult(
            success=False,
            error="Usage: cses.py metadata <category_id> OR cses.py tests <category> <problem_id> OR cses.py contests",
        )
        print(json.dumps(asdict(result)))
        sys.exit(1)

    mode: str = sys.argv[1]

    if mode == "metadata":
        if len(sys.argv) != 3:
            result = MetadataResult(
                success=False,
                error="Usage: cses.py metadata <category_id>",
            )
            print(json.dumps(asdict(result)))
            sys.exit(1)

        category_id = sys.argv[2]
        problems = scrape_category_problems(category_id)

        if not problems:
            result = MetadataResult(
                success=False,
                error=f"No problems found for category: {category_id}",
            )
            print(json.dumps(asdict(result)))
            return

        result = MetadataResult(success=True, error="", problems=problems)
        print(json.dumps(asdict(result)))

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

        problem_input: str = sys.argv[3]
        url: str | None = parse_problem_url(problem_input)

        if not url:
            tests_result = TestsResult(
                success=False,
                error=f"Invalid problem input: {problem_input}. Use either problem ID (e.g., 1068) or full URL",
                problem_id=problem_input if problem_input.isdigit() else "",
                url="",
                tests=[],
                timeout_ms=0,
                memory_mb=0,
            )
            print(json.dumps(asdict(tests_result)))
            sys.exit(1)

        tests: list[TestCase] = scrape(url)

        problem_id: str = (
            problem_input if problem_input.isdigit() else problem_input.split("/")[-1]
        )

        try:
            headers = {
                "User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
            }
            response = requests.get(url, headers=headers, timeout=10)
            response.raise_for_status()
            soup = BeautifulSoup(response.text, "html.parser")
            timeout_ms, memory_mb = extract_problem_limits(soup)
        except Exception as e:
            tests_result = TestsResult(
                success=False,
                error=f"Failed to extract constraints: {e}",
                problem_id=problem_id,
                url=url,
                tests=[],
                timeout_ms=0,
                memory_mb=0,
            )
            print(json.dumps(asdict(tests_result)))
            sys.exit(1)

        if not tests:
            tests_result = TestsResult(
                success=False,
                error=f"No tests found for {problem_input}",
                problem_id=problem_id,
                url=url,
                tests=[],
                timeout_ms=timeout_ms,
                memory_mb=memory_mb,
            )
            print(json.dumps(asdict(tests_result)))
            sys.exit(1)

        test_cases = tests
        tests_result = TestsResult(
            success=True,
            error="",
            problem_id=problem_id,
            url=url,
            tests=test_cases,
            timeout_ms=timeout_ms,
            memory_mb=memory_mb,
        )
        print(json.dumps(asdict(tests_result)))

    elif mode == "contests":
        if len(sys.argv) != 2:
            contest_result = ContestListResult(
                success=False, error="Usage: cses.py contests"
            )
            print(json.dumps(asdict(contest_result)))
            sys.exit(1)

        categories = scrape_categories()
        if not categories:
            contest_result = ContestListResult(success=False, error="No contests found")
            print(json.dumps(asdict(contest_result)))
            sys.exit(1)

        contest_result = ContestListResult(success=True, error="", contests=categories)
        print(json.dumps(asdict(contest_result)))

    else:
        result = MetadataResult(
            success=False,
            error=f"Unknown mode: {mode}. Use 'metadata <category>', 'tests <category> <problem_id>', or 'contests'",
        )
        print(json.dumps(asdict(result)))
        sys.exit(1)


if __name__ == "__main__":
    main()
