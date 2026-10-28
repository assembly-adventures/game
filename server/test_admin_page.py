"""Staff HTML is protected independently of its navigation link and reporting API."""

import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from fastapi.testclient import TestClient
from itsdangerous import URLSafeTimedSerializer

from server.app import create_app, SESSION_COOKIE


class StaffPageTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        Path(self.temp.name, "index.html").write_text("game")
        env = patch.dict(os.environ, {
            "APP_ORIGIN": "https://game.example", "SESSION_SECRET": "s" * 48,
            "STATIC_DIR": self.temp.name, "AA_STAFF_ONYENS": "professor, TAOnyen",
        })
        env.start()
        self.addCleanup(env.stop)
        self.client = TestClient(create_app(), base_url="https://game.example", follow_redirects=False)
        self.addCleanup(self.client.close)

    def sign_in(self, onyen):
        cookie = URLSafeTimedSerializer("s" * 48, salt="aa-session-v1").dumps({"uid": onyen, "version": 2})
        self.client.cookies.set(SESSION_COOKIE, cookie)

    def test_anonymous_and_student_cannot_read_staff_html(self):
        for method in (self.client.get, self.client.head):
            response = method("/admin")
            self.assertEqual(response.status_code, 401)
            self.assertNotIn("Learning overview", response.text)
        self.sign_in("student")
        for method in (self.client.get, self.client.head):
            response = method("/admin")
            self.assertEqual(response.status_code, 403)
            self.assertNotIn("Learning overview", response.text)

    def test_staff_can_read_page_without_database_or_static_copy(self):
        for onyen in ("professor", "taonyen"):
            self.sign_in(onyen)
            response = self.client.get("/admin")
            self.assertEqual(response.status_code, 200)
            self.assertIn("Learning overview", response.text)
            self.assertIn("/api/admin", response.text)
            self.assertEqual(response.headers["cache-control"], "private, no-store")
            self.assertIn("frame-ancestors 'none'", response.headers["content-security-policy"])
            self.assertTrue(response.headers["content-type"].startswith("text/html"))

    def test_revoking_staff_access_takes_effect_on_next_page_request(self):
        self.sign_in("professor")
        self.assertEqual(self.client.get("/admin").status_code, 200)
        with patch.dict(os.environ, {"AA_STAFF_ONYENS": ""}):
            self.assertEqual(self.client.get("/admin").status_code, 403)


if __name__ == "__main__":
    unittest.main()
