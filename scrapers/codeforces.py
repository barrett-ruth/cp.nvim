#!/usr/bin/env python3

import json
import sys

import cloudscraper
from bs4 import BeautifulSoup, Tag


def scrape(url: str) -> list[tuple[str, str]]:
    try:
        scraper = cloudscraper.create_scraper()
        response = scraper.get(url, timeout=10)
        response.raise_for_status()

        soup = BeautifulSoup(response.text, "html.parser")
        input_sections = soup.find_all("div", class_="input")
        output_sections = soup.find_all("div", class_="output")

        individual_inputs: dict[str, list[str]] = {}
        individual_outputs: dict[str, list[str]] = {}

        for inp_section in input_sections:
            inp_pre = inp_section.find("pre")
            if not inp_pre or not isinstance(inp_pre, Tag):
                continue

            test_line_divs = inp_pre.find_all(
                "div", class_=lambda x: x and "test-example-line-" in x
            )
            if not test_line_divs:
                continue

            for div in test_line_divs:
                classes = div.get("class", [])
                class_name = next(
                    (
                        cls
                        for cls in classes
                        if "test-example-line-" in cls and cls.split("-")[-1].isdigit()
                    ),
                    None,
                )
                if not class_name:
                    continue

                test_num = class_name.replace("test-example-line-", "")
                if test_num not in individual_inputs:
                    individual_inputs[test_num] = []
                individual_inputs[test_num].append(div.get_text().strip())

        for out_section in output_sections:
            out_pre = out_section.find("pre")
            if not out_pre or not isinstance(out_pre, Tag):
                continue

            test_line_divs = out_pre.find_all(
                "div", class_=lambda x: x and "test-example-line-" in x
            )
            if not test_line_divs:
                continue

            for div in test_line_divs:
                classes = div.get("class", [])
                class_name = next(
                    (
                        cls
                        for cls in classes
                        if "test-example-line-" in cls and cls.split("-")[-1].isdigit()
                    ),
                    None,
                )
                if not class_name:
                    continue

                test_num = class_name.replace("test-example-line-", "")
                if test_num not in individual_outputs:
                    individual_outputs[test_num] = []
                individual_outputs[test_num].append(div.get_text().strip())

        if individual_inputs and individual_outputs:
            common_tests = set(individual_inputs.keys()) & set(
                individual_outputs.keys()
            )
            if common_tests:
                tests = []
                for test_num in sorted(common_tests):
                    input_text = "\n".join(individual_inputs[test_num])
                    output_text = "\n".join(individual_outputs[test_num])
                    prefixed_input = "1\n" + input_text
                    tests.append((prefixed_input, output_text))
                return tests
        all_inputs = []
        all_outputs = []

        for inp_section in input_sections:
            inp_pre = inp_section.find("pre")
            if not inp_pre or not isinstance(inp_pre, Tag):
                continue

            divs = inp_pre.find_all("div")
            if divs:
                lines = [div.get_text().strip() for div in divs if isinstance(div, Tag)]
                text = "\n".join(lines)
            else:
                text = inp_pre.get_text().replace("\r", "").strip()
            all_inputs.append(text)

        for out_section in output_sections:
            out_pre = out_section.find("pre")
            if not out_pre or not isinstance(out_pre, Tag):
                continue

            divs = out_pre.find_all("div")
            if divs:
                lines = [div.get_text().strip() for div in divs if isinstance(div, Tag)]
                text = "\n".join(lines)
            else:
                text = out_pre.get_text().replace("\r", "").strip()
            all_outputs.append(text)

        if not all_inputs or not all_outputs:
            return []

        combined_input = "\n".join(all_inputs)
        combined_output = "\n".join(all_outputs)
        return [(combined_input, combined_output)]

    except Exception as e:
        print(f"CloudScraper failed: {e}", file=sys.stderr)
        return []


def parse_problem_url(contest_id: str, problem_letter: str) -> str:
    return (
        f"https://codeforces.com/contest/{contest_id}/problem/{problem_letter.upper()}"
    )


def scrape_contest_problems(contest_id: str) -> list[dict[str, str]]:
    try:
        contest_url: str = f"https://codeforces.com/contest/{contest_id}"
        scraper = cloudscraper.create_scraper()
        response = scraper.get(contest_url, timeout=10)
        response.raise_for_status()

        soup = BeautifulSoup(response.text, "html.parser")
        problems: list[dict[str, str]] = []

        problem_links = soup.find_all(
            "a", href=lambda x: x and f"/contest/{contest_id}/problem/" in x
        )

        for link in problem_links:
            if not isinstance(link, Tag):
                continue
            href: str = str(link.get("href", ""))
            if f"/contest/{contest_id}/problem/" in href:
                problem_letter: str = href.split("/")[-1].lower()
                problem_name: str = link.get_text(strip=True)

                if problem_letter and problem_name:
                    problems.append({"id": problem_letter, "name": problem_name})

        problems.sort(key=lambda x: x["id"])

        seen: set[str] = set()
        unique_problems: list[dict[str, str]] = []
        for p in problems:
            if p["id"] not in seen:
                seen.add(p["id"])
                unique_problems.append(p)

        return unique_problems

    except Exception as e:
        print(f"Failed to scrape contest problems: {e}", file=sys.stderr)
        return []


def scrape_sample_tests(url: str) -> list[tuple[str, str]]:
    print(f"Scraping: {url}", file=sys.stderr)
    return scrape(url)


def main() -> None:
    if len(sys.argv) < 2:
        print(
            json.dumps(
                {
                    "success": False,
                    "error": "Usage: codeforces.py metadata <contest_id> OR codeforces.py tests <contest_id> <problem_letter>",
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
                        "error": "Usage: codeforces.py metadata <contest_id>",
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
                        "error": "Usage: codeforces.py tests <contest_id> <problem_letter>",
                    }
                )
            )
            sys.exit(1)

        tests_contest_id: str = sys.argv[2]
        problem_letter: str = sys.argv[3]
        problem_id: str = tests_contest_id + problem_letter.lower()

        url: str = parse_problem_url(tests_contest_id, problem_letter)
        tests: list[tuple[str, str]] = scrape_sample_tests(url)

        if not tests:
            print(
                json.dumps(
                    {
                        "success": False,
                        "error": f"No tests found for {tests_contest_id} {problem_letter}",
                        "problem_id": problem_id,
                        "url": url,
                    }
                )
            )
            sys.exit(1)

        test_list: list[dict[str, str]] = []
        for input_data, output_data in tests:
            test_list.append({"input": input_data, "expected": output_data})

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
