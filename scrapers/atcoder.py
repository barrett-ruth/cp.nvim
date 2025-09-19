#!/usr/bin/env python3

import json
import sys

import requests
from bs4 import BeautifulSoup, Tag


def parse_problem_url(contest_id: str, problem_letter: str) -> str:
    task_id: str = f"{contest_id}_{problem_letter}"
    return f"https://atcoder.jp/contests/{contest_id}/tasks/{task_id}"


def extract_problem_from_row(row, contest_id: str) -> dict[str, str] | None:
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

    return {"id": problem_letter.lower(), "name": task_name}


def scrape_contest_problems(contest_id: str) -> list[dict[str, str]]:
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

        rows = task_table.find_all("tr")[1:]  # skip header
        problems: list[dict[str, str]] = []
        for row in rows:
            problem = extract_problem_from_row(row, contest_id)
            if problem:
                problems.append(problem)

        problems.sort(key=lambda x: x["id"])
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


def scrape(url: str) -> list[tuple[str, str]]:
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

        tests: list[tuple[str, str]] = []
        i = 0
        while i < len(sample_headers):
            test_case = extract_test_case_from_headers(sample_headers, i)
            if test_case:
                tests.append(test_case)
                i += 2  # move from "Sample Input n" to after "Sample Output n"
            else:
                i += 1

        return tests

    except Exception as e:
        print(f"Error scraping AtCoder: {e}", file=sys.stderr)
        return []


def main() -> None:
    if len(sys.argv) < 2:
        print(
            json.dumps(
                {
                    "success": False,
                    "error": "Usage: atcoder.py metadata <contest_id> OR atcoder.py tests <contest_id> <problem_letter>",
                }
            )
        )
        sys.exit(1)

    mode: str = sys.argv[1]

    if mode == "metadata":
        if len(sys.argv) != 3:
            print(
                json.dumps(
                    {
                        "success": False,
                        "error": "Usage: atcoder.py metadata <contest_id>",
                    }
                )
            )
            sys.exit(1)

        contest_id: str = sys.argv[2]
        problems: list[dict[str, str]] = scrape_contest_problems(contest_id)

        if not problems:
            print(
                json.dumps(
                    {
                        "success": False,
                        "error": f"No problems found for contest {contest_id}",
                    }
                )
            )
            sys.exit(1)

        print(
            json.dumps(
                {
                    "success": True,
                    "contest_id": contest_id,
                    "problems": problems,
                }
            )
        )

    elif mode == "tests":
        if len(sys.argv) != 4:
            print(
                json.dumps(
                    {
                        "success": False,
                        "error": "Usage: atcoder.py tests <contest_id> <problem_letter>",
                    }
                )
            )
            sys.exit(1)

        test_contest_id: str = sys.argv[2]
        problem_letter: str = sys.argv[3]
        problem_id: str = f"{test_contest_id}_{problem_letter.lower()}"

        url: str = parse_problem_url(test_contest_id, problem_letter)
        print(f"Scraping: {url}", file=sys.stderr)

        tests: list[tuple[str, str]] = scrape(url)
        if not tests:
            print(
                json.dumps(
                    {
                        "success": False,
                        "error": f"No tests found for {test_contest_id} {problem_letter}",
                        "problem_id": problem_id,
                        "url": url,
                    }
                )
            )
            sys.exit(1)

        test_list: list[dict[str, str]] = [
            {"input": i, "expected": o} for i, o in tests
        ]

        print(
            json.dumps(
                {
                    "success": True,
                    "problem_id": problem_id,
                    "url": url,
                    "tests": test_list,
                }
            )
        )

    else:
        print(
            json.dumps(
                {
                    "success": False,
                    "error": f"Unknown mode: {mode}. Use 'metadata' or 'tests'",
                }
            )
        )
        sys.exit(1)


if __name__ == "__main__":
    main()
