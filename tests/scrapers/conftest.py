import pytest


@pytest.fixture
def mock_codeforces_html():
    return """
    <div class="time-limit">Time limit: 1 seconds</div>
    <div class="memory-limit">Memory limit: 256 megabytes</div>
    <div class="input">
        <pre>
            <div class="test-example-line-1">3</div>
            <div class="test-example-line-1">1 2 3</div>
        </pre>
    </div>
    <div class="output">
        <pre>
            <div class="test-example-line-1">6</div>
        </pre>
    </div>
    """


@pytest.fixture
def mock_atcoder_html():
    return """
    <h3>Sample Input 1</h3>
    <pre>3
1 2 3</pre>
    <h3>Sample Output 1</h3>
    <pre>6</pre>
    """


@pytest.fixture
def mock_cses_html():
    return """
    <h1>Example</h1>
    <p>Input:</p>
    <pre>3
1 2 3</pre>
    <p>Output:</p>
    <pre>6</pre>
    """
