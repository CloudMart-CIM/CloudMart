"""Unit tests for user-service (in-memory backend)."""

import json
import os
import unittest

os.environ["DB_BACKEND"] = "memory"

from app import app, users_db, SEED_USERS


class UserServiceTestCase(unittest.TestCase):
    def setUp(self):
        users_db.clear()
        for user in SEED_USERS:
            users_db[user["id"]] = dict(user)

        app.config["TESTING"] = True
        self.client = app.test_client()

    def test_health(self):
        response = self.client.get("/health")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.get_json()["status"], "healthy")

    def test_ready(self):
        response = self.client.get("/ready")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.get_json()["status"], "ready")

    def test_login_success(self):
        response = self.client.post(
            "/auth/login",
            data=json.dumps({"email": "alice@cloudmart.example", "password": "password123"}),
            content_type="application/json",
        )
        self.assertEqual(response.status_code, 200)
        body = response.get_json()
        self.assertIn("token", body)
        self.assertEqual(body["user"]["email"], "alice@cloudmart.example")

    def test_login_invalid_password(self):
        response = self.client.post(
            "/auth/login",
            data=json.dumps({"email": "alice@cloudmart.example", "password": "wrong-password"}),
            content_type="application/json",
        )
        self.assertEqual(response.status_code, 401)

    def test_register_and_profile(self):
        register_response = self.client.post(
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
        self.assertEqual(register_response.status_code, 201)
        token = register_response.get_json()["token"]

        profile_response = self.client.get(
            "/users/me",
            headers={"Authorization": f"Bearer {token}"},
        )
        self.assertEqual(profile_response.status_code, 200)
        self.assertEqual(profile_response.get_json()["email"], "newuser@example.com")

    def test_register_duplicate_email(self):
        response = self.client.post(
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
        self.assertEqual(response.status_code, 409)


if __name__ == "__main__":
    unittest.main()
