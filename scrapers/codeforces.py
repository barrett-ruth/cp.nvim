#!/usr/bin/env python3

import json
import re
import sys
from dataclasses import asdict

from bs4 import BeautifulSoup, Tag

from .base import BaseScraper, HttpClient
from .clients import CloudScraperClient
from .models import (
    ContestListResult,
    ContestSummary,
    MetadataResult,
    ProblemSummary,
    TestCase,
    TestsResult,
)


class CodeforcesScraper(BaseScraper):
    @property
    def platform_name(self) -> str:
        return "codeforces"

    def _create_client(self) -> HttpClient:
        return CloudScraperClient(self.config)

    def scrape_contest_metadata(self, contest_id: str) -> MetadataResult:
        return self._safe_execute(
            "metadata", self._scrape_contest_metadata_impl, contest_id
        )

    def scrape_problem_tests(self, contest_id: str, problem_id: str) -> TestsResult:
        return self._safe_execute(
            "tests", self._scrape_problem_tests_impl, contest_id, problem_id
        )

    def scrape_contest_list(self) -> ContestListResult:
        return self._safe_execute("contests", self._scrape_contest_list_impl)

    def _scrape_contest_metadata_impl(self, contest_id: str) -> MetadataResult:
        problems = scrape_contest_problems(contest_id, self.client)
        if not problems:
            return self._create_metadata_error(
                f"No problems found for contest {contest_id}", contest_id
            )
        return MetadataResult(
            success=True, error="", contest_id=contest_id, problems=problems
        )

    def _scrape_problem_tests_impl(
        self, contest_id: str, problem_letter: str
    ) -> TestsResult:
        problem_id = contest_id + problem_letter.lower()
        url = parse_problem_url(contest_id, problem_letter)
        tests = scrape_sample_tests(url, self.client)

        response = self.client.get(url)
        soup = BeautifulSoup(response.text, "html.parser")
        timeout_ms, memory_mb = extract_problem_limits(soup)

        if not tests:
            return self._create_tests_error(
                f"No tests found for {contest_id} {problem_letter}", problem_id, url
            )

        return TestsResult(
            success=True,
            error="",
            problem_id=problem_id,
            url=url,
            tests=tests,
            timeout_ms=timeout_ms,
            memory_mb=memory_mb,
        )

    def _scrape_contest_list_impl(self) -> ContestListResult:
        contests = scrape_contests(self.client)
        if not contests:
            return self._create_contests_error("No contests found")
        return ContestListResult(success=True, error="", contests=contests)


def scrape(url: str, client: HttpClient) -> list[TestCase]:
    try:
        response = client.get(url)

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


def scrape_contest_problems(
    contest_id: str, client: HttpClient
) -> list[ProblemSummary]:
    try:
        contest_url: str = f"https://codeforces.com/contest/{contest_id}"
        response = client.get(contest_url)

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


def scrape_sample_tests(url: str, client: HttpClient) -> list[TestCase]:
    print(f"Scraping: {url}", file=sys.stderr)
    return scrape(url, client)


def scrape_contests(client: HttpClient) -> list[ContestSummary]:
    response = client.get("https://codeforces.com/api/contest.list")

    data = response.json()
    if data["status"] != "OK":
        return []

    contests = []
    for contest in data["result"]:
        contest_id = str(contest["id"])
        name = contest["name"]

        contests.append(ContestSummary(id=contest_id, name=name, display_name=name))

    return contests


def main() -> None:
    if len(sys.argv) < 2:
        result = MetadataResult(
            success=False,
            error="Usage: codeforces.py metadata <contest_id> OR codeforces.py tests <contest_id> <problem_letter> OR codeforces.py contests",
        )
        print(json.dumps(asdict(result)))
        sys.exit(1)

    scraper = CodeforcesScraper()
    mode: str = sys.argv[1]

    if mode == "metadata":
        if len(sys.argv) != 3:
            result = MetadataResult(
                success=False, error="Usage: codeforces.py metadata <contest_id>"
            )
            print(json.dumps(asdict(result)))
            sys.exit(1)

        contest_id: str = sys.argv[2]
        result = scraper.scrape_contest_metadata(contest_id)
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
        tests_result = scraper.scrape_problem_tests(tests_contest_id, problem_letter)
        print(json.dumps(asdict(tests_result)))

    elif mode == "contests":
        if len(sys.argv) != 2:
            contest_result = ContestListResult(
                success=False, error="Usage: codeforces.py contests"
            )
            print(json.dumps(asdict(contest_result)))
            sys.exit(1)

        contest_result = scraper.scrape_contest_list()
        print(json.dumps(asdict(contest_result)))

    else:
        result = MetadataResult(
            success=False,
            error=f"Unknown mode: {mode}. Use 'metadata', 'tests', or 'contests'",
        )
        print(json.dumps(asdict(result)))
        sys.exit(1)

    scraper.close()


if __name__ == "__main__":
    main()
