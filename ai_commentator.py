#!/usr/bin/env python3
"""
AI Commentator sidecar for CS 1.6 server.
Reads game events from AMX plugin, sends to Cloudflare Workers AI (Gemma 4),
and writes AI responses back for the plugin to display in chat.

Usage: python3 ai_commentator.py

Environment variables:
  CF_ACCOUNT_ID  - Cloudflare account ID
  CF_API_TOKEN   - Cloudflare API token (Workers AI permission)
"""

import os
import sys
import time
import json
import urllib.request
import urllib.error

# --- Config ---
EVENTS_FILE = "/hlds/cstrike/addons/amxmodx/data/ai_events.txt"
RESPONSES_FILE = "/hlds/cstrike/addons/amxmodx/data/ai_responses.txt"
MODEL = "@cf/google/gemma-4-26b-a4b-it"
CHECK_INTERVAL = 5  # seconds between checks
MIN_EVENTS_FOR_COMMENT = 2  # minimum events before generating a comment
MAX_EVENTS_BATCH = 10  # max events to send per AI call

CF_ACCOUNT_ID = os.environ.get("CF_ACCOUNT_ID", "")
CF_API_TOKEN = os.environ.get("CF_API_TOKEN", "")

SYSTEM_PROMPT = """You are a fun, energetic Counter-Strike 1.6 game commentator named AITEKLABS AI.
You watch the game events and make short, entertaining comments in the chat.

Rules:
- Keep comments to 1 sentence max (under 100 characters)
- Be funny, hype, or sarcastic
- Use CS slang: "headshot!", "clutch!", "eco round", "rush B", "camper!", "ace!"
- React to headshots with extra excitement
- Never be toxic or offensive
- Write in English
- Do NOT use emojis
- Do NOT repeat the event, just comment on it creatively"""


def call_cloudflare_ai(events_text: str) -> str:
    """Call Cloudflare Workers AI with game events."""
    if not CF_ACCOUNT_ID or not CF_API_TOKEN:
        return ""

    url = f"https://api.cloudflare.com/client/v4/accounts/{CF_ACCOUNT_ID}/ai/run/{MODEL}"

    payload = json.dumps({
        "messages": [
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": f"Game events:\n{events_text}\n\nGive ONE short comment:"}
        ],
        "max_tokens": 60,
        "temperature": 0.9
    }).encode("utf-8")

    req = urllib.request.Request(
        url,
        data=payload,
        headers={
            "Authorization": f"Bearer {CF_API_TOKEN}",
            "Content-Type": "application/json"
        },
        method="POST"
    )

    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            if data.get("success") and data.get("result", {}).get("response"):
                return data["result"]["response"].strip()
    except (urllib.error.URLError, json.JSONDecodeError, KeyError) as e:
        print(f"[AI] Error calling Cloudflare: {e}", file=sys.stderr)

    return ""


def read_and_clear_events() -> list:
    """Read events from file and clear it."""
    if not os.path.exists(EVENTS_FILE):
        return []

    try:
        with open(EVENTS_FILE, "r") as f:
            lines = [l.strip() for l in f.readlines() if l.strip()]

        # Clear the file
        with open(EVENTS_FILE, "w") as f:
            pass

        return lines[-MAX_EVENTS_BATCH:]  # keep only recent
    except IOError:
        return []


def write_response(text: str):
    """Write AI response for the AMX plugin to read."""
    try:
        with open(RESPONSES_FILE, "a") as f:
            f.write(text + "\n")
    except IOError:
        pass


def main():
    print("[AI Commentator] Starting...")
    print(f"[AI Commentator] Model: {MODEL}")
    print(f"[AI Commentator] Events: {EVENTS_FILE}")
    print(f"[AI Commentator] Responses: {RESPONSES_FILE}")

    if not CF_ACCOUNT_ID or not CF_API_TOKEN:
        print("[AI Commentator] WARNING: CF_ACCOUNT_ID or CF_API_TOKEN not set!")
        print("[AI Commentator] Set them in docker-compose.yml environment section.")
        print("[AI Commentator] Running in dry-run mode (events logged but no AI calls).")

    # Ensure data dir exists
    os.makedirs(os.path.dirname(EVENTS_FILE), exist_ok=True)

    while True:
        time.sleep(CHECK_INTERVAL)

        events = read_and_clear_events()
        if len(events) < MIN_EVENTS_FOR_COMMENT:
            continue

        events_text = "\n".join(events)
        print(f"[AI Commentator] Processing {len(events)} events...")

        if CF_ACCOUNT_ID and CF_API_TOKEN:
            comment = call_cloudflare_ai(events_text)
            if comment:
                # Truncate to fit CS 1.6 chat (max ~128 chars)
                comment = comment[:120]
                write_response(comment)
                print(f"[AI Commentator] Response: {comment}")
        else:
            print(f"[AI Commentator] [DRY-RUN] Events: {events_text[:200]}")


if __name__ == "__main__":
    main()
