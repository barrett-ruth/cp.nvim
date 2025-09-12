#!/usr/bin/env python3

import sys

import requests
from bs4 import BeautifulSoup


def parse_problem_url(problem_input: str) -> str | None:
    if problem_input.startswith("https://cses.fi/problemset/task/"):
        return problem_input
    elif problem_input.isdigit():
        return f"https://cses.fi/problemset/task/{problem_input}"
    return None


def scrape(url: str) -> list[tuple[str, str]]:
    try:
        headers = {
            "User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
        }

        response = requests.get(url, headers=headers, timeout=10)
        response.raise_for_status()

        soup = BeautifulSoup(response.text, "html.parser")

        tests = []
        example_header = soup.find("h1", string="Example")

        if example_header:
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

            if input_text and output_text:
                tests.append((input_text, output_text))

        return tests

    except Exception as e:
        print(f"Error scraping CSES: {e}", file=sys.stderr)
        return []


def main():
    if len(sys.argv) != 2:
        print("Usage: cses.py <problem_id_or_url>", file=sys.stderr)
        sys.exit(1)

    problem_input = sys.argv[1]
    url = parse_problem_url(problem_input)

    if not url:
        print(f"Invalid problem input: {problem_input}", file=sys.stderr)
        print("Use either problem ID (e.g., 1068) or full URL", file=sys.stderr)
        sys.exit(1)

    tests = scrape(url)

    if not tests:
        print(f"No tests found for {problem_input}", file=sys.stderr)
        sys.exit(1)

    print("---INPUT---")
    print(len(tests))
    for input_data, output_data in tests:
        print(input_data)
    print("---OUTPUT---")
    for input_data, output_data in tests:
        print(output_data)
    print("---END---")


if __name__ == "__main__":
    main()
