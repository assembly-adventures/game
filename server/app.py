"""Require CSXL Onyen login before serving the Godot browser release."""

import os
from pathlib import Path
import secrets
import re
from urllib.parse import urlencode, urlsplit

from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import HTMLResponse, JSONResponse, RedirectResponse, Response
from fastapi.staticfiles import StaticFiles
from starlette.concurrency import run_in_threadpool
import httpx
import psycopg
from itsdangerous import BadSignature, URLSafeTimedSerializer

from .api import router
from .gameplay import register_player
from .reporting import require_staff

SESSION_COOKIE = "__Host-aa-session"
LOGIN_COOKIE = "__Host-aa-login"
SESSION_SECONDS = 8 * 60 * 60
AUTH_ORIGIN = "https://csxl.unc.edu"


async def verify_token(token: str) -> dict[str, str]:
    """Verify roster identity with CSXL; PID is stored only in PostgreSQL."""
    try:
        async with httpx.AsyncClient(timeout=10, follow_redirects=False) as client:
            result = await client.get(f"{AUTH_ORIGIN}/verify", params={"token": token})
        if result.status_code != 200:
            raise HTTPException(401, "UNC login was not accepted. Please sign in again.")
        identity = result.json()
        uid = identity.get("uid")
        pid = str(identity.get("pid", ""))
        if not isinstance(uid, str) or not uid or len(uid) > 128:
            raise HTTPException(401, "UNC login returned an invalid identity.")
        if not re.fullmatch(r"[0-9]{9}", pid):
            raise HTTPException(401, "UNC login returned an invalid roster identifier.")
        return {"onyen": uid, "pid": pid}
    except (httpx.HTTPError, ValueError, AttributeError):
        raise HTTPException(503, "UNC login is temporarily unavailable.") from None


def create_app() -> FastAPI:
    """Build the app with a fixed HTTPS callback origin and required signing key."""
    origin = os.environ["APP_ORIGIN"].rstrip("/")
    parsed = urlsplit(origin)
    if (parsed.scheme != "https" or not parsed.hostname or parsed.path
            or parsed.query or parsed.fragment or parsed.username or parsed.password):
        raise RuntimeError("APP_ORIGIN must be an HTTPS origin without a path")
    secret = os.environ["SESSION_SECRET"]
    if len(secret) < 32:
        raise RuntimeError("SESSION_SECRET must contain at least 32 random characters")
    sessions = URLSafeTimedSerializer(secret, salt="aa-session-v1")
    logins = URLSafeTimedSerializer(secret, salt="aa-login-v1")
    static_dir = Path(os.environ.get("STATIC_DIR", "build/web"))
    static = StaticFiles(directory=static_dir, html=True)
    # The image build gzips the largest files (infra/Dockerfile): the engine alone is 40 MB, 10 MB gzipped.
    gzipped = {name for name in ("index.wasm", "index.pck", "index.js") if (static_dir / f"{name}.gz").is_file()}
    app = FastAPI(docs_url=None, redoc_url=None, openapi_url=None)

    def authenticate(request: Request) -> str:
        try:
            session = sessions.loads(request.cookies.get(SESSION_COOKIE, ""), max_age=SESSION_SECONDS)
            if (not isinstance(session, dict) or not isinstance(session.get("uid"), str)
                    or not session["uid"] or session.get("version") != 2):
                raise BadSignature("Invalid session")
            return session["uid"]
        except BadSignature:
            raise HTTPException(401, "Your session expired. Reload the page to sign in.") from None

    @app.exception_handler(psycopg.Error)
    async def database_unavailable(request: Request, error: psycopg.Error) -> JSONResponse:
        # Database exception details can include identity values; do not log them.
        return JSONResponse({"detail": "Saved progress is temporarily unavailable. Please retry."}, status_code=503)

    @app.middleware("http")
    async def private_responses(request: Request, call_next):
        response = await call_next(request)
        # Only the game's own files set their caching; nothing else, player data included, is ever stored.
        response.headers.setdefault("Cache-Control", "private, no-store")
        response.headers["Referrer-Policy"] = "no-referrer"
        response.headers["X-Content-Type-Options"] = "nosniff"
        return response

    @app.get("/healthz")
    async def health() -> Response:
        return Response("ok\n", media_type="text/plain")

    @app.get("/auth/login")
    async def login() -> RedirectResponse:
        state = secrets.token_urlsafe(32)
        # CSXL prepends https:// itself: its origin is a host/path, not a URL.
        # The callback path carries the browser-bound login state.
        query = urlencode({"origin": f"{parsed.netloc}/auth/callback/{state}", "continue_to": ""})
        response = RedirectResponse(f"{AUTH_ORIGIN}/auth?{query}", status_code=302)
        response.set_cookie(LOGIN_COOKIE, logins.dumps(state), max_age=600,
                            secure=True, httponly=True, samesite="lax", path="/")
        return response

    @app.get("/auth/callback/{state}")
    async def callback(request: Request, state: str, token: str = "") -> RedirectResponse:
        try:
            expected = logins.loads(request.cookies.get(LOGIN_COOKIE, ""), max_age=600)
            if not isinstance(expected, str) or not secrets.compare_digest(expected, state):
                raise BadSignature("Login state mismatch")
        except BadSignature:
            raise HTTPException(401, "Login expired or belongs to another browser. Please sign in again.") from None
        if not token or len(token) > 8192:
            raise HTTPException(401, "Missing or invalid UNC login token.")
        identity = await verify_token(token)
        await run_in_threadpool(register_player, **identity)
        response = RedirectResponse("/", status_code=303)
        response.set_cookie(SESSION_COOKIE, sessions.dumps({"uid": identity["onyen"], "version": 2}), max_age=SESSION_SECONDS,
                            secure=True, httponly=True, samesite="lax", path="/")
        response.delete_cookie(LOGIN_COOKIE, secure=True, httponly=True, samesite="lax")
        return response

    app.include_router(router(authenticate, origin))

    @app.api_route("/admin", methods=["GET", "HEAD"])
    def admin(request: Request) -> Response:
        # A hidden navigation link is only a convenience. Authorize the page itself,
        # and the reporting API independently, using the verified session identity.
        require_staff(authenticate(request))
        response = HTMLResponse(Path(__file__).with_name("admin.html").read_text())
        response.headers["Content-Security-Policy"] = (
            "default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; "
            "connect-src 'self'; img-src 'self'; base-uri 'none'; frame-ancestors 'none'; "
            "form-action 'self'"
        )
        return response

    @app.api_route("/{path:path}", methods=["GET", "HEAD"])
    async def game(request: Request, path: str) -> Response:
        try:
            authenticate(request)
        except HTTPException:
            return RedirectResponse("/auth/login", status_code=302)
        path = path or "index.html"
        if path in gzipped and "gzip" in request.headers.get("accept-encoding", ""):
            # Typed like the original: guess_type ignores the .gz.
            response = await static.get_response(f"{path}.gz", request.scope)
            response.headers["Content-Encoding"] = "gzip"
        else:
            response = await static.get_response(path, request.scope)
        if path in gzipped:
            response.headers["Vary"] = "Accept-Encoding"
        # The game's files are the same for every player, so browsers keep them and ask on each visit
        # whether they changed (ETag). A deploy still reaches everyone straight away.
        response.headers["Cache-Control"] = "private, no-cache"
        return response

    return app
