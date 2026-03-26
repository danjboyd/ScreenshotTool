#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $(basename "$0") <output-file> [size]" >&2
  echo "Reads a DALL·E prompt from stdin, calls the OpenAI Images API, and writes the PNG to <output-file>." >&2
  exit 1
fi

OUTPUT_FILE=$1
IMAGE_SIZE=${2:-1024x1024}

if [[ -z "${OPENAI_API_KEY:-}" ]]; then
  echo "dalle_generate: OPENAI_API_KEY is not set." >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "dalle_generate: jq is required but not installed." >&2
  exit 1
fi

if ! command -v base64 >/dev/null 2>&1; then
  echo "dalle_generate: base64 is required but not installed." >&2
  exit 1
fi

PROMPT=$(cat)
if [[ -z "${PROMPT// }" ]]; then
  echo "dalle_generate: prompt is empty." >&2
  exit 1
fi

PAYLOAD=$(jq -n \
  --arg prompt "$PROMPT" \
  --arg size "$IMAGE_SIZE" \
  '{model:"gpt-image-1",prompt:$prompt,size:$size}')

RESPONSE=$(curl -sS -X POST "https://api.openai.com/v1/images/generations" \
  -H "Authorization: Bearer ${OPENAI_API_KEY}" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD")

if [[ "$(echo "$RESPONSE" | jq -r '.error // empty')" != "" ]]; then
  echo "dalle_generate: API error:" >&2
  echo "$RESPONSE" | jq -r '.error' >&2
  exit 1
fi

IMAGE_B64=$(echo "$RESPONSE" | jq -r '.data[0].b64_json')
if [[ -z "$IMAGE_B64" || "$IMAGE_B64" == "null" ]]; then
  echo "dalle_generate: no image data returned." >&2
  exit 1
fi

echo "$IMAGE_B64" | base64 --decode > "$OUTPUT_FILE"
echo "Saved image to $OUTPUT_FILE"
