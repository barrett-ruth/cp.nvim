#!/usr/bin/env python3

import json
import sys

import cloudscraper
from bs4 import BeautifulSoup


def scrape(url: str):
    try:
        scraper = cloudscraper.create_scraper()
        response = scraper.get(url, timeout=10)
        response.raise_for_status()

        soup = BeautifulSoup(response.text, "html.parser")
        tests = []

        input_sections = soup.find_all("div", class_="input")
        output_sections = soup.find_all("div", class_="output")

        for inp_section, out_section in zip(input_sections, output_sections):
            inp_pre = inp_section.find("pre")
            out_pre = out_section.find("pre")

            if inp_pre and out_pre:
                input_lines = []
                output_lines = []

                for line_div in inp_pre.find_all("div", class_="test-example-line"):
                    input_lines.append(line_div.get_text().strip())

                output_divs = out_pre.find_all("div", class_="test-example-line")
                if not output_divs:
                    output_text_raw = out_pre.get_text().strip().replace("\r", "")
                    output_lines = [
                        line.strip()
                        for line in output_text_raw.split("\n")
                        if line.strip()
                    ]
                else:
                    for line_div in output_divs:
                        output_lines.append(line_div.get_text().strip())

                if input_lines and output_lines:
                    input_text = "\n".join(input_lines)
                    output_text = "\n".join(output_lines)
                    tests.append((input_text, output_text))

        return tests

    except Exception as e:
        print(f"CloudScraper failed: {e}", file=sys.stderr)
        return []


def parse_problem_url(contest_id: str, problem_letter: str) -> str:
    return (
        f"https://codeforces.com/contest/{contest_id}/problem/{problem_letter.upper()}"
    )


def scrape_contest_problems(contest_id: str):
    try:
        contest_url = f"https://codeforces.com/contest/{contest_id}"
        scraper = cloudscraper.create_scraper()
        response = scraper.get(contest_url, timeout=10)
        response.raise_for_status()

        soup = BeautifulSoup(response.text, "html.parser")
        problems = []

        problem_links = soup.find_all("a", href=lambda x: x and f"/contest/{contest_id}/problem/" in x)

        for link in problem_links:
            href = link.get("href", "")
            if f"/contest/{contest_id}/problem/" in href:
                problem_letter = href.split("/")[-1].lower()
                problem_name = link.get_text(strip=True)

                if problem_letter and problem_name and len(problem_letter) == 1:
                    problems.append({
                        "id": problem_letter,
                        "name": problem_name
                    })

        problems.sort(key=lambda x: x["id"])

        seen = set()
        unique_problems = []
        for p in problems:
            if p["id"] not in seen:
                seen.add(p["id"])
                unique_problems.append(p)

        return unique_problems

    except Exception as e:
        print(f"Failed to scrape contest problems: {e}", file=sys.stderr)
        return []


def scrape_sample_tests(url: str):
    print(f"Scraping: {url}", file=sys.stderr)
    return scrape(url)


def main():
    if len(sys.argv) < 2:
        result = {
            "success": False,
            "error": "Usage: codeforces.py metadata <contest_id> OR codeforces.py tests <contest_id> <problem_letter>",
        }
        print(json.dumps(result))
        sys.exit(1)

    mode = sys.argv[1]

    if mode == "metadata":
        if len(sys.argv) != 3:
            result = {
                "success": False,
                "error": "Usage: codeforces.py metadata <contest_id>",
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
                "error": "Usage: codeforces.py tests <contest_id> <problem_letter>",
            }
            print(json.dumps(result))
            sys.exit(1)

        contest_id = sys.argv[2]
        problem_letter = sys.argv[3]
        problem_id = contest_id + problem_letter.lower()

        url = parse_problem_url(contest_id, problem_letter)
        tests = scrape_sample_tests(url)

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

    else:
        result = {
            "success": False,
            "error": f"Unknown mode: {mode}. Use 'metadata' or 'tests'",
        }
        print(json.dumps(result))
        sys.exit(1)


if __name__ == "__main__":
    main()
