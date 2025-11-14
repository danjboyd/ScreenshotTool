#!/usr/bin/env python3
import base64
import json
import os
import pathlib
import sys
import urllib.request

ICON_SPECS = [
    ("Select", "a selection marquee: rounded rectangle with a dashed border and a small grab handle"),
    ("Highlighter", "an angled highlighter marker tip with a translucent aqua ink trail"),
    ("Pen", "a vertical fountain pen nib silhouette with a breather hole"),
    ("Text", "an elegant capital letter T representing the text tool"),
    ("Eraser", "a beveled pink-and-blue eraser form split diagonally"),
    ("Copy", "a forward motion arrow implying copy/export"),
    ("Preferences", "a circular gear with a glowing aqua hub"),
]

BASE_PROMPT = (
    "Design a flat minimalist toolbar icon for a screenshot annotation app. "
    "The icon must sit on a transparent background and be centered with at least 12px of padding inside a 512x512 canvas. "
    "Style: high-contrast glyphs tuned for a dark Sombre UI (#2f3135). "
    "Palette: soft neutrals #dfe5ec / #88909c plus aqua accent #4dd0e1 (use #5ef2ff for highlights if needed). "
    "Keep stroke weights consistent, avoid gradients and shadows, and render only the glyph (no background plate). "
)

API_URL = "https://api.openai.com/v1/images/generations"
OVERWRITE = os.environ.get("AI_ICON_OVERWRITE", "0") == "1"


def require_api_key() -> str:
    api_key = os.environ.get("OPENAI_API_KEY")
    if not api_key:
        sys.exit("OPENAI_API_KEY is not set. Source local.env first.")
    return api_key


def call_openai(api_key: str, prompt: str) -> bytes:
    payload = {
        "model": "gpt-image-1",
        "prompt": prompt,
        "size": "1024x1024",
        "background": "transparent",
    }
    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        API_URL,
        data=data,
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
        },
    )
    with urllib.request.urlopen(req) as resp:
        body = resp.read()
    result = json.loads(body)
    b64 = result["data"][0]["b64_json"]
    return base64.b64decode(b64)


def main() -> None:
    api_key = require_api_key()
    output_dir = pathlib.Path("Resources/AIIcons")
    output_dir.mkdir(parents=True, exist_ok=True)

    for name, detail in ICON_SPECS:
        prompt = f"{BASE_PROMPT} Glyph description: {detail}."
        out_path = output_dir / f"{name}-draft.png"
        if out_path.exists() and not OVERWRITE:
            print(f"Skipping {name}; {out_path} already exists.")
            continue
        print(f"Generating {name}…", flush=True)
        png_bytes = call_openai(api_key, prompt)
        with open(out_path, "wb") as fh:
            fh.write(png_bytes)
        print(f"  saved {out_path}")


if __name__ == "__main__":
    main()
