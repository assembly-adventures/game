"""Exercise login and protection of every browser asset without live UNC tokens."""

import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import AsyncMock, patch
from urllib.parse import parse_qs, urlsplit

from fastapi import HTTPException
from fastapi.testclient import TestClient
import httpx
from itsdangerous import URLSafeTimedSerializer

from server.app import create_app, SESSION_COOKIE, verify_token


class LoginTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        for name in ("index.html", "index.js", "index.wasm", "index.pck"):
            Path(self.temp.name, name).write_text("game asset")
        env = patch.dict(os.environ, {"APP_ORIGIN": "https://game.example",
                                     "SESSION_SECRET": "s" * 48, "STATIC_DIR": self.temp.name})
        registration = patch("server.app.register_player")
        registration.start()
        self.addCleanup(registration.stop)
        env.start()
        self.addCleanup(env.stop)
        self.client = TestClient(create_app(), base_url="https://game.example", follow_redirects=False)
        self.addCleanup(self.client.close)

    def begin_login(self):
        response = self.client.get("/auth/login")
        self.assertEqual(response.status_code, 302)
        location = urlsplit(response.headers["location"])
        self.assertEqual(location.netloc, "csxl.unc.edu")
        callback = parse_qs(location.query)["origin"][0]
        self.assertTrue(callback.startswith("game.example/auth/callback/"))
        self.assertNotIn("://", callback)
        # Model CSXL's actual callback construction so a duplicated scheme fails.
        return "https://" + callback

    def test_csxl_callback_has_exactly_one_https_scheme(self):
        callback = self.begin_login()
        parsed = urlsplit(callback)
        self.assertEqual(parsed.scheme, "https")
        self.assertEqual(parsed.netloc, "game.example")
        self.assertTrue(parsed.path.startswith("/auth/callback/"))

    def test_all_assets_require_login(self):
        for path in ("/", "/index.html", "/index.js", "/index.wasm", "/index.pck"):
            with self.subTest(path=path):
                response = self.client.get(path)
                self.assertEqual(response.status_code, 302)
                self.assertEqual(response.headers["location"], "/auth/login")

    def test_health_is_public(self):
        self.assertEqual(self.client.get("/healthz").status_code, 200)

    def test_callback_requires_browser_state(self):
        with patch("server.app.verify_token", new_callable=AsyncMock) as verify:
            response = self.client.get("/auth/callback/forged?token=anything")
            self.assertEqual(response.status_code, 401)
            verify.assert_not_called()

    def test_valid_login_serves_assets_and_clears_login_cookie(self):
        callback = self.begin_login()
        with patch("server.app.verify_token", new_callable=AsyncMock, return_value={"onyen": "testonyen", "pid": "123456789"}):
            response = self.client.get(callback, params={"token": "valid"})
        self.assertEqual(response.status_code, 303)
        cookie = response.headers.get_list("set-cookie")[0]
        for flag in ("Secure", "HttpOnly", "SameSite=lax", "Path=/"):
            self.assertIn(flag, cookie)
        for path in ("/", "/index.js", "/index.wasm", "/index.pck"):
            self.assertEqual(self.client.get(path).status_code, 200)
        self.assertEqual(self.client.get(callback, params={"token": "valid"}).status_code, 401)
        self.assertEqual(self.client.get("/missing").status_code, 404)
        self.assertEqual(self.client.get("/index.wasm").headers["content-type"], "application/wasm")

    def test_rejected_token_never_opens_game(self):
        callback = self.begin_login()
        with patch("server.app.verify_token", new_callable=AsyncMock,
                   side_effect=HTTPException(401, "Invalid token")):
            self.assertEqual(self.client.get(callback, params={"token": "invalid"}).status_code, 401)
        self.assertEqual(self.client.get("/index.pck").status_code, 302)

    def test_tampered_and_expired_cookies_are_rejected(self):
        signer = URLSafeTimedSerializer("s" * 48, salt="aa-session-v1")
        with patch("itsdangerous.timed.time.time", return_value=1):
            expired = signer.dumps({"uid": "testonyen"})
        for cookie in ("forged", expired):
            self.client.cookies.set(SESSION_COOKIE, cookie)
            self.assertEqual(self.client.get("/index.pck").status_code, 302)

    def test_responses_do_not_cache_or_forward_referrers(self):
        response = self.client.get("/auth/login")
        self.assertEqual(response.headers["cache-control"], "private, no-store")
        self.assertEqual(response.headers["referrer-policy"], "no-referrer")

    def test_configuration_fails_closed(self):
        with patch.dict(os.environ, {"SESSION_SECRET": "short"}):
            with self.assertRaises(RuntimeError):
                create_app()


class ProviderTests(unittest.IsolatedAsyncioTestCase):
    async def test_verified_identity_is_returned_for_server_side_storage(self):
        mock = AsyncMock()
        mock.get.return_value = httpx.Response(200, json={"uid": "testonyen", "pid": "123456789"})
        with patch("server.app.httpx.AsyncClient") as client:
            client.return_value.__aenter__.return_value = mock
            self.assertEqual(await verify_token("token"), {"onyen": "testonyen", "pid": "123456789"})
        mock.get.assert_awaited_once_with("https://csxl.unc.edu/verify", params={"token": "token"})

    async def test_upstream_failure_and_bad_identity_fail_closed(self):
        for result, status in ((httpx.Response(401), 401),
                               (httpx.Response(200, json={}), 401),
                               (httpx.Response(200, text="not JSON"), 503)):
            mock = AsyncMock()
            mock.get.return_value = result
            with patch("server.app.httpx.AsyncClient") as client:
                client.return_value.__aenter__.return_value = mock
                with self.assertRaises(HTTPException) as raised:
                    await verify_token("token")
                self.assertEqual(raised.exception.status_code, status)


if __name__ == "__main__":
    unittest.main()
