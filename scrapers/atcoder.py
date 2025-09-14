#!/usr/bin/env python3

import json
import sys

import requests
from bs4 import BeautifulSoup


def parse_problem_url(contest_id: str, problem_letter: str) -> str:
    task_id = f"{contest_id}_{problem_letter}"
    return f"https://atcoder.jp/contests/{contest_id}/tasks/{task_id}"


def scrape_contest_problems(contest_id: str):
    try:
        contest_url = f"https://atcoder.jp/contests/{contest_id}/tasks"
        headers = {
            "User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
        }

        response = requests.get(contest_url, headers=headers, timeout=10)
        response.raise_for_status()

        soup = BeautifulSoup(response.text, "html.parser")
        problems = []

        task_table = soup.find("table", class_="table")
        if not task_table:
            return []

        rows = task_table.find_all("tr")[1:]  # Skip header row

        for row in rows:
            cells = row.find_all("td")
            if len(cells) >= 2:
                task_link = cells[1].find("a")
                if task_link:
                    task_name = task_link.get_text(strip=True)
                    task_href = task_link.get("href", "")

                    # Extract problem letter from task name or URL
                    task_id = task_href.split("/")[-1] if task_href else ""
                    if task_id.startswith(contest_id + "_"):
                        problem_letter = task_id[len(contest_id) + 1 :]

                        if problem_letter and task_name:
                            problems.append(
                                {"id": problem_letter.lower(), "name": task_name}
                            )

        problems.sort(key=lambda x: x["id"])
        return problems

    except Exception as e:
        print(f"Failed to scrape AtCoder contest problems: {e}", file=sys.stderr)
        return []


def scrape(url: str) -> list[tuple[str, str]]:
    try:
        headers = {
            "User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
        }

        response = requests.get(url, headers=headers, timeout=10)
        response.raise_for_status()

        soup = BeautifulSoup(response.text, "html.parser")

        tests = []

        sample_headers = soup.find_all(
            "h3", string=lambda x: x and "sample" in x.lower() if x else False
        )

        i = 0
        while i < len(sample_headers):
            header = sample_headers[i]
            if "input" in header.get_text().lower():
                input_pre = header.find_next("pre")
                if input_pre and i + 1 < len(sample_headers):
                    next_header = sample_headers[i + 1]
                    if "output" in next_header.get_text().lower():
                        output_pre = next_header.find_next("pre")
                        if output_pre:
                            input_text = input_pre.get_text().strip().replace("\r", "")
                            output_text = (
                                output_pre.get_text().strip().replace("\r", "")
                            )
                            if input_text and output_text:
                                tests.append((input_text, output_text))
                        i += 2
                        continue
            i += 1

        return tests

    except Exception as e:
        print(f"Error scraping AtCoder: {e}", file=sys.stderr)
        return []


def main():
    if len(sys.argv) < 2:
        result = {
            "success": False,
            "error": "Usage: atcoder.py metadata <contest_id> OR atcoder.py tests <contest_id> <problem_letter>",
        }
        print(json.dumps(result))
        sys.exit(1)

    mode = sys.argv[1]

    if mode == "metadata":
        if len(sys.argv) != 3:
            result = {
                "success": False,
                "error": "Usage: atcoder.py metadata <contest_id>",
            }
            print(json.dumps(result))
            sys.exit(1)

        contest_id = sys.argv[2]
        problems = scrape_contest_problems(contest_id)

        if not problems:
            result = {
                "success": False,
                "error": f"No problems found for contest {contest_id}",
            }
            print(json.dumps(result))
            sys.exit(1)

        result = {
            "success": True,
            "contest_id": contest_id,
            "problems": problems,
        }
        print(json.dumps(result))

    elif mode == "tests":
        if len(sys.argv) != 4:
            result = {
                "success": False,
                "error": "Usage: atcoder.py tests <contest_id> <problem_letter>",
            }
            print(json.dumps(result))
            sys.exit(1)

        contest_id = sys.argv[2]
        problem_letter = sys.argv[3]
        problem_id = contest_id + problem_letter.lower()

        url = parse_problem_url(contest_id, problem_letter)
        print(f"Scraping: {url}", file=sys.stderr)

        tests = scrape(url)

        if not tests:
            result = {
                "success": False,
                "error": f"No tests found for {contest_id} {problem_letter}",
                "problem_id": problem_id,
                "url": url,
            }
            print(json.dumps(result))
            sys.exit(1)

        test_cases = []
        for input_data, output_data in tests:
            test_cases.append({"input": input_data, "output": output_data})

        if test_cases:
            combined_input = (
                str(len(test_cases))
                + "\n"
                + "\n".join(tc["input"] for tc in test_cases)
            )
            combined_output = "\n".join(tc["output"] for tc in test_cases)
            test_cases = [{"input": combined_input, "output": combined_output}]

        result = {
            "success": True,
            "problem_id": problem_id,
            "url": url,
            "test_cases": test_cases,
        }
        print(json.dumps(result))

    else:
        result = {
            "success": False,
            "error": f"Unknown mode: {mode}. Use 'metadata' or 'tests'",
        }
        print(json.dumps(result))
        sys.exit(1)


if __name__ == "__main__":
    main()
