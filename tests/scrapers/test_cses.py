from unittest.mock import Mock
import pytest
from scrapers.cses import scrape, scrape_all_problems


def test_scrape_success(mocker, mock_cses_html):
    mock_response = Mock()
    mock_response.text = mock_cses_html

    mocker.patch("scrapers.cses.requests.get", return_value=mock_response)

    result = scrape("https://cses.fi/problemset/task/1068")

    assert len(result) == 1
    assert result[0][0] == "3\n1 2 3"
    assert result[0][1] == "6"


def test_scrape_all_problems(mocker):
    mock_response = Mock()
    mock_response.text = """
    <h1>Introductory Problems</h1>
    <a href="/problemset/task/1068">Weird Algorithm</a>
    <a href="/problemset/task/1083">Missing Number</a>
    <h1>Sorting and Searching</h1>
    <a href="/problemset/task/1084">Apartments</a>
    """

    mocker.patch("scrapers.cses.requests.get", return_value=mock_response)

    result = scrape_all_problems()

    assert "Introductory Problems" in result
    assert "Sorting and Searching" in result
    assert len(result["Introductory Problems"]) == 2
    assert result["Introductory Problems"][0] == {
        "id": "1068",
        "name": "Weird Algorithm",
    }


def test_scrape_network_error(mocker):
    mocker.patch("scrapers.cses.requests.get", side_effect=Exception("Network error"))

    result = scrape("https://cses.fi/problemset/task/1068")

    assert result == []
