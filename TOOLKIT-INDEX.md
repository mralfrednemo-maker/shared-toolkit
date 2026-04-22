# Toolkit Index — read at session start

One-line pointers. For rules, gotchas, quotas, commands → `C:\Users\chris\PROJECTS\shared\TOOLKIT.md`.

Tool names in the first column MUST match a `### <name>` header in TOOLKIT.md (canonical), OR carry `<!-- drift-ignore: <reason> -->`. The drift detector at `shared/scripts/toolkit_drift.py` enforces this.

---

## Knowledge & memory (local, instant)

| Tool | Purpose | How |
|---|---|---|
| QMD — Local Vector Search | Local vector search over memory + tech-library + agent docs | `qmd vsearch "query" -n 5` |
| LightRAG | Graph + vector KB, persistent (Docker, localhost:9621) <!-- drift-ignore: covered via skills, no dedicated TOOLKIT ### --> | skills: `lightrag-query`, `lightrag-upload`, `lightrag-status`, `lightrag-explore`, `lightrag-save-session` |

## Web (fast)

| Tool | Purpose | How |
|---|---|---|
| WebSearch — Built-in Claude Tool | ~10 results, snippets + links | native tool |
| Bing Headful Search — `mitso-search.py` | URLs + snippets, optional fetch or Sonar synthesis | `python mitso-search.py [--fetch\|--deep\|--combined]` |
| Perplexity Sonar Pro — `mitso-search.py --deep` | Paid web synthesis | `mitso-search.py --deep` |
| Firecrawl — MCP + CLI (`firecrawl_search`, `firecrawl_scrape`, etc.) | Search / scrape / crawl / extract / agent / interact | MCP tools `firecrawl_*`, CLI skills `firecrawl-*` |
| Headless / Headful Browser — `mitso/browser-automation/` | Playwright Chromium profiles for authenticated scraping | `node mitso/browser-automation/setup-login.js` |
| Generic Navigation — `mitso/browser-automation/navigate.js` | Full headful/headless website interaction — click, fill, scroll, extract, tabs, settings | `node mitso/browser-automation/navigate.js --url "..." --actions "click:#btn\|fill:#inp:val"` |
| Headful Login Setup — `mitso/browser-automation/setup-nav.js` | One-time headful login for any site (cookies persist to shared profile) | `node mitso/browser-automation/setup-nav.js --url "https://..."` |

## LLM conversations (minutes)

| Tool | Purpose | How |
|---|---|---|
| ChatGPT — `cg` | ChatGPT — same thread, push back | `cg <prompt>` / `cg new <prompt>` |
| Gemini — `gg` | Gemini Pro — same thread, second opinion | `gg <prompt>` / `gg new <prompt>` |
| Claude Web Opus — `cc` | Claude web (Opus + thinking) — nuanced analysis | `cc <prompt>` / `cc sonnet <p>` / `cc no-think <p>` |
| Claude Web + Research — `cc research` | Claude + live web search, auto-saves to `deus/research/` | `cc research <prompt>` |
| Codex — `cx` | Codex CLI — implementation | `cx <task>` / `cx new` / `cx ro` / `cx bg` / `cx spark` |

## Deep research (10–30 min)

| Tool | Purpose | How |
|---|---|---|
| Gemini Deep Research — `gg dr` | Gemini Deep Research — 100+ sites | `gg dr <prompt>` (≤10/day) |
| ChatGPT Deep Research — `test_chatgpt_deep_research.py` | ChatGPT Deep Research, full report | see TOOLKIT §Tier 4 |

## Thread extraction (read without posting)

| Tool | Purpose | How |
|---|---|---|
| ChatGPT Full-Thread Dump — `dump_chatgpt_thread.py` | Full ChatGPT thread → JSON + MD via backend API | `python shared/scripts/dump_chatgpt_thread.py <conv-id> [out-dir]` |
| `recon_claude_response.py` <!-- drift-ignore: no dedicated TOOLKIT ### yet — add one when promoted from recon to first-class --> | Claude thread read via Selenium profile | `python the-thinker/browser-automation/recon_claude_response.py` — edit THREAD const |
| claude-in-chrome MCP <!-- drift-ignore: browser control layer, documented inline under dump_chatgpt_thread --> | Live Chrome reads (past Cloudflare); DOM virtualised — scroll or use backend | `mcp__claude-in-chrome__*` |

## Browser automation profiles

| Profile | Use |
|---|---|
| `mitso/browser-automation/profile` <!-- drift-ignore: profile path, not a tool --> | Playwright Chromium, authenticated services (Gmail, ChatGPT backend) |
| `chrome-automation-profile-3` <!-- drift-ignore: profile path, not a tool --> | Selenium Claude reads (`recon_claude_response.py`) |
| `chrome-automation-profile-ein-design{,-2,-3}` <!-- drift-ignore: profile path, not a tool --> | ein-design engines (ChatGPT/Gemini/Claude) |

## Pipelines (heavy)

| Pipeline | Purpose | How |
|---|---|---|
| Ein MDP — `the-thinker/ein/ein-mdp.py` + `/ein-mdp-loop` skill | 5-phase adversarial debate across 3 engines | `python ein/ein-mdp.py --phase <p>` or `/ein-mdp-loop` |
| Ein Selenium — `ein-selenium.py` | Direct Selenium deliberation, all engines | `python ein/ein-selenium.py` |
| Ein Design — `ein-design.py` | 5-phase design synthesis (draft → cross_1/2/3 → final) | `python ein/ein-design.py --phase <p> [--resume <ledger>]` or `/ein-design-loop` |
| Pipeline-guard <!-- drift-ignore: has its own ## section, not a ### tool --> | Envelope + PreToolUse hook, fail-closed for launchers | `/pipeline-guard <description>` |
| Agora <!-- drift-ignore: planned, not shipped; not in TOOLKIT yet --> | Multi-LLM debate gateway + dashboard | `C:\Users\chris\PROJECTS\agora\` (architecture drafted) |

## Subagents

| Agent | When |
|---|---|
| Context Compiler | Before briefing another AI or launching a major task |
| Explore Agent | Open-ended codebase scans |
| General-Purpose Agent | Multi-step research |
| Codex rescue <!-- drift-ignore: skill (`/codex:rescue`), not under Tier-7 subagents --> | `/codex:rescue` — second-pass diagnosis or handoff |

## Messaging & sessions

| Tool | Purpose |
|---|---|
| `/msg <agent> <text>` <!-- drift-ignore: skill --> | Send to another Claude Code session |
| `/inbox` <!-- drift-ignore: skill --> | Read unread agent messages |
| `/handover` <!-- drift-ignore: skill --> | Save session + write HANDOVER.md |
| `/resumeintact` <!-- drift-ignore: skill --> | Reload prior session with full prompt history |
| `/techlib` <!-- drift-ignore: skill --> | Save fix/decision to tech library + LightRAG |

## Hard rules (summary — full rules in TOOLKIT.md)

- Never retry a failed `cg`/`gg`/`cc`/`gg dr`/`cc research` more than once. Rate-limited by `browser_safety.py`.
- `cg`/`gg`/`cc` NEVER in background — always synchronous.
- Pipeline-guard BLOCK = stop. Do not bypass.
- `cg new`/`gg new`/`cc new` only for genuinely unrelated topics — breaks thread context.

---

If the right tool isn't in this index, read TOOLKIT.md. If it isn't there either, say so before proposing new code.
