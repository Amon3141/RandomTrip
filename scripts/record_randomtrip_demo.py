#!/usr/bin/env python3
"""
Record a short RandomTrip demo (log in, spin, destination, moving).

  pip install -r scripts/requirements-demo.txt
  python -m playwright install chromium
  python scripts/record_randomtrip_demo.py

Starts ``runserver`` (after migrate), then records with Playwright. Requires ffmpeg
for the optional H.264 ``--mp4`` output.
"""
from __future__ import annotations

import argparse
import os
import shutil
import signal
import subprocess
import sys
import tempfile
import time
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
if str(REPO) not in sys.path:
    sys.path.insert(0, str(REPO))
os.environ.setdefault("DJANGO_SETTINGS_MODULE", "config.settings")
os.chdir(REPO)


def _default_out() -> Path:
    cloud = Path("/opt/cursor/artifacts")
    if cloud.is_dir():
        return cloud / "randomtrip-demo.webm"
    d = REPO / "demo_output"
    d.mkdir(exist_ok=True)
    return d / "randomtrip-demo.webm"


def _ensure_demo_user(username: str, password: str) -> None:
    import django

    django.setup()
    from django.contrib.auth import get_user_model

    User = get_user_model()
    u, _ = User.objects.get_or_create(
        username=username,
        defaults={"email": f"{username}@example.com"},
    )
    u.set_password(password)
    u.save()


def _run_migrate() -> int:
    return subprocess.call(
        [sys.executable, "manage.py", "migrate", "--noinput"],
        cwd=REPO,
    )


def _record(
    base_url: str,
    username: str,
    password: str,
    out_webm: Path,
    out_mp4: Path | None,
) -> None:
    from playwright.sync_api import sync_playwright

    out_webm.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="randomtrip_v_", dir=out_webm.parent) as tdir:
        tpath = Path(tdir)
        with sync_playwright() as p:
            browser = p.chromium.launch(headless=True)
            context = browser.new_context(
                viewport={"width": 1280, "height": 720},
                record_video_dir=str(tpath),
                record_video_size={"width": 1280, "height": 720},
            )
            context.grant_permissions(["geolocation"], origin=base_url)
            context.set_geolocation({"latitude": 35.6762, "longitude": 139.6503})
            page = context.new_page()

            page.goto(f"{base_url}/accounts/login/", wait_until="networkidle")
            page.locator('input[name="username"]').fill(username)
            page.locator('input[name="password"]').fill(password)
            page.get_by_role("button", name="Log In").click()
            page.wait_for_url("**/", timeout=30_000)

            page.select_option("#distance-input", "10000")
            page.locator("#spin-roulette-link").click()
            page.wait_for_url("**/next-destination/**", timeout=60_000)
            page.wait_for_function(
                """() => {
            const el = document.querySelector('.next-destination-text');
            return el && el.textContent && el.textContent.trim().length > 0;
            }""",
                timeout=30_000,
            )
            # Pause on destination so viewers can read name, address, and description
            page.wait_for_timeout(4500)
            page.locator(".go-to-this-place-button").click()
            page.wait_for_url("**/moving/**", timeout=15_000)
            page.wait_for_timeout(3500)
            page.locator(".arrived-button").click()
            page.wait_for_url("**/", timeout=15_000)
            page.wait_for_timeout(2500)

            context.close()
            browser.close()

        vids = list(tpath.glob("*.webm"))
        if not vids:
            raise RuntimeError(f"No .webm produced in {tpath}")
        shutil.move(str(vids[0]), out_webm)

    if out_mp4 is not None:
        subprocess.check_call(
            [
                "ffmpeg",
                "-y",
                "-i",
                str(out_webm),
                "-c:v",
                "libx264",
                "-pix_fmt",
                "yuv420p",
                "-movflags",
                "+faststart",
                str(out_mp4),
            ]
        )


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", type=Path, default=_default_out(), help="Output .webm path")
    ap.add_argument(
        "--mp4",
        type=Path,
        help="If set, also re-encode to H.264 .mp4 (requires ffmpeg).",
    )
    ap.add_argument("--base-url", default="http://127.0.0.1:8000")
    ap.add_argument(
        "--username", default="demorecorder", help="User created/updated for the demo"
    )
    ap.add_argument("--password", default="Dem0Recorder!")

    args = ap.parse_args()
    out_webm = args.out
    if args.mp4 is None and str(args.out).endswith(".mp4"):
        out_mp4 = args.out
        out_webm = out_mp4.with_suffix(".webm")
    else:
        out_mp4 = args.mp4

    if _run_migrate() != 0:
        return 1
    _ensure_demo_user(args.username, args.password)

    proc = subprocess.Popen(
        [sys.executable, "manage.py", "runserver", "127.0.0.1:8000"],
        cwd=REPO,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    try:
        time.sleep(2.5)
        if proc.poll() is not None:
            print("Django server exited early.", file=sys.stderr)
            return 1
        _record(args.base_url, args.username, args.password, out_webm, out_mp4)
    finally:
        proc.send_signal(signal.SIGTERM)
        try:
            proc.wait(timeout=8)
        except subprocess.TimeoutExpired:
            proc.kill()

    print(f"Wrote: {out_webm}")
    if out_mp4 is not None:
        print(f"Wrote: {out_mp4}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
