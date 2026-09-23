"""Check Chrome startup without isolation headers to catch runtime mismatches.

Requires Chrome and the optional playwright package in the local test environment.
The static test server listens only on loopback and never changes deployed auth.
"""

from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from threading import Thread

from playwright.sync_api import sync_playwright


class QuietHandler(SimpleHTTPRequestHandler):
    def log_message(self, *_args) -> None:
        pass


def main() -> None:
    root = Path(__file__).resolve().parents[1]
    handler = partial(QuietHandler, directory=str(root / "build/web"))
    server = ThreadingHTTPServer(("127.0.0.1", 0), handler)
    Thread(target=server.serve_forever, daemon=True).start()
    try:
        with sync_playwright() as playwright:
            browser = playwright.chromium.launch(
                channel="chrome", headless=True,
                args=["--enable-unsafe-swiftshader", "--use-angle=swiftshader"],
            )
            page = browser.new_page(viewport={"width": 1280, "height": 800})
            errors: list[str] = []
            page.on("console", lambda message: print(message.type, message.text, flush=True))
            page.on("pageerror", lambda error: errors.append(str(error)))
            page.on("requestfailed", lambda request: errors.append(
                f"{request.url}: {request.failure}"
            ))
            try:
                page.goto(f"http://127.0.0.1:{server.server_port}/", wait_until="load")
                page.wait_for_selector("#status", state="detached", timeout=30000)
                # The opening animation reveals Begin Challenge after five seconds.
                page.wait_for_timeout(6000)
                page.screenshot(path=str(root / "build/browser-smoke.png"))
                assert not errors, errors
                print("Chrome startup passed: loader cleared and no browser errors.")
            finally:
                browser.close()
    finally:
        server.shutdown()
        server.server_close()


if __name__ == "__main__":
    main()
