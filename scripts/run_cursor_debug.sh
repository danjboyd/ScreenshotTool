#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="./ScreenshotTool.app/"
DEFAULT_IMAGE="${ROOT_DIR}/Resources/ScreenshotToolIcon.png"
IMAGE_PATH="${1:-$DEFAULT_IMAGE}"
LOG_PATH="${2:-./debug.log}"

if [[ ! -d "$APP_PATH" ]]; then
  echo "ScreenshotTool.app not found at $APP_PATH" >&2
  exit 1
fi

if [[ ! -f "$IMAGE_PATH" ]]; then
  echo "Image not found at '$IMAGE_PATH'" >&2
  echo "Pass a valid image path as the first argument." >&2
  exit 1
fi

echo "Launching ScreenshotTool with SCREENSHOT_CURSOR_DEBUG=1"
echo "Image: $IMAGE_PATH"
echo "Log:   $LOG_PATH"

RUNNER=()
if command -v openapp >/dev/null 2>&1; then
  RUNNER=(openapp "$APP_PATH" "$IMAGE_PATH")
else
  RUNNER=("$APP_PATH/ScreenshotTool" "$IMAGE_PATH")
fi

export PATH="/usr/GNUstep/System/Tools:${PATH}"
export LD_LIBRARY_PATH="/usr/GNUstep/System/Library/Libraries:${LD_LIBRARY_PATH:-}"

SCREENSHOT_CURSOR_DEBUG=1 "${RUNNER[@]}" 2>&1 | tee "$LOG_PATH" &
APP_PID=$!

echo "cursor debug: app pid $APP_PID"

focus_with_xdotool() {
  echo "xdotool: automation started"
  if ! command -v xdotool >/dev/null 2>&1; then
    return
  fi

  local window_id=""
  for _ in $(seq 1 10); do
    local search_output=""
    if search_output="$(xdotool search --name 'ScreenshotTool' 2>/dev/null)"; then
      window_id="$(head -n 1 <<<"$search_output")"
    else
      window_id=""
    fi
    if [[ -n "$window_id" ]]; then
      break
    fi
    sleep 1
  done

  if [[ -z "$window_id" ]]; then
    echo "xdotool: unable to locate ScreenshotTool window" >&2
    return
  fi

  echo "xdotool: focusing window $window_id"
  if command -v wmctrl >/dev/null 2>&1; then
    wmctrl -i -R "$window_id" >/dev/null 2>&1 || true
  fi

  xdotool windowactivate --sync "$window_id" >/dev/null 2>&1 || true
  local center_x="${CURSOR_DEBUG_X:-500}"
  local center_y="${CURSOR_DEBUG_Y:-350}"
  local toolbar_x="${CURSOR_DEBUG_TOOLBAR_X:-500}"
  local toolbar_y="${CURSOR_DEBUG_TOOLBAR_Y:-40}"

  xdotool mousemove --window "$window_id" "$center_x" "$center_y" >/dev/null 2>&1 || true
  echo "xdotool: moved mouse to ${center_x}x${center_y}"
  sleep 0.5
  xdotool mousemove --window "$window_id" "$toolbar_x" "$toolbar_y" >/dev/null 2>&1 || true
  echo "xdotool: moved mouse to toolbar ${toolbar_x}x${toolbar_y}"
}

(
  echo "cursor debug: waiting before automation"
  sleep 1
  echo "cursor debug: invoking xdotool automation"
  focus_with_xdotool
) &
XDO_PID=$!

wait "$APP_PID"
APP_STATUS=$?

wait "$XDO_PID" 2>/dev/null || true

exit "$APP_STATUS"
