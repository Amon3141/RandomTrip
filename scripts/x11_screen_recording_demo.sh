#!/bin/bash
# Full X11 screen capture with pointer (ffmpeg) + Chrome + xdotool for RandomTrip.
# Prereq: create config/local_settings.py with CSRF/SESSION _SECURE = False
#   (or rely on settings that allow cookies on http for local dev)
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"
export DISPLAY="${DISPLAY:-:0}"
ART_DIR="${ART_DIR:-/opt/cursor/artifacts}"
OUT_MP4="${OUT_MP4:-$ART_DIR/randomtrip-screen-demo.mp4}"
DEMO_USER="${DEMO_USER:-demorecorder}"
DEMO_PASS="${DEMO_PASS:-Dem0Recorder!}"
CHROME="${CHROME:-/usr/local/bin/google-chrome}"
PROFILE="/tmp/chromium-rt-$(date +%s).$$"

mkdir -p "$ART_DIR"
python3 manage.py migrate --noinput
python3 -c "
import os, django
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'config.settings')
django.setup()
from django.contrib.auth import get_user_model
User = get_user_model()
u, _ = User.objects.get_or_create(
    username='${DEMO_USER}',
    defaults={'email': '${DEMO_USER}@example.com'},
)
u.set_password('${DEMO_PASS}')
u.save()
print('demo user ok')
"

python3 manage.py runserver 127.0.0.1:8000 > /tmp/django-rt.log 2>&1 &
DJPID=$!
cleanup() {
  kill "$DJPID" 2>/dev/null || true
  kill "$FFPID" 2>/dev/null || true
  kill "$CPID" 2>/dev/null || true
  rm -rf "$PROFILE" 2>/dev/null || true
}
trap cleanup EXIT
sleep 2.3

VID_SIZE=$(xdpyinfo | awk '/dimensions/ {print $2; exit}' | tr -d '\r')
# Record full desktop with mouse pointer drawn by grabber
ffmpeg -y -nostdin -f x11grab -video_size "$VID_SIZE" -framerate 25 -draw_mouse 1 \
  -i "$DISPLAY" -t 80 -c:v libx264 -pix_fmt yuv420p -preset veryfast -crf 19 \
  -movflags +faststart "$OUT_MP4" </dev/null &
FFPID=$!
sleep 1.2

"$CHROME" --user-data-dir="$PROFILE" --no-sandbox --no-default-browser-check \
  --new-window --window-size=1200,880 "http://127.0.0.1:8000/accounts/login/" 2>/dev/null &
CPID=$!
sleep 3.2

# Find Chrome: WM_CLASS second field is "google-chrome" (lowercase; see `xprop`)
WID=""
for i in 1 2 3 4 5 6 7 8; do
  WID=$(xdotool search --class "google-chrome" 2>/dev/null | head -1 || true)
  [[ -n "$WID" ]] && break
  WID=$(xdotool search --class "chromium" 2>/dev/null | head -1 || true)
  [[ -n "$WID" ]] && break
  sleep 0.5
done
if [[ -z "$WID" ]]; then
  echo "Chrome window not found" >&2
  exit 1
fi
xdotool windowactivate --sync "$WID" || true
xdotool windowmove --sync "$WID" 200 100
xdotool windowsize --sync "$WID" 1200 880
sleep 0.5
# Click inside the page to focus the tab
eval "$(xdotool getwindowgeometry --shell "$WID")"
xdotool mousemove --sync "$((X+400))" "$((Y+200))" click 1
sleep 0.2

eval "$(xdotool getwindowgeometry --shell "$WID")"
# $X $Y $WIDTH $HEIGHT
# Centered form: right-aligned inputs; click username box (relative to content)
UX=$((X + 820))
UY=$((Y + 300))
# Password field lower
PY=$((Y + 390))
# Log In button
BX=$((X + 920))
BY=$((Y + 470))

xdotool mousemove --sync "$UX" "$UY" click 1
sleep 0.15
xdotool type --delay 12 -- "$DEMO_USER"
xdotool mousemove --sync "$((X+820))" "$PY" click 1
xdotool type --delay 12 -- "$DEMO_PASS"
xdotool mousemove --sync "$BX" "$BY" click 1
sleep 2.8

# Page zoom: Ctrl+ / Ctrl- (key plus/minus, not numpad - works in Chrome)
for _ in 1 2; do xdotool key --delay 250 ctrl+plus; sleep 0.4; done
sleep 0.5
for _ in 1 2; do xdotool key --delay 250 ctrl+minus; sleep 0.4; done
sleep 0.5
xdotool key --delay 200 ctrl+0
sleep 0.5

# Distance <select> — block is ~horizontal center, below header
SX=$((X + 600))
SY=$((Y + 230))
xdotool mousemove --sync "$SX" "$SY" click 1
sleep 0.25
xdotool key Home
for _ in 1 2 3; do xdotool key --delay 120 Down; done
xdotool key Return
sleep 0.35

# Spin
SPX=$((X + 600))
SPY=$((Y + 500))
xdotool mousemove --sync "$SPX" "$SPY" click 1
sleep 5.5
# If geolocation failed, manual path
MANY=$((Y + 380))
xdotool mousemove --sync "$((X+500))" "$MANY" click 1
sleep 0.12
xdotool type --delay 10 -- "35.6762"
xdotool key Tab
xdotool type --delay 10 -- "139.6503"
# Use manual button
xdotool mousemove --sync "$((X+640))" "$((MANY+55))" click 1
sleep 5

# Next destination: zoom, scroll, go to this place
for _ in 1 2; do xdotool key --delay 200 ctrl+plus; sleep 0.25; done
xdotool key --delay 150 Page_Down
sleep 0.3
for _ in 1 2; do xdotool key --delay 200 ctrl+minus; sleep 0.25; done
sleep 0.4
GOPX=$((X + 600))
GOPY=$((Y + 600))
xdotool mousemove --sync "$GOPX" "$GOPY" click 1
sleep 3.2

# Moving: zoom, scroll, Arrived
xdotool key Page_Down
for _ in 1 2; do xdotool key ctrl+plus; sleep 0.15; done
for _ in 1 2; do xdotool key ctrl+minus; sleep 0.15; done
sleep 0.4
ARRX=$((X + 600))
ARRY=$((Y + 620))
xdotool mousemove --sync "$ARRX" "$ARRY" click 1
sleep 3.5
# Mouse wiggle to show pointer
for _ in 1 2 3; do
  xdotool mousemove_relative 180 0
  sleep 0.2
  xdotool mousemove_relative -- -180 0
  sleep 0.2
done
sleep 1.2

wait $FFPID || true
echo "Wrote: $OUT_MP4"
