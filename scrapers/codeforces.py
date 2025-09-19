#!/usr/bin/env python3

import json
import sys
from dataclasses import asdict

import cloudscraper
from bs4 import BeautifulSoup, Tag

from .models import MetadataResult, Problem, TestCase, TestsResult


def scrape(url: str) -> list[TestCase]:
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
                    tests.append(TestCase(input=prefixed_input, expected=output_text))
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
        return [TestCase(input=combined_input, expected=combined_output)]

    except Exception as e:
        print(f"CloudScraper failed: {e}", file=sys.stderr)
        return []


def parse_problem_url(contest_id: str, problem_letter: str) -> str:
    return (
        f"https://codeforces.com/contest/{contest_id}/problem/{problem_letter.upper()}"
    )


def scrape_contest_problems(contest_id: str) -> list[Problem]:
    try:
        contest_url: str = f"https://codeforces.com/contest/{contest_id}"
        scraper = cloudscraper.create_scraper()
        response = scraper.get(contest_url, timeout=10)
        response.raise_for_status()

        soup = BeautifulSoup(response.text, "html.parser")
        problems: list[Problem] = []

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
                    problems.append(Problem(id=problem_letter, name=problem_name))

        problems.sort(key=lambda x: x.id)

        seen: set[str] = set()
        unique_problems: list[Problem] = []
        for p in problems:
            if p.id not in seen:
                seen.add(p.id)
                unique_problems.append(p)

        return unique_problems

    except Exception as e:
        print(f"Failed to scrape contest problems: {e}", file=sys.stderr)
        return []


def scrape_sample_tests(url: str) -> list[TestCase]:
    print(f"Scraping: {url}", file=sys.stderr)
    return scrape(url)


def main() -> None:
    if len(sys.argv) < 2:
        result = MetadataResult(
            success=False,
            error="Usage: codeforces.py metadata <contest_id> OR codeforces.py tests <contest_id> <problem_letter>",
        )
        print(json.dumps(asdict(result)))
        sys.exit(1)

    mode: str = sys.argv[1]

    if mode == "metadata":
        if len(sys.argv) != 3:
            result = MetadataResult(
                success=False, error="Usage: codeforces.py metadata <contest_id>"
            )
            print(json.dumps(asdict(result)))
            sys.exit(1)

        contest_id: str = sys.argv[2]
        problems: list[Problem] = scrape_contest_problems(contest_id)

        if not problems:
            result = MetadataResult(
                success=False, error=f"No problems found for contest {contest_id}"
            )
            print(json.dumps(asdict(result)))
            sys.exit(1)

        result = MetadataResult(success=True, contest_id=contest_id, problems=problems)
        print(json.dumps(asdict(result)))

    elif mode == "tests":
        if len(sys.argv) != 4:
            tests_result = TestsResult(
                success=False,
                error="Usage: codeforces.py tests <contest_id> <problem_letter>",
            )
            print(json.dumps(asdict(tests_result)))
            sys.exit(1)

        tests_contest_id: str = sys.argv[2]
        problem_letter: str = sys.argv[3]
        problem_id: str = tests_contest_id + problem_letter.lower()

        url: str = parse_problem_url(tests_contest_id, problem_letter)
        tests: list[TestCase] = scrape_sample_tests(url)

        if not tests:
            tests_result = TestsResult(
                success=False,
                error=f"No tests found for {tests_contest_id} {problem_letter}",
                problem_id=problem_id,
                url=url,
            )
            print(json.dumps(asdict(tests_result)))
            sys.exit(1)

        tests_result = TestsResult(
            success=True, problem_id=problem_id, url=url, tests=tests
        )
        print(json.dumps(asdict(tests_result)))

    else:
        result = MetadataResult(
            success=False, error=f"Unknown mode: {mode}. Use 'metadata' or 'tests'"
        )
        print(json.dumps(asdict(result)))
        sys.exit(1)


if __name__ == "__main__":
    main()
