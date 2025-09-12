#!/usr/bin/env python3

import json
import sys

import requests
from bs4 import BeautifulSoup


def parse_problem_url(contest_id: str, problem_letter: str) -> str:
    task_id = f"{contest_id}_{problem_letter}"
    return f"https://atcoder.jp/contests/{contest_id}/tasks/{task_id}"


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
    if len(sys.argv) != 3:
        result = {
            "success": False,
            "error": "Usage: atcoder.py <contest_id> <problem_letter>",
            "problem_id": None,
        }
        print(json.dumps(result))
        sys.exit(1)

    contest_id = sys.argv[1]
    problem_letter = sys.argv[2]
    problem_id = contest_id + problem_letter

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

    result = {
        "success": True,
        "problem_id": problem_id,
        "url": url,
        "test_cases": test_cases,
    }

    print(json.dumps(result))


if __name__ == "__main__":
    main()
