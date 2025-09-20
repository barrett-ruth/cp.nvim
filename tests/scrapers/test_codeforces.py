from unittest.mock import Mock
from scrapers.codeforces import scrape, scrape_contest_problems
from scrapers.models import ProblemSummary


def test_scrape_success(mocker, mock_codeforces_html):
    mock_scraper = Mock()
    mock_response = Mock()
    mock_response.text = mock_codeforces_html
    mock_scraper.get.return_value = mock_response

    mocker.patch(
        "scrapers.codeforces.cloudscraper.create_scraper", return_value=mock_scraper
    )

    result = scrape("https://codeforces.com/contest/1900/problem/A")

    assert len(result) == 1
    assert result[0].input == "1\n3\n1 2 3"
    assert result[0].expected == "6"


def test_scrape_contest_problems(mocker):
    mock_scraper = Mock()
    mock_response = Mock()
    mock_response.text = """
    <a href="/contest/1900/problem/A">A. Problem A</a>
    <a href="/contest/1900/problem/B">B. Problem B</a>
    """
    mock_scraper.get.return_value = mock_response

    mocker.patch(
        "scrapers.codeforces.cloudscraper.create_scraper", return_value=mock_scraper
    )

    result = scrape_contest_problems("1900")

    assert len(result) == 2
    assert result[0] == ProblemSummary(id="a", name="A. Problem A")
    assert result[1] == ProblemSummary(id="b", name="B. Problem B")


def test_scrape_network_error(mocker):
    mock_scraper = Mock()
    mock_scraper.get.side_effect = Exception("Network error")

    mocker.patch(
        "scrapers.codeforces.cloudscraper.create_scraper", return_value=mock_scraper
    )

    result = scrape("https://codeforces.com/contest/1900/problem/A")

    assert result == []
