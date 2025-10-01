from unittest.mock import Mock

from scrapers.codeforces import CodeforcesScraper
from scrapers.models import ContestSummary, ProblemSummary


def test_scrape_success(mocker, mock_codeforces_html):
    mock_page = Mock()
    mock_page.html_content = mock_codeforces_html
    mocker.patch("scrapers.codeforces.StealthyFetcher.fetch", return_value=mock_page)

    scraper = CodeforcesScraper()
    result = scraper.scrape_problem_tests("1900", "A")

    assert result.success
    assert len(result.tests) == 1
    assert result.tests[0].input == "1\n3\n1 2 3"
    assert result.tests[0].expected == "6"


def test_scrape_contest_problems(mocker):
    html = """
    <a href="/contest/1900/problem/A">A. Problem A</a>
    <a href="/contest/1900/problem/B">B. Problem B</a>
    """
    mock_page = Mock()
    mock_page.html_content = html
    mocker.patch("scrapers.codeforces.StealthyFetcher.fetch", return_value=mock_page)

    scraper = CodeforcesScraper()
    result = scraper.scrape_contest_metadata("1900")

    assert result.success
    assert len(result.problems) == 2
    assert result.problems[0] == ProblemSummary(id="a", name="A. Problem A")
    assert result.problems[1] == ProblemSummary(id="b", name="B. Problem B")


def test_scrape_network_error(mocker):
    mocker.patch(
        "scrapers.codeforces.StealthyFetcher.fetch",
        side_effect=Exception("Network error"),
    )

    scraper = CodeforcesScraper()
    result = scraper.scrape_problem_tests("1900", "A")

    assert not result.success
    assert "network error" in result.error.lower()


def test_scrape_contests_success(mocker):
    mock_response = Mock()
    mock_response.json.return_value = {
        "status": "OK",
        "result": [
            {"id": 1951, "name": "Educational Codeforces Round 168 (Rated for Div. 2)"},
            {"id": 1950, "name": "Codeforces Round 936 (Div. 2)"},
            {"id": 1949, "name": "Codeforces Global Round 26"},
        ],
    }
    mocker.patch("scrapers.codeforces.requests.get", return_value=mock_response)

    scraper = CodeforcesScraper()
    result = scraper.scrape_contest_list()

    assert result.success
    assert len(result.contests) == 3
    assert result.contests[0] == ContestSummary(
        id="1951",
        name="Educational Codeforces Round 168 (Rated for Div. 2)",
        display_name="Educational Codeforces Round 168 (Rated for Div. 2)",
    )


def test_scrape_contests_api_error(mocker):
    mock_response = Mock()
    mock_response.json.return_value = {"status": "FAILED", "result": []}
    mocker.patch("scrapers.codeforces.requests.get", return_value=mock_response)

    scraper = CodeforcesScraper()
    result = scraper.scrape_contest_list()

    assert not result.success
    assert "no contests found" in result.error.lower()


def test_scrape_contests_network_error(mocker):
    mocker.patch(
        "scrapers.codeforces.requests.get", side_effect=Exception("Network error")
    )

    scraper = CodeforcesScraper()
    result = scraper.scrape_contest_list()

    assert not result.success
    assert "network error" in result.error.lower()
