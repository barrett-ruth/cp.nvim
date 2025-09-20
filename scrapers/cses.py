#!/usr/bin/env python3

import json
import re
import sys
from dataclasses import asdict

import requests
from bs4 import BeautifulSoup, Tag

from scrapers.models import MetadataResult, ProblemSummary, TestCase, TestsResult


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

        problem_links = soup.find_all(
            "a", href=lambda x: x and "/problemset/task/" in x
        )
        print(f"Found {len(problem_links)} problem links", file=sys.stderr)

        current_category = None
        for element in soup.find_all(["h1", "a"]):
            current_category = process_problem_element(
                element, current_category, all_categories
            )

        for category in all_categories:
            all_categories[category].sort(key=lambda x: int(x.id))

        print(f"Found {len(all_categories)} categories", file=sys.stderr)
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

        response = requests.get(url, headers=headers, timeout=10)
        response.raise_for_status()

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
            error="Usage: cses.py metadata OR cses.py tests <problem_id_or_url>",
        )
        print(json.dumps(asdict(result)))
        sys.exit(1)

    mode: str = sys.argv[1]

    if mode == "metadata":
        if len(sys.argv) != 2:
            result = MetadataResult(
                success=False,
                error="Usage: cses.py metadata",
            )
            print(json.dumps(asdict(result)))
            sys.exit(1)

        all_categories: dict[str, list[ProblemSummary]] = scrape_all_problems()

        if not all_categories:
            result = MetadataResult(
                success=False,
                error="Failed to scrape CSES problem categories",
            )
            print(json.dumps(asdict(result)))
            sys.exit(1)

        result = MetadataResult(success=True, error="", categories=all_categories)
        print(json.dumps(asdict(result)))

    elif mode == "tests":
        if len(sys.argv) != 3:
            tests_result = TestsResult(
                success=False,
                error="Usage: cses.py tests <problem_id_or_url>",
                problem_id="",
                url="",
                tests=[],
                timeout_ms=0,
                memory_mb=0,
            )
            print(json.dumps(asdict(tests_result)))
            sys.exit(1)

        problem_input: str = sys.argv[2]
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

    else:
        result = MetadataResult(
            success=False,
            error=f"Unknown mode: {mode}. Use 'metadata' or 'tests'",
        )
        print(json.dumps(asdict(result)))
        sys.exit(1)


if __name__ == "__main__":
    main()
