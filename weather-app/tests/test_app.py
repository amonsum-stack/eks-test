import pytest
from app import app


@pytest.fixture
def client():
    app.config['TESTING'] = True
    with app.test_client() as client:
        yield client


def test_health_check(client):
    """Health endpoint must return 200 — this is what the readiness probe checks."""
    response = client.get('/health')
    assert response.status_code == 200


def test_homepage_loads(client):
    """Homepage must return 200."""
    response = client.get('/')
    assert response.status_code == 200


def test_health_returns_json(client):
    """Health endpoint should return JSON."""
    response = client.get('/health')
    assert response.content_type == 'application/json'