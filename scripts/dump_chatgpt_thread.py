"""
Dump a full ChatGPT conversation thread to disk via ChatGPT's own backend API.

Uses the already-logged-in Chrome profile used by the rest of our tooling
(the mitso browser-automation profile) — so no admin, no cookie DB unlock,
no CSP / CORS issues, no DOM scraping of virtualised chat turns.

How it works:
    1. Launch Chrome via undetected-chromedriver on the logged-in profile.
    2. Navigate to the conversation URL so cookies are in scope.
    3. Execute an async fetch() that:
         - GETs /api/auth/session to get the Bearer accessToken
         - GETs /backend-api/conversation/<id> with the Bearer
       and returns the JSON body as a string.
    4. Parse the mapping tree, walk parent chain from current_node to root,
       flatten to [role, text, ts] turns, write JSON + Markdown to disk.

Usage:
    python dump_chatgpt_thread.py <conversation-id> [out-dir]

Writes two files to out-dir (default C:/Users/chris/Downloads):
    chatgpt-thread-<id>.json  — {title, id, turns: [{role,text,ts}, ...]}
    chatgpt-thread-<id>.md    — flattened markdown for human reading

Requires:
    seleniumbase (same dep ecosystem as chatgpt_selenium_post.py)
    A Chrome profile at PROFILE_DIR that is logged in to chatgpt.com.
"""

import argparse
import json
import os
import pathlib
import sys
import time

from seleniumbase import Driver

PROFILE_DIR = r"C:\Users\chris\PROJECTS\mitso\browser-automation\profile"
DEFAULT_OUT = pathlib.Path("C:/Users/chris/Downloads")


FETCH_JS = r"""
const done = arguments[arguments.length - 1];
(async () => {
  try {
    const id = arguments[0];
    const s = await fetch('/api/auth/session', {credentials:'include'});
    const tok = (await s.json()).accessToken;
    if (!tok) { done(JSON.stringify({error:'no_access_token'})); return; }
    const r = await fetch('/backend-api/conversation/' + id, {
      credentials:'include', headers: {'Authorization': 'Bearer ' + tok}
    });
    if (!r.ok) { done(JSON.stringify({error:'fetch_status', status:r.status})); return; }
    const txt = await r.text();
    done(txt);
  } catch(e) { done(JSON.stringify({error:e.message})); }
})();
"""


def clean_locks(profile_dir: str) -> None:
    for root, _, files in os.walk(profile_dir):
        for f in files:
            if f in ("SingletonLock", "SingletonCookie", "SingletonSocket"):
                try:
                    os.remove(os.path.join(root, f))
                except OSError:
                    pass


def flatten(data: dict) -> list[dict]:
    mapping = data.get("mapping", {})
    order: list[str] = []
    node = data.get("current_node")
    while node and node in mapping:
        order.append(node)
        node = mapping[node].get("parent")
    order.reverse()

    turns = []
    for nid in order:
        msg = mapping[nid].get("message")
        if not msg:
            continue
        role = (msg.get("author") or {}).get("role")
        if role not in ("user", "assistant"):
            continue
        parts = (msg.get("content") or {}).get("parts") or []
        text = "\n".join(p if isinstance(p, str) else json.dumps(p) for p in parts)
        turns.append({
            "role": role,
            "text": text,
            "ts": msg.get("create_time"),
        })
    return turns


def write_outputs(data: dict, conv_id: str, out_dir: pathlib.Path) -> tuple[pathlib.Path, pathlib.Path, int]:
    out_dir.mkdir(parents=True, exist_ok=True)
    turns = flatten(data)

    json_path = out_dir / f"chatgpt-thread-{conv_id}.json"
    md_path = out_dir / f"chatgpt-thread-{conv_id}.md"

    json_path.write_text(json.dumps({
        "title": data.get("title"),
        "id": conv_id,
        "turns": turns,
    }, indent=2, ensure_ascii=False), encoding="utf-8")

    lines = [f"# {data.get('title') or conv_id}", f"_Conversation: {conv_id}_", ""]
    for i, t in enumerate(turns, 1):
        lines.append(f"## [{i}] {t['role']}")
        lines.append(t["text"] or "")
        lines.append("")
    md_path.write_text("\n".join(lines), encoding="utf-8")

    return json_path, md_path, len(turns)


def dump(conv_id: str, out_dir: pathlib.Path) -> None:
    clean_locks(PROFILE_DIR)
    print(f"Launching Chrome (profile={PROFILE_DIR})", flush=True)
    driver = Driver(uc=True, headless=False, user_data_dir=PROFILE_DIR)
    try:
        url = f"https://chatgpt.com/c/{conv_id}"
        print(f"Navigating to {url}", flush=True)
        driver.get(url)
        time.sleep(4)
        driver.set_script_timeout(60)
        print("Fetching via /backend-api/conversation ...", flush=True)
        result = driver.execute_async_script(FETCH_JS, conv_id)
        if not result:
            raise SystemExit("Empty result from browser fetch")
        try:
            data = json.loads(result)
        except json.JSONDecodeError as e:
            raise SystemExit(f"JSON decode failed: {e}. Head: {result[:200]}")
        if isinstance(data, dict) and data.get("error"):
            raise SystemExit(f"Fetch error: {data}")
        json_path, md_path, n = write_outputs(data, conv_id, out_dir)
        print(f"Saved {n} turns")
        print(f"JSON: {json_path}")
        print(f"MD:   {md_path}")
    finally:
        try:
            driver.quit()
        except Exception:
            pass


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("conv_id")
    ap.add_argument("out_dir", nargs="?", default=str(DEFAULT_OUT))
    args = ap.parse_args()
    dump(args.conv_id, pathlib.Path(args.out_dir))


if __name__ == "__main__":
    main()
