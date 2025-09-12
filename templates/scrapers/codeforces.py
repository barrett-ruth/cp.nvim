#!/usr/bin/env python3

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
                    if len(input_lines) > 1 and input_lines[0].isdigit():
                        test_count = int(input_lines[0])
                        remaining_input = input_lines[1:]
                        for i in range(min(test_count, len(output_lines))):
                            if i < len(remaining_input):
                                tests.append((remaining_input[i], output_lines[i]))
                    else:
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


def scrape_sample_tests(url: str):
    print(f"Scraping: {url}", file=sys.stderr)
    return scrape(url)


def main():
    if len(sys.argv) != 3:
        print("Usage: codeforces.py <contest_id> <problem_letter>", file=sys.stderr)
        print("Example: codeforces.py 1234 A", file=sys.stderr)
        sys.exit(1)

    contest_id = sys.argv[1]
    problem_letter = sys.argv[2]

    url = parse_problem_url(contest_id, problem_letter)
    tests = scrape_sample_tests(url)

    if not tests:
        print(f"No tests found for {contest_id} {problem_letter}", file=sys.stderr)
        print(
            "Consider adding test cases manually to the io/ directory", file=sys.stderr
        )
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
