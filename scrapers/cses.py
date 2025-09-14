#!/usr/bin/env python3

import json
import sys

import requests
from bs4 import BeautifulSoup


def parse_problem_url(problem_input: str) -> str | None:
    if problem_input.startswith("https://cses.fi/problemset/task/"):
        return problem_input
    elif problem_input.isdigit():
        return f"https://cses.fi/problemset/task/{problem_input}"
    return None


def scrape_all_problems() -> dict[str, list[dict[str, str]]]:
    try:
        problemset_url: str = "https://cses.fi/problemset/"
        headers: dict[str, str] = {
            "User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
        }

        response = requests.get(problemset_url, headers=headers, timeout=10)
        response.raise_for_status()

        soup = BeautifulSoup(response.text, "html.parser")
        all_categories: dict[str, list[dict[str, str]]] = {}

        problem_links = soup.find_all(
            "a", href=lambda x: x and "/problemset/task/" in x
        )
        print(f"Found {len(problem_links)} problem links", file=sys.stderr)

        current_category: str | None = None
        for element in soup.find_all(["h1", "a"]):
            if element.name == "h1":
                current_category = element.get_text().strip()
                if current_category not in all_categories:
                    all_categories[current_category] = []
            elif element.name == "a" and "/problemset/task/" in element.get("href", ""):
                href: str = element.get("href", "")
                problem_id: str = href.split("/")[-1]
                problem_name: str = element.get_text(strip=True)

                if problem_id.isdigit() and problem_name and current_category:
                    all_categories[current_category].append(
                        {"id": problem_id, "name": problem_name}
                    )

        for category in all_categories:
            all_categories[category].sort(key=lambda x: int(x["id"]))

        print(f"Found {len(all_categories)} categories", file=sys.stderr)
        return all_categories

    except Exception as e:
        print(f"Failed to scrape CSES problems: {e}", file=sys.stderr)
        return {}


def scrape(url: str) -> list[tuple[str, str]]:
    try:
        headers: dict[str, str] = {
            "User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
        }

        response = requests.get(url, headers=headers, timeout=10)
        response.raise_for_status()

        soup = BeautifulSoup(response.text, "html.parser")

        tests: list[tuple[str, str]] = []
        example_header = soup.find("h1", string="Example")

        if example_header:
            current = example_header.find_next_sibling()
            input_text: str | None = None
            output_text: str | None = None

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


def main() -> None:
    if len(sys.argv) < 2:
        result: dict[str, str | bool] = {
            "success": False,
            "error": "Usage: cses.py metadata OR cses.py tests <problem_id_or_url>",
        }
        print(json.dumps(result))
        sys.exit(1)

    mode: str = sys.argv[1]

    if mode == "metadata":
        if len(sys.argv) != 2:
            result = {
                "success": False,
                "error": "Usage: cses.py metadata",
            }
            print(json.dumps(result))
            sys.exit(1)

        all_categories: dict[str, list[dict[str, str]]] = scrape_all_problems()

        if not all_categories:
            result = {
                "success": False,
                "error": "Failed to scrape CSES problem categories",
            }
            print(json.dumps(result))
            sys.exit(1)

        result = {
            "success": True,
            "categories": all_categories,
        }
        print(json.dumps(result))

    elif mode == "tests":
        if len(sys.argv) != 3:
            result = {
                "success": False,
                "error": "Usage: cses.py tests <problem_id_or_url>",
            }
            print(json.dumps(result))
            sys.exit(1)

        problem_input: str = sys.argv[2]
        url: str | None = parse_problem_url(problem_input)

        if not url:
            result = {
                "success": False,
                "error": f"Invalid problem input: {problem_input}. Use either problem ID (e.g., 1068) or full URL",
                "problem_id": problem_input if problem_input.isdigit() else None,
            }
            print(json.dumps(result))
            sys.exit(1)

        tests: list[tuple[str, str]] = scrape(url)

        problem_id: str = (
            problem_input if problem_input.isdigit() else problem_input.split("/")[-1]
        )

        if not tests:
            result = {
                "success": False,
                "error": f"No tests found for {problem_input}",
                "problem_id": problem_id,
                "url": url,
            }
            print(json.dumps(result))
            sys.exit(1)

        test_cases: list[dict[str, str]] = []
        for input_data, output_data in tests:
            test_cases.append({"input": input_data, "output": output_data})

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
