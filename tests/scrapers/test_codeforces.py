from unittest.mock import Mock

from scrapers.codeforces import CodeforcesScraper
from scrapers.models import ContestSummary, ProblemSummary


def test_scrape_success(mocker, mock_codeforces_html):
    mock_client = Mock()
    mock_response = Mock()
    mock_response.text = mock_codeforces_html
    mock_client.get.return_value = mock_response

    scraper = CodeforcesScraper()
    mocker.patch.object(scraper, "_create_client", return_value=mock_client)

    result = scraper.scrape_problem_tests("1900", "A")

    assert result.success == True
    assert len(result.tests) == 1
    assert result.tests[0].input == "1\n3\n1 2 3"
    assert result.tests[0].expected == "6"


def test_scrape_contest_problems(mocker):
    mock_client = Mock()
    mock_response = Mock()
    mock_response.text = """
    <a href="/contest/1900/problem/A">A. Problem A</a>
    <a href="/contest/1900/problem/B">B. Problem B</a>
    """
    mock_client.get.return_value = mock_response

    scraper = CodeforcesScraper()
    mocker.patch.object(scraper, "_create_client", return_value=mock_client)

    result = scraper.scrape_contest_metadata("1900")

    assert result.success == True
    assert len(result.problems) == 2
    assert result.problems[0] == ProblemSummary(id="a", name="A. Problem A")
    assert result.problems[1] == ProblemSummary(id="b", name="B. Problem B")


def test_scrape_network_error(mocker):
    mock_client = Mock()
    mock_client.get.side_effect = Exception("Network error")

    scraper = CodeforcesScraper()
    mocker.patch.object(scraper, "_create_client", return_value=mock_client)

    result = scraper.scrape_problem_tests("1900", "A")

    assert result.success == False
    assert "network error" in result.error.lower()


def test_scrape_contests_success(mocker):
    mock_client = Mock()
    mock_response = Mock()
    mock_response.json.return_value = {
        "status": "OK",
        "result": [
            {"id": 1951, "name": "Educational Codeforces Round 168 (Rated for Div. 2)"},
            {"id": 1950, "name": "Codeforces Round 936 (Div. 2)"},
            {"id": 1949, "name": "Codeforces Global Round 26"},
        ],
    }
    mock_client.get.return_value = mock_response

    scraper = CodeforcesScraper()
    mocker.patch.object(scraper, "_create_client", return_value=mock_client)

    result = scraper.scrape_contest_list()

    assert result.success == True
    assert len(result.contests) == 3
    assert result.contests[0] == ContestSummary(
        id="1951",
        name="Educational Codeforces Round 168 (Rated for Div. 2)",
        display_name="Educational Codeforces Round 168 (Rated for Div. 2)",
    )
    assert result.contests[1] == ContestSummary(
        id="1950",
        name="Codeforces Round 936 (Div. 2)",
        display_name="Codeforces Round 936 (Div. 2)",
    )
    assert result.contests[2] == ContestSummary(
        id="1949",
        name="Codeforces Global Round 26",
        display_name="Codeforces Global Round 26",
    )


def test_scrape_contests_api_error(mocker):
    mock_client = Mock()
    mock_response = Mock()
    mock_response.json.return_value = {"status": "FAILED", "result": []}
    mock_client.get.return_value = mock_response

    scraper = CodeforcesScraper()
    mocker.patch.object(scraper, "_create_client", return_value=mock_client)

    result = scraper.scrape_contest_list()

    assert result.success == False
    assert "no contests found" in result.error.lower()


def test_scrape_contests_network_error(mocker):
    mock_client = Mock()
    mock_client.get.side_effect = Exception("Network error")

    scraper = CodeforcesScraper()
    mocker.patch.object(scraper, "_create_client", return_value=mock_client)

    result = scraper.scrape_contest_list()

    assert result.success == False
    assert "network error" in result.error.lower()
