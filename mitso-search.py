"""
Mitso Research Script
=====================
Default: WebSearch (built-in) + Bing headful Playwright — free, parallel, fast.
Deep mode (--deep): adds Perplexity Sonar Pro via OpenRouter — paid, use when free results are thin
or a real decision is on the line.
Fetch mode (--fetch N): auto-fetches full content of top N Bing results (default N=3).

Usage:
    python3 mitso-search.py "your query"              # Bing only (URLs + snippets)
    python3 mitso-search.py "your query" --fetch      # Bing + fetch top 3 full pages
    python3 mitso-search.py "your query" --fetch 5   # Bing + fetch top 5 full pages
    python3 mitso-search.py "your query" --deep       # Bing + Sonar synthesis
"""

import asyncio
import sys
import re
import base64
import httpx
from urllib.parse import quote_plus, urlparse, parse_qs
from playwright.async_api import async_playwright

OPENROUTER_KEY = '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'


def decode_bing_url(url):
    """Decode Bing tracking redirect URLs to get the real destination URL."""
    if 'bing.com/ck/' not in url:
        return url
    try:
        parsed = urlparse(url)
        params = parse_qs(parsed.query)
        u_param = params.get('u', [''])[0]
        if u_param.startswith('a1'):
            u_param = u_param[2:]  # strip 'a1' prefix
        # Add padding if needed
        padding = 4 - len(u_param) % 4
        if padding != 4:
            u_param += '=' * padding
        decoded = base64.urlsafe_b64decode(u_param).decode('utf-8', errors='ignore')
        if decoded.startswith('http'):
            return decoded
    except Exception:
        pass
    return url


async def bing_search(query, max_results=10):
    async with async_playwright() as p:
        browser = await p.chromium.launch(headless=False, args=['--no-sandbox', '--disable-gpu'])
        page = await browser.new_page(
            user_agent='Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36'
        )
        url = f'https://www.bing.com/search?q={quote_plus(query)}&scope=web&FORM=HDRSC1'
        await page.goto(url, wait_until='domcontentloaded', timeout=15000)
        raw = await page.evaluate(
            'Array.from(document.querySelectorAll("li.b_algo")).map(item => {'
            '  const a = item.querySelector("h2 a");'
            '  const snip = item.querySelector(".b_caption p, .b_lineclamp2, .b_paractl");'
            '  return { title: a ? a.innerText : "", href: a ? a.href : "", snippet: snip ? snip.innerText.slice(0,200) : "" };'
            '})'
        )
        await browser.close()
        results = []
        seen = set()
        for item in raw:
            u = decode_bing_url(item.get('href', '').strip())
            if not u or not u.startswith('http') or u in seen:
                continue
            seen.add(u)
            results.append({'title': item['title'][:150], 'url': u, 'snippet': item['snippet']})
            if len(results) >= max_results:
                break
        return results


async def fetch_url_content(url, max_chars=4000):
    """Fetch full text content from a URL, stripping HTML tags."""
    try:
        async with httpx.AsyncClient(follow_redirects=True, timeout=15) as client:
            headers = {'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'}
            resp = await client.get(url, headers=headers)
            resp.raise_for_status()
            html = resp.text
            # Strip scripts and styles
            html = re.sub(r'<(script|style)[^>]*>.*?</(script|style)>', '', html, flags=re.DOTALL | re.IGNORECASE)
            # Strip all remaining HTML tags
            text = re.sub(r'<[^>]+>', ' ', html)
            # Collapse whitespace
            text = re.sub(r'\s+', ' ', text).strip()
            return text[:max_chars]
    except Exception as e:
        return f'[fetch failed: {e}]'


async def sonar_search(query):
    async with httpx.AsyncClient() as client:
        resp = await client.post(
            'https://openrouter.ai/api/v1/chat/completions',
            headers={'Authorization': f'Bearer {OPENROUTER_KEY}', 'Content-Type': 'application/json'},
            json={
                'model': 'perplexity/sonar-pro',
                'messages': [
                    {'role': 'system', 'content': 'You are a research assistant. Answer with specific facts, tool names, pricing, pros/cons. Be concise and structured.'},
                    {'role': 'user', 'content': query}
                ],
                'max_tokens': 2048,
            },
            timeout=30,
        )
        resp.raise_for_status()
        data = resp.json()
        return data['choices'][0]['message']['content']


async def main(query, deep=False, fetch_n=0):
    mode_parts = []
    if fetch_n:
        mode_parts.append(f'Bing + fetch top {fetch_n}')
    else:
        mode_parts.append('Bing (standard)')
    if deep:
        mode_parts.append('Sonar (deep)')
    print(f'Searching: "{query}"')
    print(f'Mode: {" + ".join(mode_parts)}\n')

    if deep:
        bing_task = asyncio.create_task(bing_search(query))
        sonar_task = asyncio.create_task(sonar_search(query))
        bing_results, sonar_text = await asyncio.gather(bing_task, sonar_task)
    else:
        bing_results = await bing_search(query)
        sonar_text = None

    print('=== BING RESULTS ===')
    for i, r in enumerate(bing_results, 1):
        print(f'{i}. {r["title"]}')
        print(f'   {r["url"]}')
        if r['snippet']:
            print(f'   {r["snippet"]}')
    print()

    if fetch_n and bing_results:
        targets = bing_results[:fetch_n]
        print(f'=== FETCHING FULL CONTENT (top {len(targets)}) ===\n')
        fetch_tasks = [fetch_url_content(r['url']) for r in targets]
        contents = await asyncio.gather(*fetch_tasks)
        for r, content in zip(targets, contents):
            print(f'--- {r["title"]} ---')
            print(f'URL: {r["url"]}')
            print(content)
            print()

    if sonar_text:
        print('=== SONAR SYNTHESIS ===')
        print(sonar_text)


if __name__ == '__main__':
    args = sys.argv[1:]
    deep_mode = '--deep' in args

    # Parse --fetch [N] — default N=3 if flag present without number
    fetch_n = 0
    if '--fetch' in args:
        idx = args.index('--fetch')
        args.pop(idx)
        if idx < len(args) and args[idx].isdigit():
            fetch_n = int(args.pop(idx))
        else:
            fetch_n = 3

    query_args = [a for a in args if not a.startswith('--')]
    query = ' '.join(query_args) if query_args else 'best tools 2026'
    asyncio.run(main(query, deep=deep_mode, fetch_n=fetch_n))
