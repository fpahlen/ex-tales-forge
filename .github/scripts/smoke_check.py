#!/usr/bin/env python3
"""Smoke check of a deployed Tales Forge app (the security lane, playtest.yml).

    python3 .github/scripts/smoke_check.py https://tales-forge-playtest.fly.dev

Checks, in order:
  1. GET /health answers 200 "ok" (retries for up to 5 minutes while the new
     machine starts).
  2. GET / sends a signed-out visitor to the sign-in page (302 to /admin/login).
  3. GET /admin/login renders the LiveView page (200, data-phx-session).
  4. The LiveView mounts over the websocket (/live/websocket, phx_join gets
     status "ok").

A game turn calls the LLM, which costs money, so no game turn runs here.
Writes a Markdown table to $GITHUB_STEP_SUMMARY when set. Exit 1 when a check
fails. Needs the Python package `websockets` (pip install websockets).
"""

import asyncio
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request
from http.cookiejar import CookieJar


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None


def main(base):
    base = base.rstrip("/")
    jar = CookieJar()
    opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar), NoRedirect())
    results = []

    def get(path):
        req = urllib.request.Request(base + path, headers={"User-Agent": "tales-forge-smoke-check"})
        try:
            with opener.open(req, timeout=20) as resp:
                return resp.status, dict(resp.headers), resp.read().decode("utf-8", "replace")
        except urllib.error.HTTPError as err:
            return err.code, dict(err.headers), err.read().decode("utf-8", "replace")

    def record(name, ok, detail):
        results.append((name, ok, detail))
        print(("PASS " if ok else "FAIL ") + name + ": " + detail, flush=True)
        return ok

    # 1. /health, with retries.
    deadline = time.time() + 300
    while True:
        try:
            status, _, body = get("/health")
        except Exception as err:  # connection refused while the machine starts
            status, body = 0, str(err)
        if status == 200 and body.strip() == "ok":
            record("GET /health", True, "200 ok")
            break
        if time.time() > deadline:
            record("GET /health", False, f"{status} {body[:80]!r} after 5 minutes")
            break
        time.sleep(10)

    # 2. The home page sends a signed-out visitor to the sign-in page.
    status, headers, _ = get("/")
    location = headers.get("location") or headers.get("Location") or ""
    record("GET / (signed out)", status == 302 and "/admin/login" in location, f"{status} -> {location or 'no redirect'}")

    # 3. The sign-in page renders the LiveView.
    status, _, html = get("/admin/login")
    csrf = re.search(r'name="csrf-token" content="([^"]+)"', html)
    main_div = re.search(r'<div[^>]*data-phx-main[^>]*>', html)
    attrs = {}
    if main_div:
        attrs = dict(re.findall(r'(id|data-phx-session|data-phx-static)="([^"]*)"', main_div.group(0)))
    ok = status == 200 and bool(csrf) and "data-phx-session" in attrs
    record("GET /admin/login (LiveView render)", ok, f"{status}, csrf {'yes' if csrf else 'no'}, LiveView {'yes' if attrs else 'no'}")

    # 4. The LiveView mounts over the websocket.
    if ok:
        try:
            reply = asyncio.run(join(base, jar, csrf.group(1), attrs))
            status_ = reply.get("status")
            record("LiveView mount (websocket)", status_ == "ok", f"phx_join {status_}")
        except Exception as err:
            record("LiveView mount (websocket)", False, repr(err)[:200])
    else:
        record("LiveView mount (websocket)", False, "skipped: the page did not render")

    summary = ["### Smoke check: " + base, "", "| Check | Result | Detail |", "| --- | --- | --- |"]
    summary += [f"| {n} | {'PASS' if ok else 'FAIL'} | {d.replace('|', '/')} |" for n, ok, d in results]
    summary.append("")
    summary.append("No game turn: a turn calls the LLM, which costs money.")
    path = os.environ.get("GITHUB_STEP_SUMMARY")
    if path:
        with open(path, "a") as f:
            f.write("\n".join(summary) + "\n")
    return 0 if all(ok for _, ok, _ in results) else 1


async def join(base, jar, csrf, attrs):
    import websockets

    ws_url = re.sub(r"^http", "ws", base) + "/live/websocket?_csrf_token=" + csrf + "&vsn=2.0.0"
    cookie = "; ".join(f"{c.name}={c.value}" for c in jar)
    topic = "lv:" + attrs.get("id", "phx-main")
    payload = {
        "url": base + "/admin/login",
        "params": {"_csrf_token": csrf, "_mounts": 0},
        "session": attrs["data-phx-session"],
        "static": attrs.get("data-phx-static"),
    }
    async with websockets.connect(ws_url, additional_headers={"Cookie": cookie, "Origin": base}, open_timeout=20) as ws:
        await ws.send(json.dumps(["1", "1", topic, "phx_join", payload]))
        deadline = time.time() + 20
        while time.time() < deadline:
            msg = json.loads(await asyncio.wait_for(ws.recv(), timeout=20))
            if msg[2] == topic and msg[3] == "phx_reply":
                return msg[4]
    return {"status": "timeout"}


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(__doc__)
        sys.exit(2)
    sys.exit(main(sys.argv[1]))
