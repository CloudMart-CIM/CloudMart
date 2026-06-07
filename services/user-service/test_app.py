"""Unit tests for user-service (in-memory backend)."""

import json
import os

os.environ["DB_BACKEND"] = "memory"

import pytest

from app import app, users_db, SEED_USERS


@pytest.fixture
def client():
    users_db.clear()
    for user in SEED_USERS:
        users_db[user["id"]] = dict(user)

    app.config["TESTING"] = True
    with app.test_client() as test_client:
        yield test_client


def test_health(client):
    response = client.get("/health")
    assert response.status_code == 200
    assert response.get_json()["status"] == "healthy"


def test_ready(client):
    response = client.get("/ready")
    assert response.status_code == 200
    assert response.get_json()["status"] == "ready"


def test_login_success(client):
    response = client.post(
        "/auth/login",
        data=json.dumps({"email": "alice@cloudmart.example", "password": "password123"}),
        content_type="application/json",
    )
    assert response.status_code == 200
    body = response.get_json()
    assert "token" in body
    assert body["user"]["email"] == "alice@cloudmart.example"


def test_login_invalid_password(client):
    response = client.post(
        "/auth/login",
        data=json.dumps({"email": "alice@cloudmart.example", "password": "wrong-password"}),
        content_type="application/json",
    )
    assert response.status_code == 401


def test_register_and_profile(client):
    register_response = client.post(
        "/auth/register",
        data=json.dumps(
            {
                "name": "Test User",
                "email": "newuser@example.com",
                "password": "password123",
            }
        ),
        content_type="application/json",
    )
    assert register_response.status_code == 201
    token = register_response.get_json()["token"]

    profile_response = client.get(
        "/users/me",
        headers={"Authorization": f"Bearer {token}"},
    )
    assert profile_response.status_code == 200
    assert profile_response.get_json()["email"] == "newuser@example.com"


def test_register_duplicate_email(client):
    response = client.post(
        "/auth/register",
        data=json.dumps(
            {
                "name": "Duplicate",
                "email": "alice@cloudmart.example",
                "password": "password123",
            }
        ),
        content_type="application/json",
    )
    assert response.status_code == 409
