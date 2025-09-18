#!/usr/bin/env python3

import json
import sys

import cloudscraper
from bs4 import BeautifulSoup


def extract_combined_text(sections) -> list[str]:
    texts = []

    for section in sections:
        pre = section.find("pre")
        if not pre:
            continue

        divs = pre.find_all("div")
        if divs:
            lines = [div.get_text().strip() for div in divs]
            text = "\n".join(lines)
        else:
            text = pre.get_text().replace("\r", "").strip()
        texts.append(text)

    return texts


def extract_lines_by_test_number(sections) -> dict[int, list[str]]:
    lines_by_test = {}

    for section in sections:
        pre = section.find("pre")
        if not pre:
            continue

        divs = pre.find_all("div")
        for div in divs:
            classes = div.get("class", [])
            for class_name in classes:
                if not class_name.startswith("test-example-line-"):
                    continue

                try:
                    test_num = int(class_name.split("-")[-1])
                    if test_num not in lines_by_test:
                        lines_by_test[test_num] = []
                    lines_by_test[test_num].append(div.get_text().strip())
                except (ValueError, IndexError):
                    continue

    return lines_by_test


def extract_individual_test_cases(
    input_sections, output_sections
) -> list[tuple[str, str]]:
    if not input_sections or not output_sections:
        return []

    input_by_test = extract_lines_by_test_number(input_sections)
    output_by_test = extract_lines_by_test_number(output_sections)

    if not input_by_test or not output_by_test:
        return []

    tests = []
    test_numbers = sorted(set(input_by_test.keys()) & set(output_by_test.keys()))

    for test_num in test_numbers:
        input_lines = input_by_test.get(test_num, [])
        output_lines = output_by_test.get(test_num, [])

        if not input_lines or not output_lines:
            continue

        input_text = "\n".join(input_lines)
        output_text = "\n".join(output_lines)
        tests.append((input_text, output_text))

    return tests


def scrape(url: str) -> list[tuple[str, str]]:
    try:
        scraper = cloudscraper.create_scraper()
        response = scraper.get(url, timeout=10)
        response.raise_for_status()

        soup = BeautifulSoup(response.text, "html.parser")
        tests: list[tuple[str, str]] = []

        input_sections = soup.find_all("div", class_="input")
        output_sections = soup.find_all("div", class_="output")

        individual_tests = extract_individual_test_cases(
            input_sections, output_sections
        )

        if individual_tests:
            return individual_tests

        all_inputs = extract_combined_text(input_sections)
        all_outputs = extract_combined_text(output_sections)

        if all_inputs and all_outputs:
            combined_input = "\n".join(all_inputs)
            combined_output = "\n".join(all_outputs)
            tests.append((combined_input, combined_output))

        return tests

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
            href: str = link.get("href", "")
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


def scrape_with_both_formats(
    url: str,
) -> tuple[list[tuple[str, str]], tuple[str, str] | None]:
    try:
        scraper = cloudscraper.create_scraper()
        response = scraper.get(url, timeout=10)
        response.raise_for_status()

        soup = BeautifulSoup(response.text, "html.parser")

        input_sections = soup.find_all("div", class_="input")
        output_sections = soup.find_all("div", class_="output")

        individual_tests = extract_individual_test_cases(
            input_sections, output_sections
        )

        all_inputs = extract_combined_text(input_sections)
        all_outputs = extract_combined_text(output_sections)

        combined = None
        if all_inputs and all_outputs:
            combined_input = "\n".join(all_inputs)
            combined_output = "\n".join(all_outputs)
            combined = (combined_input, combined_output)

        return individual_tests, combined

    except Exception as e:
        print(f"CloudScraper failed: {e}", file=sys.stderr)
        return [], None


def main() -> None:
    if len(sys.argv) < 2:
        result: dict[str, str | bool] = {
            "success": False,
            "error": "Usage: codeforces.py metadata <contest_id> OR codeforces.py tests <contest_id> <problem_letter>",
        }
        print(json.dumps(result))
        sys.exit(1)

    mode: str = sys.argv[1]

    if mode == "metadata":
        if len(sys.argv) != 3:
            result: dict[str, str | bool] = {
                "success": False,
                "error": "Usage: codeforces.py metadata <contest_id>",
            }
            print(json.dumps(result))
            sys.exit(1)

        contest_id: str = sys.argv[2]
        problems: list[dict[str, str]] = scrape_contest_problems(contest_id)

        if not problems:
            result: dict[str, str | bool] = {
                "success": False,
                "error": f"No problems found for contest {contest_id}",
            }
            print(json.dumps(result))
            sys.exit(1)

        result: dict[str, str | bool | list] = {
            "success": True,
            "contest_id": contest_id,
            "problems": problems,
        }
        print(json.dumps(result))

    elif mode == "tests":
        if len(sys.argv) != 4:
            result: dict[str, str | bool] = {
                "success": False,
                "error": "Usage: codeforces.py tests <contest_id> <problem_letter>",
            }
            print(json.dumps(result))
            sys.exit(1)

        contest_id: str = sys.argv[2]
        problem_letter: str = sys.argv[3]
        problem_id: str = contest_id + problem_letter.lower()

        url: str = parse_problem_url(contest_id, problem_letter)
        print(f"Scraping: {url}", file=sys.stderr)
        individual_tests, combined = scrape_with_both_formats(url)

        if not individual_tests and not combined:
            result: dict[str, str | bool] = {
                "success": False,
                "error": f"No tests found for {contest_id} {problem_letter}",
                "problem_id": problem_id,
                "url": url,
            }
            print(json.dumps(result))
            sys.exit(1)

        test = []
        run = []

        if individual_tests:
            for input_data, output_data in individual_tests:
                test.append({"input": input_data, "output": output_data})
                run.append({"input": f"1\n{input_data}", "output": output_data})
        elif combined:
            test.append({"input": combined[0], "output": combined[1]})
            run.append({"input": combined[0], "output": combined[1]})

        result: dict[str, str | bool | list] = {
            "success": True,
            "problem_id": problem_id,
            "url": url,
            "test": test,
            "run": run,
        }

        print(json.dumps(result))

    else:
        result: dict[str, str | bool] = {
            "success": False,
            "error": f"Unknown mode: {mode}. Use 'metadata' or 'tests'",
        }
        print(json.dumps(result))
        sys.exit(1)


if __name__ == "__main__":
    main()
