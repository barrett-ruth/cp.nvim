#!/usr/bin/env python3

import json
import re
import sys
import time
from dataclasses import asdict

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


def extract_problem_limits(soup: BeautifulSoup) -> tuple[int, float]:
    timeout_ms = None
    memory_mb = None

    paragraphs = soup.find_all("p")
    for p in paragraphs:
        text = p.get_text()
        if "Time Limit:" in text and "Memory Limit:" in text:
            time_match = re.search(r"Time Limit:\s*(\d+)\s*sec", text)
            if time_match:
                seconds = int(time_match.group(1))
                timeout_ms = seconds * 1000

            memory_match = re.search(r"Memory Limit:\s*(\d+)\s*MiB", text)
            if memory_match:
                memory_mib = int(memory_match.group(1))
                memory_mb = round(memory_mib * 1.048576, 2)
            break

    if timeout_ms is None:
        raise ValueError("Could not find valid timeout in problem constraints")

    if memory_mb is None:
        raise ValueError("Could not find valid memory limit in problem constraints")

    return timeout_ms, memory_mb


def parse_problem_url(contest_id: str, problem_letter: str) -> str:
    task_id: str = f"{contest_id}_{problem_letter}"
    return f"https://atcoder.jp/contests/{contest_id}/tasks/{task_id}"


def extract_problem_from_row(row, contest_id: str) -> ProblemSummary | None:
    cells = row.find_all("td")
    if len(cells) < 2:
        return None

    task_link = cells[1].find("a")
    if not task_link:
        return None

    task_name = task_link.get_text(strip=True)
    task_href = task_link.get("href", "")
    if not task_href:
        return None

    task_id = task_href.split("/")[-1]
    if not task_id.startswith(contest_id + "_"):
        return None

    problem_letter = task_id[len(contest_id) + 1 :]
    if not problem_letter or not task_name:
        return None

    return ProblemSummary(id=problem_letter.lower(), name=task_name)


def scrape_contest_problems(contest_id: str) -> list[ProblemSummary]:
    try:
        contest_url = f"https://atcoder.jp/contests/{contest_id}/tasks"
        headers = {
            "User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
        }

        response = requests.get(contest_url, headers=headers, timeout=10)
        response.raise_for_status()

        soup = BeautifulSoup(response.text, "html.parser")
        task_table = soup.find("table", class_="table")
        if not task_table or not isinstance(task_table, Tag):
            return []

        rows = task_table.find_all("tr")[1:]
        problems: list[ProblemSummary] = []
        for row in rows:
            problem = extract_problem_from_row(row, contest_id)
            if problem:
                problems.append(problem)

        problems.sort(key=lambda x: x.id)
        return problems

    except Exception as e:
        print(f"Failed to scrape AtCoder contest problems: {e}", file=sys.stderr)
        return []


def extract_test_case_from_headers(sample_headers, i: int) -> tuple[str, str] | None:
    if i >= len(sample_headers):
        return None

    header = sample_headers[i]
    if "input" not in header.get_text().lower():
        return None

    input_pre = header.find_next("pre")
    if not input_pre or i + 1 >= len(sample_headers):
        return None

    next_header = sample_headers[i + 1]
    if "output" not in next_header.get_text().lower():
        return None

    output_pre = next_header.find_next("pre")
    if not output_pre:
        return None

    input_text = input_pre.get_text().strip().replace("\r", "")
    output_text = output_pre.get_text().strip().replace("\r", "")
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
        sample_headers = soup.find_all(
            "h3", string=lambda x: x and "sample" in x.lower() if x else False
        )

        tests: list[TestCase] = []
        i = 0
        while i < len(sample_headers):
            test_case = extract_test_case_from_headers(sample_headers, i)
            if test_case:
                input_text, output_text = test_case
                tests.append(TestCase(input=input_text, expected=output_text))
                i += 2
            else:
                i += 1

        return tests

    except Exception as e:
        print(f"Error scraping AtCoder: {e}", file=sys.stderr)
        return []


def main() -> None:
    if len(sys.argv) < 2:
        result = MetadataResult(
            success=False,
            error="Usage: atcoder.py metadata <contest_id> OR atcoder.py tests <contest_id> <problem_letter>",
        )
        print(json.dumps(asdict(result)))
        sys.exit(1)

    mode: str = sys.argv[1]

    if mode == "metadata":
        if len(sys.argv) != 3:
            result = MetadataResult(
                success=False,
                error="Usage: atcoder.py metadata <contest_id>",
            )
            print(json.dumps(asdict(result)))
            sys.exit(1)

        contest_id: str = sys.argv[2]
        problems: list[ProblemSummary] = scrape_contest_problems(contest_id)

        if not problems:
            result = MetadataResult(
                success=False,
                error=f"No problems found for contest {contest_id}",
            )
            print(json.dumps(asdict(result)))
            sys.exit(1)

        result = MetadataResult(
            success=True,
            error="",
            contest_id=contest_id,
            problems=problems,
        )
        print(json.dumps(asdict(result)))

    elif mode == "tests":
        if len(sys.argv) != 4:
            tests_result = TestsResult(
                success=False,
                error="Usage: atcoder.py tests <contest_id> <problem_letter>",
                problem_id="",
                url="",
                tests=[],
                timeout_ms=0,
                memory_mb=0,
            )
            print(json.dumps(asdict(tests_result)))
            sys.exit(1)

        test_contest_id: str = sys.argv[2]
        problem_letter: str = sys.argv[3]
        problem_id: str = f"{test_contest_id}_{problem_letter.lower()}"

        url: str = parse_problem_url(test_contest_id, problem_letter)
        tests: list[TestCase] = scrape(url)

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
                error=f"No tests found for {test_contest_id} {problem_letter}",
                problem_id=problem_id,
                url=url,
                tests=[],
                timeout_ms=timeout_ms,
                memory_mb=memory_mb,
            )
            print(json.dumps(asdict(tests_result)))
            sys.exit(1)

        tests_result = TestsResult(
            success=True,
            error="",
            problem_id=problem_id,
            url=url,
            tests=tests,
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
