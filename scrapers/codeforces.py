#!/usr/bin/env python3

import json
import re
import sys
from dataclasses import asdict

import cloudscraper
from bs4 import BeautifulSoup, Tag

from .models import (
    ContestListResult,
    ContestSummary,
    MetadataResult,
    ProblemSummary,
    TestCase,
    TestsResult,
)


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


def extract_problem_limits(soup: BeautifulSoup) -> tuple[int, float]:
    timeout_ms = None
    memory_mb = None

    time_limit_div = soup.find("div", class_="time-limit")
    if time_limit_div:
        text = time_limit_div.get_text().strip()
        match = re.search(r"(\d+) seconds?", text)
        if match:
            seconds = int(match.group(1))
            timeout_ms = seconds * 1000

    if timeout_ms is None:
        raise ValueError("Could not find valid timeout in time-limit section")

    memory_limit_div = soup.find("div", class_="memory-limit")
    if memory_limit_div:
        text = memory_limit_div.get_text().strip()
        match = re.search(r"(\d+) megabytes", text)
        if match:
            memory_mb = float(match.group(1))

    if memory_mb is None:
        raise ValueError("Could not find valid memory limit in memory-limit section")

    return timeout_ms, memory_mb


def scrape_contest_problems(contest_id: str) -> list[ProblemSummary]:
    try:
        contest_url: str = f"https://codeforces.com/contest/{contest_id}"
        scraper = cloudscraper.create_scraper()
        response = scraper.get(contest_url, timeout=10)
        response.raise_for_status()

        soup = BeautifulSoup(response.text, "html.parser")
        problems: list[ProblemSummary] = []

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
                    problems.append(
                        ProblemSummary(id=problem_letter, name=problem_name)
                    )

        problems.sort(key=lambda x: x.id)

        seen: set[str] = set()
        unique_problems: list[ProblemSummary] = []
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


def scrape_contests() -> list[ContestSummary]:
    try:
        scraper = cloudscraper.create_scraper()
        response = scraper.get("https://codeforces.com/api/contest.list", timeout=10)
        response.raise_for_status()

        data = response.json()
        if data["status"] != "OK":
            return []

        contests = []
        for contest in data["result"]:
            contest_id = str(contest["id"])
            name = contest["name"]

            display_name = name
            if "Educational Codeforces Round" in name:
                match = re.search(r"Educational Codeforces Round (\d+)", name)
                if match:
                    display_name = f"Educational Round {match.group(1)}"
            elif "Codeforces Global Round" in name:
                match = re.search(r"Codeforces Global Round (\d+)", name)
                if match:
                    display_name = f"Global Round {match.group(1)}"
            elif "Codeforces Round" in name:
                div_match = re.search(r"Codeforces Round (\d+) \(Div\. (\d+)\)", name)
                if div_match:
                    display_name = (
                        f"Round {div_match.group(1)} (Div. {div_match.group(2)})"
                    )
                else:
                    combined_match = re.search(
                        r"Codeforces Round (\d+) \(Div\. 1 \+ Div\. 2\)", name
                    )
                    if combined_match:
                        display_name = (
                            f"Round {combined_match.group(1)} (Div. 1 + Div. 2)"
                        )
                    else:
                        single_div_match = re.search(
                            r"Codeforces Round (\d+) \(Div\. 1\)", name
                        )
                        if single_div_match:
                            display_name = f"Round {single_div_match.group(1)} (Div. 1)"
                        else:
                            round_match = re.search(r"Codeforces Round (\d+)", name)
                            if round_match:
                                display_name = f"Round {round_match.group(1)}"

            contests.append(
                ContestSummary(id=contest_id, name=name, display_name=display_name)
            )

        return contests[:100]

    except Exception as e:
        print(f"Failed to fetch contests: {e}", file=sys.stderr)
        return []


def main() -> None:
    if len(sys.argv) < 2:
        result = MetadataResult(
            success=False,
            error="Usage: codeforces.py metadata <contest_id> OR codeforces.py tests <contest_id> <problem_letter> OR codeforces.py contests",
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
        problems: list[ProblemSummary] = scrape_contest_problems(contest_id)

        if not problems:
            result = MetadataResult(
                success=False, error=f"No problems found for contest {contest_id}"
            )
            print(json.dumps(asdict(result)))
            sys.exit(1)

        result = MetadataResult(
            success=True, error="", contest_id=contest_id, problems=problems
        )
        print(json.dumps(asdict(result)))

    elif mode == "tests":
        if len(sys.argv) != 4:
            tests_result = TestsResult(
                success=False,
                error="Usage: codeforces.py tests <contest_id> <problem_letter>",
                problem_id="",
                url="",
                tests=[],
                timeout_ms=0,
                memory_mb=0,
            )
            print(json.dumps(asdict(tests_result)))
            sys.exit(1)

        tests_contest_id: str = sys.argv[2]
        problem_letter: str = sys.argv[3]
        problem_id: str = tests_contest_id + problem_letter.lower()

        url: str = parse_problem_url(tests_contest_id, problem_letter)
        tests: list[TestCase] = scrape_sample_tests(url)

        try:
            scraper = cloudscraper.create_scraper()
            response = scraper.get(url, timeout=10)
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
                error=f"No tests found for {tests_contest_id} {problem_letter}",
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

    elif mode == "contests":
        if len(sys.argv) != 2:
            contest_result = ContestListResult(
                success=False, error="Usage: codeforces.py contests"
            )
            print(json.dumps(asdict(contest_result)))
            sys.exit(1)

        contests = scrape_contests()
        if not contests:
            contest_result = ContestListResult(success=False, error="No contests found")
            print(json.dumps(asdict(contest_result)))
            sys.exit(1)

        contest_result = ContestListResult(success=True, error="", contests=contests)
        print(json.dumps(asdict(contest_result)))

    else:
        result = MetadataResult(
            success=False,
            error=f"Unknown mode: {mode}. Use 'metadata', 'tests', or 'contests'",
        )
        print(json.dumps(asdict(result)))
        sys.exit(1)


if __name__ == "__main__":
    main()
