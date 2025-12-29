#!/usr/bin/env bash
set -euo pipefail

APP_PATH="${APP_PATH:-./ScreenshotTool.app/ScreenshotTool}"
OUTPUT_PATH="${1:-Screenshots/app-screenshot.png}"

if ! command -v wmctrl >/dev/null 2>&1; then
  echo "capture_app_screenshot: wmctrl is required but not found in PATH." >&2
  exit 1
fi

SCREENSHOT_TOOL=""
if command -v gnome-screenshot >/dev/null 2>&1; then
  SCREENSHOT_TOOL="gnome-screenshot"
elif command -v import >/dev/null 2>&1; then
  SCREENSHOT_TOOL="import"
else
  echo "capture_app_screenshot: gnome-screenshot or ImageMagick import is required but neither is available." >&2
  exit 1
fi

mkdir -p "$(dirname "$OUTPUT_PATH")"

"$APP_PATH" >/dev/null 2>&1 &
APP_PID=$!

cleanup() {
  if ps -p "$APP_PID" >/dev/null 2>&1; then
    kill "$APP_PID" >/dev/null 2>&1 || true
    wait "$APP_PID" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

WINDOW_ID=""
for _ in {1..40}; do
  WINDOW_ID=$(wmctrl -lx | awk '{ if (index($3, "ScreenshotTool") != 0) { print $1; exit } }')
  if [[ -n "$WINDOW_ID" ]]; then
    break
  fi
  sleep 0.5
done

if [[ -z "$WINDOW_ID" ]]; then
  echo "capture_app_screenshot: failed to detect the ScreenshotTool window." >&2
  exit 1
fi

wmctrl -ia "$WINDOW_ID"
sleep 1

if [[ "$SCREENSHOT_TOOL" == "gnome-screenshot" ]]; then
  gnome-screenshot --window --file="$OUTPUT_PATH"
else
  import -window "$WINDOW_ID" "$OUTPUT_PATH"
fi
echo "Screenshot saved to $OUTPUT_PATH"
