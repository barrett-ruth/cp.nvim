#!/usr/bin/env python3

import json
import re
import sys
from dataclasses import asdict

import backoff
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


def scrape_contests() -> list[ContestSummary]:
    import concurrent.futures

    def get_max_pages() -> int:
        try:
            headers = {
                "User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
            }
            response = requests.get(
                "https://atcoder.jp/contests/archive", headers=headers, timeout=10
            )
            response.raise_for_status()

            soup = BeautifulSoup(response.text, "html.parser")
            pagination = soup.find("ul", class_="pagination")
            if not pagination or not isinstance(pagination, Tag):
                return 15

            lis = pagination.find_all("li")
            if lis and isinstance(lis[-1], Tag):
                last_li_text = lis[-1].get_text().strip()
                try:
                    return int(last_li_text)
                except ValueError:
                    return 15
            return 15
        except Exception:
            return 15

    def scrape_page(page: int) -> list[ContestSummary]:
        @backoff.on_exception(
            backoff.expo,
            (requests.exceptions.RequestException, requests.exceptions.HTTPError),
            max_tries=4,
            jitter=backoff.random_jitter,
            on_backoff=lambda details: print(
                f"Request failed on page {page} (attempt {details['tries']}), retrying in {details['wait']:.1f}s: {details['exception']}",
                file=sys.stderr,
            ),
        )
        @backoff.on_predicate(
            backoff.expo,
            lambda response: response.status_code == 429,
            max_tries=4,
            jitter=backoff.random_jitter,
            on_backoff=lambda details: print(
                f"Rate limited on page {page}, retrying in {details['wait']:.1f}s",
                file=sys.stderr,
            ),
        )
        def make_request() -> requests.Response:
            headers = {
                "User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
            }
            url = f"https://atcoder.jp/contests/archive?page={page}"
            response = requests.get(url, headers=headers, timeout=10)
            response.raise_for_status()
            return response

        try:
            response = make_request()
        except Exception:
            return []

        soup = BeautifulSoup(response.text, "html.parser")
        table = soup.find("table", class_="table")
        if not table:
            return []

        tbody = table.find("tbody")
        if not tbody or not isinstance(tbody, Tag):
            return []

        rows = tbody.find_all("tr")
        if not rows:
            return []

        contests = []
        for row in rows:
            cells = row.find_all("td")
            if len(cells) < 2:
                continue

            contest_cell = cells[1]
            link = contest_cell.find("a")
            if not link or not link.get("href"):
                continue

            href = link.get("href")
            contest_id = href.split("/")[-1]
            name = link.get_text().strip()

            try:
                name = name.encode().decode("unicode_escape")
            except (UnicodeDecodeError, UnicodeEncodeError):
                pass

            name = (
                name.replace("\uff08", "(")
                .replace("\uff09", ")")
                .replace("\u3000", " ")
            )
            name = re.sub(
                r"[\uff01-\uff5e]", lambda m: chr(ord(m.group()) - 0xFEE0), name
            )

            def generate_display_name_from_id(contest_id: str) -> str:
                parts = contest_id.replace("-", " ").replace("_", " ")

                parts = re.sub(
                    r"\b(jsc|JSC)\b",
                    "Japanese Student Championship",
                    parts,
                    flags=re.IGNORECASE,
                )
                parts = re.sub(
                    r"\b(wtf|WTF)\b",
                    "World Tour Finals",
                    parts,
                    flags=re.IGNORECASE,
                )
                parts = re.sub(
                    r"\b(ahc)(\d+)\b",
                    r"Heuristic Contest \2 (AHC)",
                    parts,
                    flags=re.IGNORECASE,
                )
                parts = re.sub(
                    r"\b(arc)(\d+)\b",
                    r"Regular Contest \2 (ARC)",
                    parts,
                    flags=re.IGNORECASE,
                )
                parts = re.sub(
                    r"\b(abc)(\d+)\b",
                    r"Beginner Contest \2 (ABC)",
                    parts,
                    flags=re.IGNORECASE,
                )
                parts = re.sub(
                    r"\b(agc)(\d+)\b",
                    r"Grand Contest \2 (AGC)",
                    parts,
                    flags=re.IGNORECASE,
                )

                return parts.title()

            english_chars = sum(1 for c in name if c.isascii() and c.isalpha())
            total_chars = len(re.sub(r"\s+", "", name))

            if total_chars > 0 and english_chars / total_chars < 0.3:
                display_name = generate_display_name_from_id(contest_id)
            else:
                display_name = name
                if "AtCoder Beginner Contest" in name:
                    match = re.search(r"AtCoder Beginner Contest (\d+)", name)
                    if match:
                        display_name = f"Beginner Contest {match.group(1)} (ABC)"
                elif "AtCoder Regular Contest" in name:
                    match = re.search(r"AtCoder Regular Contest (\d+)", name)
                    if match:
                        display_name = f"Regular Contest {match.group(1)} (ARC)"
                elif "AtCoder Grand Contest" in name:
                    match = re.search(r"AtCoder Grand Contest (\d+)", name)
                    if match:
                        display_name = f"Grand Contest {match.group(1)} (AGC)"
                elif "AtCoder Heuristic Contest" in name:
                    match = re.search(r"AtCoder Heuristic Contest (\d+)", name)
                    if match:
                        display_name = f"Heuristic Contest {match.group(1)} (AHC)"

            contests.append(
                ContestSummary(id=contest_id, name=name, display_name=display_name)
            )

        return contests

    max_pages = get_max_pages()
    page_results = {}

    with concurrent.futures.ThreadPoolExecutor(max_workers=5) as executor:
        future_to_page = {
            executor.submit(scrape_page, page): page for page in range(1, max_pages + 1)
        }

        for future in concurrent.futures.as_completed(future_to_page):
            page = future_to_page[future]
            page_contests = future.result()
            page_results[page] = page_contests

    all_contests = []
    for page in sorted(page_results.keys()):
        all_contests.extend(page_results[page])

    return all_contests


def main() -> None:
    if len(sys.argv) < 2:
        result = MetadataResult(
            success=False,
            error="Usage: atcoder.py metadata <contest_id> OR atcoder.py tests <contest_id> <problem_letter> OR atcoder.py contests",
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

    elif mode == "contests":
        if len(sys.argv) != 2:
            contest_result = ContestListResult(
                success=False, error="Usage: atcoder.py contests"
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
