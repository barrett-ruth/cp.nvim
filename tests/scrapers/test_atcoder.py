from unittest.mock import Mock
import pytest
from scrapers.atcoder import scrape, scrape_contest_problems


def test_scrape_success(mocker, mock_atcoder_html):
    mock_response = Mock()
    mock_response.text = mock_atcoder_html

    mocker.patch("scrapers.atcoder.requests.get", return_value=mock_response)

    result = scrape("https://atcoder.jp/contests/abc350/tasks/abc350_a")

    assert len(result) == 1
    assert result[0][0] == "3\n1 2 3"
    assert result[0][1] == "6"


def test_scrape_contest_problems(mocker):
    mock_response = Mock()
    mock_response.text = """
    <table class="table">
        <tr><th>Task</th><th>Name</th></tr>
        <tr>
            <td></td>
            <td><a href="/contests/abc350/tasks/abc350_a">A - Water Tank</a></td>
        </tr>
        <tr>
            <td></td>
            <td><a href="/contests/abc350/tasks/abc350_b">B - Dentist Aoki</a></td>
        </tr>
    </table>
    """

    mocker.patch("scrapers.atcoder.requests.get", return_value=mock_response)

    result = scrape_contest_problems("abc350")

    assert len(result) == 2
    assert result[0] == {"id": "a", "name": "A - Water Tank"}
    assert result[1] == {"id": "b", "name": "B - Dentist Aoki"}


def test_scrape_network_error(mocker):
    mocker.patch(
        "scrapers.atcoder.requests.get", side_effect=Exception("Network error")
    )

    result = scrape("https://atcoder.jp/contests/abc350/tasks/abc350_a")

    assert result == []
