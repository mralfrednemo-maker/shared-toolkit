# Shared Toolkit — Mitso, Deus, Gemini, Codex & Claude Code
**Location:** `C:\Users\chris\PROJECTS\shared\TOOLKIT.md` — canonical, single source of truth
**Last updated:** 2026-05-07
**Maintained by:** ALL agents. Any agent that discovers or adds a new tool updates this file immediately, then runs `qmd update shared && qmd embed shared`.

---

## DECISION GUIDE — Which Tool to Use?

```
Question or research task?
├── Already have context? → QMD first (qmd vsearch)
├── Need current web data? → WebSearch → Bing → Sonar (escalate as needed)
├── Need a second opinion / debate? → cg (ChatGPT) or gg (Gemini)
├── Need deep comprehensive research? → gg dr OR cc research
├── Need 3 LLMs to reach a decision together? → Ein Deliberation (**NOT manual cg+gg+cc**)
├── Need 3 LLMs to co-write a document/spec? → Ein Design (**NOT manual cg+gg+cc**)
└── Need to implement code? → cx (Codex)
```

### Browser Verification Policy

For browser/UI verification, prefer the workspace root Playwright setup from `C:\Users\chris\PROJECTS`: `npx playwright ...`. Use it for repeatable smoke tests, screenshots, console checks, local HTML checks, and desktop/mobile viewport evidence unless a repo has its own Playwright config.

Use Chrome DevTools MCP only as the fallback or interactive inspection tool: quick live-page navigation, JavaScript evaluation, screenshots from the current browser state, or cases where writing a Playwright script would add unnecessary ceremony.

### Browser Operation Decision Node

| Browser task | Use first | Use when |
|---|---|---|
| AFS / AtFirstSite authenticated browser automation | `C:\Users\chris\PROJECTS\afs_web_app\scripts\BROWSER-AUTOMATION.md` | Any AtFirstSite/AFS browser task, Slack app setup via the AFS persistent Chrome profile, or login-preserving Playwright CDP operation |
| Repeatable UI verification, screenshots, console checks, viewport checks | Root Playwright CLI / Playwright test | The result should be reproducible and easy to rerun from logs |
| One-shot authenticated action with saved cookies | `mitso/browser-automation/navigate.js` | The action is short and can close the browser afterward |
| Long stateful authenticated admin work | Live persistent browser (`live-browser.js` or Playwright CDP attach) | Login/session must survive across many agent actions, or the site has Cloudflare/bot checks |
| Quick live-page inspection | Chrome DevTools MCP | Need current-page navigation, JavaScript evaluation, or screenshot with minimal setup |

For AFS Browser Automation searches, the canonical handoff is `C:\Users\chris\PROJECTS\afs_web_app\scripts\BROWSER-AUTOMATION.md`. It documents the persistent Chrome + Playwright CDP approach, screenshot-first rule, and what not to do.

Default rule: do not use Selenium for stateful authenticated website operation when Playwright can attach to or own a persistent Chrome profile. Selenium-owned browser lifecycles are more likely to close, lock, or corrupt the reusable session.

### ChatGPT Thread Continuity Guard

When the task refers to an existing ChatGPT discussion, the thread URL is required context. Phrases such as "continue the discussion", "same thread", "existing ChatGPT", "manual discussion", "submit findings to ChatGPT", "ask for its views", or "resume" mean: do not start a fresh ChatGPT thread.

Before calling ChatGPT for an existing discussion:

1. Search for a task-specific thread lock: `chatgpt-thread-url.txt`, `.chatgpt-thread-url`, `*chatgpt*thread*.txt`, or a run-state field named `chatgpt_thread_url`.
2. If no URL is found, stop and ask the operator for the existing ChatGPT URL.
3. Use the guarded persistent-CDP wrapper. Do not use Selenium or `test_chatgpt_upload.py` for orchestration/audit ChatGPT consultation:

```powershell
powershell -ExecutionPolicy Bypass -File C:\Users\chris\PROJECTS\scripts\invoke-chatgpt-heavy.ps1 -ThreadUrlFile C:\path\to\chatgpt-thread-url.txt -PromptFile C:\path\prompt.md -Output C:\path\response.md
```

Use `-AllowNewThread` only when the operator explicitly asks for a fresh thread or the run ledger explicitly requires one.

For GECL/orchestration audit troubleshooting, use the run-configured CDP profile and port instead: `C:\Users\chris\PROJECTS\chrome-automation-profile-gecl-test-9227` on port `9227`, launched with `scripts\start-chatgpt-persistent-cdp.ps1` and driven by `scripts\chatgpt_persistent_cdp_client.py`, or use `agora\scripts\gecl_full_credibility_submit_gate_review.py`.

---

## PARALLEL EXECUTION — What Can Run Simultaneously?

Each browser tool (`cg`, `gg`, `cc`) runs in its **own independent browser process with its own profile**. They do not share anything. This means:

| Combination | Parallel? | Notes |
|-------------|-----------|-------|
| `cg` + `gg` | ✅ Yes | ChatGPT + Gemini — separate browsers |
| `gg dr` + `cc research` | ✅ Yes | Both are heavyweight (~10–30 min) — launch together |
| `cg` + `gg` + `cc` | ✅ Yes | All three simultaneously — fully independent |
| `cg` + `cg` | ❌ No | Same ChatGPT browser/thread — use `cg new` for a second topic only after the first finishes |
| `gg` + `gg` | ❌ No | Same Gemini thread |
| `cx` + anything | ✅ Yes | Codex is CLI-only, no browser — always parallel-safe |

> **One-at-a-time rule applies only during troubleshooting/setup.** If a browser tool is broken and you're debugging it, fix one at a time to isolate the issue. Once all tools are confirmed working, parallel runs are the default.

## SAFETY — Rate Limiting & No-Retry Rule

All browser/pipeline scripts are protected by `browser_safety.py` (`the-thinker/browser-automation/`):

| Tool | Cooldown | Hourly cap | Daily cap | Lock scope |
|------|----------|------------|-----------|------------|
| `cg` (ChatGPT) | 5s | 30/hour | 200/day | ChatGPT profile |
| `gg` (Gemini) | 5s | 30/hour | 200/day | Gemini profile |
| `cc` (Claude web) | 5s | 30/hour | 200/day | Claude profile |
| `gg dr` (Gemini DR) | 120s | 3/hour | 10/day | Gemini profile |
| ChatGPT DR | 120s | 3/hour | 10/day | ChatGPT profile |
| `cc research` | 60s | 5/hour | 20/day | Claude profile |
| Bing search (`mitso-search.py`) | 5s | 30/hour | 200/day | Playwright |
| Sonar Pro (`--deep`) | 30s | 10/hour | 50/day | Playwright |
| Ein MDP (`watchdog.py`) | 300s | 3/hour | 10/day | Ein pipeline |
| Ein Design (`ein-design.py`) | 300s | 3/hour | 10/day | Ein pipeline |

**Rules:**
- **NEVER retry a failed call more than once.** If it exits non-zero or prints `[SAFETY]`, report the error and STOP.
- Per-profile singleton locks prevent concurrent scripts sharing the same browser profile.
- All scripts exit with code 1 on failure (not 0) so the caller knows to stop.
- `--no-rate-limit` flag exists on all scripts for manual emergency override. Never use it programmatically.

## EIN MDP Browser Keep-Open Launch

Use these exact commands when the goal is to open the three MDP browsers, select the intended models, and leave the windows open for later submit:

- `python the-thinker/ein/ein_preflight.py chatgpt --dry-run --load-only --model thinking-heavy --keep-open`
- `python the-thinker/ein/ein_preflight.py claude --dry-run --load-only --model Sonnet --keep-open`
- `python the-thinker/ein/ein_preflight.py gemini --dry-run --load-only --model Pro --keep-open`

Important:
- `--dry-run` is still required even with `--load-only`; without it, `ein_preflight.py` exits immediately by design.
- These commands were live-verified on `2026-04-26` and successfully left all three browsers open on the correct models.

---

## PIPELINE-GUARD — Fail-closed protection for launcher scripts

**What it is:** a generic framework that blocks protected Bash launchers (`ein-design.py --upload-files`, `ein-mdp.py --upload-files`, etc.) unless a structured **envelope** is attached that declares + verifies the action. Turns LLM attention failures into deterministic code gates.

**Protects against (2026-04-17 disaster classes):**
- parse-to-action count lies (envelope claims 5 uploads, command has 4 → BLOCK)
- Einstein retries (same prompt+model+files re-fired → BLOCK)
- blind preflight / extraction failures (script now emits structured events; inspector sub-agent dispatches)
- missing rejection-appendix loops (skill halts instead of retrying identical prompt)
- mission drift between turns (MISSION.md injected on every UserPromptSubmit hook)

**Where to read the full manual:** `C:/Users/chris/PROJECTS/pipeline-guard/docs/INTEGRATION.md` — complete 9-feature walkthrough + "adding a new pipeline" checklist + "adding a new invariant" checklist.

**Quick reference:**
- `pipeline-guard/guard.py` — CLI validator dispatch
- `pipeline-guard/compute_hash.py` — envelope canonical hash computer
- `pipeline-guard/hooks/pretooluse_guard.py` — PreToolUse hook with `PROTECTED_PATTERNS` (add 1 line per new launcher)
- `pipeline-guard/validators/*` — per-invariant validators (parse_to_action, retry_delta, rejection_appendix_check)
- `pipeline-guard/envelopes/active/*.json` — envelopes currently in flight

**Install:** the PreToolUse hook is already registered in `~/.claude/settings.json`. It fires on every Bash call; commands matching `PROTECTED_PATTERNS` require an envelope or get blocked with a clear reason.

**When you add a new pipeline:** follow the checklist in `pipeline-guard/docs/INTEGRATION.md#3-adding-a-new-pipeline`. Roughly: 1 regex line to `PROTECTED_PATTERNS`, ~15 lines of launcher-side shim, A.6 event emission at failure/complete points, a matching orchestrator skill.

**Shortcut — the `/pipeline-guard` slash command:** before starting work on any new pipeline, launcher script, or multi-phase workflow, type `/pipeline-guard <one-line description>` in Claude Code. The skill at `~/.claude/skills/pipeline-guard/SKILL.md` walks the session through the integration review — reads the manual, applies the decision criteria, runs the §3 checklist if protection is needed, logs the decision to `pipeline-guard/PIPELINE-REVIEWS.jsonl`. Use this instead of trying to remember the integration manual exists.

---

## MAKING A LONG TASK SURVIVE COMPACTION

**When to use:** any multi-step operation that will outlive a single conversation — long pipelines, multi-prompt design sequences, staged migrations, anything where "the session crashed halfway, now what" is a real risk.

**Core principle:** the filesystem is ground truth, not the checklist. A checkbox only reflects what the last session *said* it did. Before resuming, a new session must verify on-disk artefacts and sync the checklist to reality.

### Required file anatomy

Create one markdown file at `C:\Users\chris\.claude\projects\C--Users-chris-PROJECTS\memory\<topic>-todo.md` with these sections in this order:

```
---
name: <topic> — Active Execution Plan (survives compaction)
description: ACTIVE PLAN — <scope>. Read FIRST every session.
type: project
---

# <topic> — Execution Plan

**Status:** ACTIVE | COMPLETED <date>
**Last verified:** <YYYY-MM-DD>   ← re-verify invariants if older than 7 days

## §1 — Resume Procedure       ← what a new session does before anything
  1. Re-sync external state (if plan depends on chat threads, queues, remote APIs)
  2. Verify on-disk artefacts against §6; correct stale checkboxes
  3. Find first unchecked sub-step in §6 — resume from there
  4. Execute ONE sub-step, tick BEFORE moving on
  5. On any non-zero exit / missing file: STOP, append §7, max one retry, page Christo

## §2 — Invariants              ← never-violate rules (numbered)
## §3 — Data Needed             ← table of paths to verify + paths that must NOT exist
## §4 — Parsing / Extraction    ← if plan ingests replies/outputs, format rules go here
## §5 — Bail-out Rules          ← concrete stop conditions
## §6 — Steps                   ← numbered, each with a Verify signature
## §6 — Current State           ← the ONLY mutating section; checkboxes, micro-grained
## §7 — Failure Log             ← append-only; every deviation gets a line
```

### Discipline rules (bake into the file, not just follow by memory)

1. **Tick the checkbox BEFORE the next sub-step starts.** Not after the phase.
2. **One checkbox = one atomic disk-touching operation.** "Run X pipeline" is not one step — it's {launch, save output, verify output}.
3. **Verify from disk, not from checklist.** Every step has a Verify signature (file exists, >N bytes, contains marker). Resumer verifies before trusting any tick.
4. **Failures never silently retry.** Non-zero exit = append §7, max one retry, then stop.
5. **Completed plans stay in place** with `**Status:** COMPLETED <date>` at the top; remove the `ACTIVE PLAN` line from `MEMORY.md`. Do not move the file.
6. **Re-sync external state** as step 1 of the Resume Procedure if the plan depends on anything outside the local filesystem. Example for ChatGPT threads: call `dump_chatgpt_thread.py` and confirm the last message is still the one the plan expects.

### Discovery — how the next session finds it

- **Add a one-line index entry to `MEMORY.md`**, with the prefix `**ACTIVE PLAN:**` so it jumps out during session-start auto-load:
  ```markdown
  ## <Topic>
  - **ACTIVE PLAN:** [<topic> Execution Plan](<topic>-todo.md) — Read FIRST. <one-line status hook>
  ```
- **Re-embed QMD** after each meaningful edit so vector queries surface the plan:
  ```
  qmd update mitso && qmd embed mitso
  ```

### Failure modes each part of the structure addresses

| Failure mode | Structural defense |
|---|---|
| Previous session crashed mid-update → stale checkbox | §1 step 2 (verify from disk), §6 Verify signatures |
| Two sessions resume simultaneously → clobber | _deliberately no lockfile_ (single-user machine); stop if you ever hit this |
| Plan's environment drifted since writing | "Last verified" stale-check, external-state re-sync step |
| Resumer redoes already-complete work | Micro-checkbox granularity, filesystem ground-truth rule |
| Resumer skips a required precondition | §3 Data Needed table read first |
| Silent partial-completion of a step | Each step's Verify signature, one-checkbox-per-atomic-op |
| Plan accumulates undocumented ad-hoc deviations | §7 Failure Log as single source of truth for all anomalies |
| Index entry scrolls off MEMORY.md's auto-load window | Prefix `**ACTIVE PLAN:**` placement near top of MEMORY.md |

### Reference implementation

See `C:\Users\chris\.claude\projects\C--Users-chris-PROJECTS\memory\bodyscan-eindesign-todo.md` — the BodyScan 3D Ein Design P5-P10 plan is written exactly to this template. Copy that file's structure when starting a new survivable plan.

---

## TIER 1 — Local Knowledge (instant, always first)

### QMD — Local Vector Search
**What it does:** Searches our local knowledge base — everything we've ever saved, indexed as vectors. Sub-second. No internet. No cost. The single most important tool to run before anything else.

**Commands:**
```bash
# Claude Code sessions (qmd on PATH):
qmd vsearch "topic"          # Semantic vector search (recommended, ~4s — model cold load)
qmd search "keywords"        # BM25 keyword search (instant, ~1s)
qmd query "topic"            # Hybrid search with LLM expansion (best quality, slower)

# Codex / WSL / sandboxed shells — ALWAYS use the wrapper:
node "C:/Users/chris/PROJECTS/qmd-wrap.mjs" vsearch "topic" -n 3
node "C:/Users/chris/PROJECTS/qmd-wrap.mjs" search "keywords" -n 5
node "C:/Users/chris/PROJECTS/qmd-wrap.mjs" status

# Bootstrap for fresh Codex sessions:
powershell -ExecutionPolicy Bypass -File "C:/Users/chris/PROJECTS/codex-bootstrap.ps1"
```

> **⚠ Codex / sandboxed environments:** the wrapper `qmd-wrap.mjs` is
> MANDATORY. If you call `qmd.js` directly, QMD lands on an empty
> `/tmp/.cache/qmd/index.sqlite` because your shell's `HOME` is not the
> real Windows profile — you'll see "No results found" on every search
> and QMD will start re-downloading the 328MB embedding model into the
> wrong folder. The wrapper pins `INDEX_PATH`, `XDG_CACHE_HOME`, and
> `XDG_CONFIG_HOME` to `C:/Users/chris/.cache` and `C:/Users/chris/.config`
> so Codex sees the real 20MB index with all 810 indexed files and 8
> collections. Diagnosed 2026-04-09.

**Examples:**
```bash
node "C:/Users/chris/PROJECTS/qmd-wrap.mjs" vsearch "telomere shelterin complex" -n 3
node "C:/Users/chris/PROJECTS/qmd-wrap.mjs" search "OpenClaw agent memory silo" -n 5
qmd vsearch "what do we know about senolytics"   # Claude Code shorthand
```

**When to use:** EVERY research session starts here. Before Googling. Before WebSearch. Before asking any LLM. Check what we already know.

**Collections indexed:** deus (27 docs), mitso (2), thinker (17), techlib (106), lightrag (153), memory (52), openclaw (435), shared (1) = ~800 docs total.

---

### XP Orchestrator — Local Claude/Gemini/Codex Runner
**What it does:** Runs the local XP protocol for a target repo, writes plan/scope/review/triage/test artifacts under `.xp-orchestrator/<task-id>/`, and feeds the portal.

**Read first:**
- `C:/Users/chris/PROJECTS/xp-orchestrator/README.md`
- `C:/Users/chris/PROJECTS/xp-orchestrator/INSTRUCTIONS.md`

**Primary modes:**
- `--claude-provider minimax --claude-model opus`  # maps to `MiniMax-M2.7-highspeed`
- `--claude-provider gemini --claude-model gemini-3.1-pro-preview`
- `--claude-provider raw` for direct Claude Code

**Fallback pattern:**
- `--claude-fallback-provider gemini --claude-fallback-model gemini-3.1-pro-preview`
- default chain is `minimax -> gemini -> codex`
- If Minimax/quota fails, the runner retries with Gemini, then Codex takes over as planner/reviewer if both external suppliers are exhausted.

**When to use:** any task that should be built through the orchestrator instead of hand-editing files directly.

---

## TIER 2 — Web Search (free, fast)

### WebSearch — Built-in Claude Tool
**What it does:** Claude's native web search. Returns ~10 results with summaries and links. Fast. Good for recent papers, news, quick fact-checks.

**How:** Just use the built-in WebSearch tool directly.

**Example prompt:** `Search for "senolytics clinical trials 2025"`

**Limitation:** Only ~10 results. No synthesis. Shallow.

---

### Bing Headful Search — `mitso-search.py`
**What it does:** Headful Playwright browser hitting Bing.com. Returns 10 real results with decoded URLs, snippets, and optionally full page content. **Must be headful** — Bing fingerprints headless browsers and returns garbage.

**Commands:**
```bash
# Standard — URLs + snippets only
python3 C:\Users\chris\PROJECTS\mitso-search.py "your query"

# Fetch mode — URLs + snippets + full content of top N pages (default N=3)
python3 C:\Users\chris\PROJECTS\mitso-search.py "your query" --fetch
python3 C:\Users\chris\PROJECTS\mitso-search.py "your query" --fetch 5

# Deep mode — Bing + Sonar Pro synthesis (paid)
python3 C:\Users\chris\PROJECTS\mitso-search.py "your query" --deep

# Combined — fetch + deep
python3 C:\Users\chris\PROJECTS\mitso-search.py "your query" --fetch --deep
```

**Examples:**
```bash
python3 mitso-search.py "rapamycin longevity human trials 2025"
python3 mitso-search.py "senolytics dasatinib quercetin 2025 results" --fetch 3
python3 mitso-search.py "epigenetic reprogramming safety 2025" --fetch --deep
```

**How `--fetch` works:**
1. Bing search returns top 10 results with real decoded URLs (Bing tracking URLs are automatically decoded)
2. `--fetch N` selects the top N results and fetches up to 4000 chars of full page content from each
3. Paywalled sites (Lancet, Nature, Cell) will return 403 — expected. Open-access sources (PMC, preprints, longevity blogs) fetch cleanly.
4. Content is stripped of HTML tags and returned as plain text

**When to use:**
- Standard: quick scan to see what's out there
- `--fetch`: when you need actual content, not just links — use for open-access sources
- `--deep`: when you need synthesis across sources (paid Sonar Pro)

---

### Perplexity Sonar Pro — `mitso-search.py --deep`
**What it does:** Calls Perplexity's Sonar Pro model via OpenRouter. Synthesizes across multiple web sources and returns a structured, cited answer — not just links. Paid.

**Command:**
```bash
python3 C:\Users\chris\PROJECTS\mitso-search.py "your query" --deep
```

**Example:**
```bash
python3 mitso-search.py "what is the current state of epigenetic reprogramming in vivo" --deep
```

**When to use:** When WebSearch + Bing return thin or conflicting results. When you need synthesis, not just links. **Use sparingly — paid.**

**Note:** Citations in Sonar responses are often embedded inline as [1][2] rather than in a separate array. This is expected.

---

### Firecrawl — MCP + CLI (`firecrawl_search`, `firecrawl_scrape`, etc.)
**What it does:** Turns any URL into clean LLM-ready markdown. Built-in search-and-scrape, handles JavaScript-rendered pages, can crawl entire sites, and has a cloud browser for pages requiring login/interaction. Faster and cleaner than WebFetch for web content.

**MCP tools (use directly in Claude Code sessions):**
```
firecrawl_search    — web search + optionally scrapes each result's full content
firecrawl_scrape    — single URL → clean markdown (strips ads/nav/boilerplate)
firecrawl_crawl     — recursively follow all links across a site
firecrawl_map       — discover all URLs on a domain without scraping
firecrawl_extract   — structured data extraction with a schema
firecrawl_browser_* — spin up a cloud Chromium for JS-heavy/auth-gated pages
firecrawl_agent     — autonomous mode: give a task, it navigates and extracts
```

**CLI (Bash, good for saving output):**
```bash
firecrawl scrape <url> -o .firecrawl/out.md              # single page
firecrawl search "query" --scrape -o .firecrawl/out.md   # search + scrape results
firecrawl crawl <url>                                     # full site
firecrawl map <url>                                       # URL discovery only
```

**⚠ Critical rule:** ALWAYS output to a file (`-o .firecrawl/filename.md`) or capture MCP results to disk — never dump raw into context. A 3-result search can return 96k+ chars.

**API key:** `fc-a7c85f5009684e7bac81acb408da1491` (in `~/.claude.json` under PROJECTS mcpServers)

**When to use:**
- Scraping a known URL cleanly → `firecrawl_scrape` (beats WebFetch for content quality)
- Search + read results in one shot → `firecrawl_search` with `scrapeOptions`
- JS-rendered / auth-gated pages → `firecrawl_browser_*`
- Ingesting entire docs site → `firecrawl_crawl`
- No cost advantage over WebSearch for simple queries — use WebSearch for quick lookups, Firecrawl when you need the actual page content

---

### Headless / Headful Browser — `mitso/browser-automation/`
**What it does:** Persistent Playwright Chromium profile for accessing authenticated services (Gmail, Telnyx, dashboards) headlessly. Login once, reuse session forever. No browser visible during automated runs. **Windows-native — runs in Claude Code (Mitso's environment), not in WSL/OpenClaw.**

**Location:** `C:\Users\chris\PROJECTS\mitso\browser-automation\`

#### What's Already Authenticated (as of 2026-04-16):
- Gmail: `mr.alfred.nemo@gmail.com` — use `gmail-search.js`
- Telnyx: `portal.telnyx.com` — use `telnyx-check.js`
- **ChatGPT**: `chatgpt.com` — logged in 2026-04-16. Headless read works with stealth flags (see verified config below).
- **Gemini**: `gemini.google.com` — logged in 2026-04-16. Headless read works.
- **Claude**: ⚠️ cookies saved 2026-04-16 but **vanilla Playwright headless cannot bypass Claude's Cloudflare challenge** (hits `/api/challenge_redirect`). For Claude reads, use `mcp__claude-in-chrome` against the user's live Chrome instead — it's already past Cloudflare. This profile is NOT the right tool for Claude.

**Profile dir:** `C:\Users\chris\PROJECTS\mitso\browser-automation\profile\` — cookies persist here. Never delete.

**Required stealth config for ChatGPT/Gemini headless reads:**
- `headless: true`
- `args: ['--disable-blink-features=AutomationControlled', '--no-sandbox', '--disable-dev-shm-usage']`
- `userAgent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36'`
- `waitUntil: 'domcontentloaded'` — NOT `'networkidle'` (Cloudflare keeps network busy, never fires)
- After `page.goto`, poll `page.title()` for up to 45s until it stops matching `/just a moment|checking your browser|cloudflare/i` — this is how you detect Cloudflare clearing.
- Verified working: `C:\Users\chris\PROJECTS\mitso\browser-automation\verify-logins.js`

#### One-Time Login Setup (add new service)
**File:** `setup-login.js`
```bash
cd "C:\Users\chris\PROJECTS\mitso\browser-automation"
node setup-login.js
# Browser opens visibly. Log in to whatever service you need. Close window. Done.
# Cookies saved to profile/ — reusable forever.
```

#### Ready-to-Use Headless Scripts
**Gmail search:**
```bash
node gmail-search.js "from:telnyx" 5                # Find emails from telnyx, return first 5
node gmail-search.js "subject:activation" 3          # Find activation emails, return first 3
```
Returns: thread list + first email body + all URLs in email.

**Telnyx status check:**
```bash
node telnyx-check.js
```
Returns: active numbers, status, connections, last activity.

#### Boilerplate for New Scripts
Save as `my-script.js` in the `browser-automation/` directory:
```javascript
const { chromium } = require('playwright');
const path = require('path');
const USER_DATA_DIR = path.join(__dirname, 'profile');

(async () => {
  const ctx = await chromium.launchPersistentContext(USER_DATA_DIR, {
    headless: true,
    viewport: { width: 1280, height: 900 }
  });
  const page = ctx.pages()[0] || await ctx.newPage();
  page.setDefaultTimeout(30000);
  
  await page.goto('https://your-service.com', { waitUntil: 'networkidle' });
  await page.waitForTimeout(3000); // let SPAs render
  
  // ... your scraping / interaction code here
  
  console.log(result); // output for Claude Code to capture
  await ctx.close();
})();
```

**Debug trick:** Change `headless: true` to `headless: false` to see the browser while troubleshooting.

#### When to Use
- Reading emails, checking dashboards, scraping authenticated portals
- Any task needing a logged-in browser session
- Faster and more reliable than Chrome MCP for data extraction
- Rate-limited by `browser_safety.py` — see TIER 2 table above

#### Full Documentation
**Complete guide:** `C:\Users\chris\PROJECTS\tech-library\infrastructure\mitso-browser-automation.md`

---

### Live Persistent Browser - authenticated web ops
**What it does:** Keeps one visible Chrome session alive with a dedicated persistent profile while agents send many small actions to it. This is the preferred lane for Shopify, Vercel, Google, Hostinger, dashboards, admin panels, and other authenticated workflows where session continuity matters.

**Use before:** Selenium, ad hoc Chrome launches, or Chrome DevTools MCP for multi-step authenticated admin work.

**Two working patterns:**

1. **Toolkit server:** `live-browser.js` launches a persistent Playwright Chrome context and exposes a small local HTTP action API.
2. **Raw CDP attach:** launch Chrome independently with `--remote-debugging-port=9224` and a dedicated `--user-data-dir`, then attach with Playwright Python `connect_over_cdp("http://127.0.0.1:9224")`.

**Start with the existing toolkit server:**

```powershell
cd C:\Users\chris\PROJECTS\mitso\browser-automation
node live-browser.js --profile-dir "profiles/<site>" --channel chrome --url "https://target-site.com" --port 9224
```

**Then send actions without closing the browser:**

```powershell
Invoke-RestMethod -Method Get -Uri http://127.0.0.1:9224/status
Invoke-RestMethod -Method Post -Uri http://127.0.0.1:9224/action -ContentType application/json -Body '{"type":"screenshot","path":"C:\\Users\\chris\\PROJECTS\\mitso\\browser-automation\\live-browser-screenshot.png","fullPage":true}'
```

**When to use:**
- The user logs in manually and the agent must continue operating inside the same browser.
- The site invalidates headless sessions, prompts for Cloudflare/bot checks, or loses state between fresh browser launches.
- The workflow has many small steps: click, inspect, fill, wait, screenshot, verify, repeat.
- You need cookies/localStorage to survive across script runs.

**Rules:**
- Use a dedicated profile per site: `profiles/<site>`.
- Use installed Chrome with `--channel chrome` on this Windows machine.
- Use one port per live browser; `9224` is the common CDP/admin-work port when free.
- Never run two controllers against the same profile or port at once.
- Do not close the live browser until the authenticated work is complete.
- Use Playwright CLI afterward for repeatable verification when possible; use Chrome DevTools MCP only for lightweight inspection of current browser state.

**Why not Selenium here:** Selenium/undetected-chromedriver often owns and closes the browser lifecycle. Leaving a Selenium-owned browser alive can also block the next automation run on the same profile. Use Selenium only for explicitly documented legacy/specialized scripts; never use it for ChatGPT consultation, ChatGPT Heavy, GECL authority reviews, or orchestration/audit troubleshooting.

---

### Generic Browser Navigation — `navigate.js`
**What it does:** Full headful/headless website navigation — click, fill, scroll, extract, change settings, open/close tabs. Mirrors the OpenClaw Kasm autonomous browser capability, but native Windows Playwright with a persistent profile. Write any interaction as a CLI command.

**Location:** `C:\Users\chris\PROJECTS\mitso\browser-automation\navigate.js`

#### One-Time Setup (login to any site)
```bash
cd C:\Users\chris\PROJECTS\mitso\browser-automation
node setup-nav.js --url "https://target-site.com/login"
# Headful browser opens. Log in manually. Close window.
# Cookies saved to profile/ — reusable for all subsequent headless runs.
```

#### Field Note: Logged-In Settings Work
For authenticated admin panels where the user logs in manually and the agent must change settings, prefer this order:

1. Use `setup-nav.js --profile-dir "profiles/<site>" --url "<login-or-target-url>"` for the human login. Have the user close the browser once authenticated so cookies are flushed to disk.
2. Use `live-browser.js --profile-dir "profiles/<site>" --channel chrome --url "<target-url>" --port <port>` for the actual work when the site has Cloudflare, bot checks, multi-step settings, or stateful admin pages. This keeps one visible browser open and lets Codex inspect/click/fill without losing session state.
3. Use `navigate.js --profile-dir "profiles/<site>" --headless false` for short deterministic actions, screenshots, and extraction. Use headless only after testing it; Hostinger served a Cloudflare gate in headless even though the same profile worked headfully.
4. Use direct public checks outside the browser for verification when possible. Example: after DNS edits, `Resolve-DnsName -Type MX atfirstsite.app -Server 8.8.8.8` was clearer than waiting on vendor UI propagation messages.

Practical lesson from the Hostinger/GoDaddy email-DNS session on 2026-05-06: `live-browser.js` with a dedicated profile was the best tool for logged-in website settings. `navigate.js` was useful for individual probes and short actions, but large batched JS/form actions could trip fragile admin-page postbacks. Chrome DevTools MCP should remain a fallback for lightweight inspection of current browser state, not the primary tool for this workflow.

#### Navigation CLI
```bash
# Basic navigation + screenshot
node navigate.js --url "https://example.com/settings" --screenshot

# Click a button, fill a form, take screenshot
node navigate.js --url "https://example.com" --actions "fill:#username:me|fill:#password:secret|click:.login-btn|screenshot"

# Wait for element to appear, then extract text
node navigate.js --url "https://example.com" --actions "waitFor:.loaded|extract:h1"

# Extract ALL matching elements (e.g. all prices, all links)
node navigate.js --url "https://example.com/products" --extract-all ".price" --extract-all "a[href]"

# Open a link in a new tab, switch to it, extract content
node navigate.js --url "https://example.com" --actions "click:.card[href]|switchTab:1|extract:.detail"

# Scroll to bottom, wait, take screenshot
node navigate.js --url "https://example.com" --actions "scroll:0,2000|wait:500|screenshot"

# Headful mode (watch the browser work)
node navigate.js --url "https://example.com" --actions "click:.next|wait:1000" --headless false

# Multi-step: navigate → login → go to settings → change a toggle
node navigate.js --url "https://example.com/login" --actions "fill:#email:user@test.com|fill:#pass:pass123|click:.submit|waitURL:**/dashboard"
node navigate.js --url "https://example.com/settings" --actions "click:.notifications|click:.toggle-enable|click:.save" --goto-tab 0
```

#### Action Tokens
| Token | Example | What it does |
|-------|---------|--------------|
| `click:selector` | `click:#save-btn` | Single click |
| `fill:selector:value` | `fill:#input:hello` | Clear + type |
| `type:selector:value` | `type:#input:hello` | Append without clearing |
| `select:selector:value` | `select:#country:US` | Dropdown option |
| `press:selector:keys` | `press:#input:Enter` | Click + key press |
| `hover:selector` | `hover:.dropdown` | Mouse hover |
| `dblclick:selector` | `dblclick:#el` | Double click |
| `rightclick:selector` | `rightclick:#el` | Right-click |
| `scroll:selector\|x,y` | `scroll:.footer\|0,500` | Scroll to element or px |
| `wait:n` | `wait:2000` | Sleep n ms |
| `waitFor:selector` | `waitFor:.loaded` | Wait for selector |
| `waitURL:pattern` | `waitURL:**/dashboard` | Wait for URL glob |
| `screenshot` | `screenshot` | Take screenshot |
| `extract:selector` | `extract:.price` | Print first match's text |
| `extractAll:selector` | `extractAll:a` | Print ALL matches' text |
| `extractAttr:selector` | (use `--extract-attr href`) | Extract attribute |
| `switchTab:n` | `switchTab:1` | Switch to tab index |
| `closeTab:n` | `closeTab:0` | Close tab index |
| `goto:url` | `goto:https://...` | Navigate without new page |
| `evaluate:js` | `evaluate:document.title` | Run arbitrary JS |

#### Key Flags
| Flag | Purpose |
|------|---------|
| `--screenshot` | Screenshot at end (saved to `navigate-screenshot.png`) |
| `--screenshot-path <path>` | Custom screenshot path |
| `--extract "sel"` | Extract text from first match |
| `--extract-all "sel"` | Extract text from ALL matches |
| `--extract-attr "href"` | Extract attribute instead of text |
| `--headless false` | Watch the browser work live |
| `--timeout ms` | Page/element timeout (default 30000) |
| `--new-tab url` | Open URL in new tab |
| `--goto-tab n` | Operate on tab index n |
| `--wait-for-selector sel` | Block until selector appears |
| `--cookies "JSON"` | Set cookies before navigation |

#### Write Your Own Interaction
```javascript
// Use the same pattern as navigate.js — persistent profile, stealth flags
const { chromium } = require('playwright');
const path = require('path');
const USER_DATA_DIR = path.join(__dirname, 'profile');

(async () => {
  const ctx = await chromium.launchPersistentContext(USER_DATA_DIR, {
    headless: true,
    viewport: { width: 1280, height: 900 },
    args: ['--disable-blink-features=AutomationControlled','--no-sandbox','--disable-dev-shm-usage'],
  });
  const page = ctx.pages()[0];
  await page.goto('https://your-site.com', { waitUntil: 'domcontentloaded' });
  // ... your custom steps
  await ctx.close();
})();
```

**Rate limit:** Not rate-limited — direct Playwright, no `browser_safety.py` guard. Use responsibly.

---

### ChatGPT Full-Thread Dump — `dump_chatgpt_thread.py`
**What it does:** Exports an entire ChatGPT conversation (all user + assistant turns, in order, with timestamps) to disk as JSON + Markdown. Orders of magnitude faster and cleaner than DOM scraping, and bypasses ChatGPT's UI virtualisation (which only renders turns that get scrolled into view).

**Scope:** read-only transcript export only. Do not use this SeleniumBase path to chat with ChatGPT, submit prompts, upload files, continue orchestration/audit discussions, or handle GECL authority reviews. ChatGPT consultation uses the persistent Chrome CDP path in the `ChatGPT Thread Continuity Guard` above.

**Location:** `C:\Users\chris\PROJECTS\shared\scripts\dump_chatgpt_thread.py`

**Usage:**
```bash
python dump_chatgpt_thread.py <conversation-id> [out-dir]
# out-dir defaults to C:/Users/chris/Downloads
```

**Outputs (in `out-dir`):**
- `chatgpt-thread-<id>.json` — `{title, id, turns: [{role, text, ts}, ...]}`
- `chatgpt-thread-<id>.md`   — flattened, chronological, one `## [N] role` heading per turn

**Example:**
```bash
python C:/Users/chris/PROJECTS/shared/scripts/dump_chatgpt_thread.py 69e0403b-04b8-838f-a55c-ad7f7bd4a392
# Saved 171 turns, 200KB JSON + 190KB markdown
```

**How it works (so you can reuse the technique):**
1. Launches Chrome via `seleniumbase Driver(uc=True)` against the profile at `C:\Users\chris\PROJECTS\mitso\browser-automation\profile` (same profile as `chatgpt_selenium_post.py`).
2. Navigates to `https://chatgpt.com/c/<id>` so cookies are in scope.
3. Executes this async fetch inside the page:
   ```js
   const sess = await fetch('/api/auth/session', {credentials:'include'}).then(r=>r.json());
   const tok  = sess.accessToken;            // ~2 KB bearer JWT
   const r    = await fetch(`/backend-api/conversation/${id}`, {
     credentials:'include',
     headers: {'Authorization': `Bearer ${tok}`}
   });
   return r.text();                          // full thread JSON, mapping + current_node
   ```
4. Parses `mapping` and walks the parent chain up from `current_node` to the root to get the linear ordering (the mapping is a tree because of edits/regens — this picks the visible branch).
5. Filters to `user` / `assistant` roles, flattens `content.parts`, writes to disk.

**Why not simpler approaches (lessons learned):**
- `browser_cookie3` → fails with `RequiresAdminError` because Chrome holds a live lock on the cookie DB; shadow-copy needs admin.
- `claude-in-chrome` MCP + anchor download → silently fails (programmatic download without user gesture gets suppressed by Chrome).
- `claude-in-chrome` MCP + `fetch` POST to a local listener → blocked by ChatGPT's CSP `connect-src` (even with `mode: 'no-cors'`).
- `navigator.clipboard.writeText` in background tab → fails with "Document is not focused".
- `read_network_requests` → returns request metadata only, no response body.
- DOM scraping each turn → works but ChatGPT virtualises the message list; you must scroll each assistant turn into view for its content to render. ~10x slower on long threads, fragile, and loses structured timestamps.

**When to use:**
- Need to reconstruct the full design-sequence history of a long ChatGPT thread (e.g., Ein Design runs).
- Need to audit what was actually said across all rounds without scrolling.
- Need a machine-readable transcript for downstream tools (parse per-turn role + timestamp).

**Requirements:** the mitso profile must be logged in to chatgpt.com. If it isn't, re-run `node C:\Users\chris\PROJECTS\mitso\browser-automation\setup-login.js` and sign in once.

---

## TIER 3 — AI Conversations (minutes, back-and-forth)

### ChatGPT — `cg`
**What it does:** Sends prompt to ChatGPT in the browser, continues same thread. Returns response. Best for debate, idea testing, pushback, synthesis.

**Commands:**
```powershell
cg <prompt>              # Continue current thread
cg new <prompt>          # Start fresh thread (new topic only)

# Attachment / Heavy consults use the persistent-CDP wrapper:
powershell -ExecutionPolicy Bypass -File C:/Users/chris/PROJECTS/scripts/invoke-chatgpt-heavy.ps1 `
  -AllowNewThread `
  -PromptFile C:/path/to/prompt.txt `
  -Files C:/path/to/file1.py,C:/path/to/file2.py `
  -Output C:/path/to/chatgpt-response.md

# GECL/orchestration audit troubleshooting uses the run-configured CDP profile/port:
powershell -ExecutionPolicy Bypass -File C:/Users/chris/PROJECTS/scripts/start-chatgpt-persistent-cdp.ps1 `
  -ProfileDir C:/Users/chris/PROJECTS/chrome-automation-profile-gecl-test-9227 `
  -Port 9227 `
  -StateFile C:/Users/chris/PROJECTS/agora/data/orchestration-watchdog/gecl-chatgpt-cdp-state-9227.json
python C:/Users/chris/PROJECTS/scripts/chatgpt_persistent_cdp_client.py `
  --cdp-url http://127.0.0.1:9227 `
  --mode send `
  --thread-url-file C:/path/to/chatgpt-thread-url.txt `
  --prompt-file C:/path/to/prompt.txt `
  --file C:/path/to/file1.py `
  --file C:/path/to/file2.py `
  --output C:/path/to/chatgpt-response.md
```

**Examples:**
```bash
cg "What are the strongest objections to partial epigenetic reprogramming?"
cg new "Completely different topic: explain the Hayflick limit"
```

**Rules:**
- NEVER use `cg new` mid-topic — kills all context
- Always push back on ChatGPT's answers — don't just accept them
- Good for adversarial review and stress-testing ideas
- Use the persistent-CDP wrapper/client, not Selenium or `test_chatgpt_upload.py`, when the consult needs file uploads, Heavy/Extended Thinking, a saved response, or an existing thread guarantee.
- For generic ChatGPT Heavy calls, prefer `scripts\invoke-chatgpt-heavy.ps1` unless the run config says otherwise. For GECL/orchestration audit troubleshooting, use port `9227` with profile `C:\Users\chris\PROJECTS\chrome-automation-profile-gecl-test-9227`, or use `agora\scripts\gecl_full_credibility_submit_gate_review.py`.

---

### Gemini — `gg`
**What it does:** Sends prompt to Gemini Pro in the browser, continues same thread. Good for second opinions, cross-checking, and broad synthesis.

**Commands:**
```bash
gg <prompt>              # Continue current thread
gg new <prompt>          # Start fresh thread
```

**Examples:**
```bash
gg "Cross-check: is this interpretation of the Yang 2023 paper correct?"
gg new "New topic: what are the latest findings on NAD+ and aging?"
```

**Rule:** Same thread continues automatically. Fresh thread only for genuinely unrelated topics.

---

### Claude Web Opus — `cc`
**What it does:** Sends to Claude.ai (Opus + extended thinking by default) in the browser. Best for nuanced analysis, reasoning through complex problems.

**Commands:**
```bash
cc <prompt>              # Continue thread (Opus + extended thinking — default)
cc sonnet <prompt>       # Override to Sonnet (adds --model sonnet)
cc no-think <prompt>     # Disable extended thinking (faster)
```

**Model verification (zero-tolerance):** After model selection, the script checks the UI confirms the correct model before sending any prompt. Mismatch → exit code 1, nothing sent.

**Example:**
```bash
cc "Analyze the methodological weaknesses in this mouse study on senolytics"
cc sonnet "Quick check: is this calculation correct?"
```

---

### Claude Web + Research — `cc research`
**What it does:** Claude web with real-time web search enabled (Opus + extended thinking). Searches the live web AND reasons about it. Auto-saves response to `deus/research/`. Best of both worlds.

**Command:**
```bash
cc research <prompt>
```

**Example:**
```bash
cc research "What are the latest clinical trial results for dasatinib + quercetin?"
```

**When to use:** When you need live web data AND deep reasoning together.

**Deep research watchdog:** For `--web-search` (i.e., `cc research`), Claude creates a document/artifact as part of research — this is expected, NOT an error. After research completes, the script:
1. Tries to extract the report directly from the DOM
2. If short (<10,000 chars), tries clicking any download link
3. If still insufficient, sends a follow-up message asking Claude to paste the full report as chat text, then captures that response
Report is auto-saved to `deus/research/`.

---

## TIER 4 — Deep Research (10–30 min, comprehensive)

### Gemini Deep Research — `gg dr`
**What it does:** Gemini's full deep research mode. Visits 100+ websites, synthesizes into a comprehensive report. Takes 10–30 minutes.

**Commands:**
```bash
gg dr <prompt>           # Continue thread
gg dr new <prompt>       # Fresh thread
```

**Example:**
```bash
gg dr "Comprehensive review of senolytics mechanisms, clinical evidence, and safety profile as of 2025"
```

**Quota:** ≤10/day. Use when WebSearch + Bing are insufficient for complex multi-source questions.

---

### ChatGPT Deep Research — `test_chatgpt_deep_research.py`
**What it does:** ChatGPT's deep research mode. Alternative to Gemini DR.

**Command:**
```bash
python.exe "C:/Users/chris/PROJECTS/the-thinker/browser-automation/test_chatgpt_deep_research.py" --prompt "..."
```

**Quota:** ≤12/month. Save for critical gaps.

---

## TIER 5 — Multi-LLM Pipelines (the heavy artillery)

> **RULE: Never manually orchestrate multiple LLMs yourself.**
> Never call `cg`, `gg`, `cc` one by one, collect responses, and summarize them yourself. That is not facilitation — that is you doing the work that Ein exists to do, worse and slower. Use the right pipeline below.

### WHICH PIPELINE TO USE? <!-- drift-ignore: decision guide, not a tool -->

**Fundamental split:** do you want an **answer / decision** (Ein MDP) or a **document / design** (Ein Design)?

| I want to... | Use |
|---|---|
| Make a decision / answer "should we do X?" | **Ein MDP** |
| Risk assessment, ethical question, methodology debate | **Ein MDP** |
| Resolve "which of these options is best?" | **Ein MDP** |
| Audit / stress-test a plan or hypothesis | **Ein MDP** |
| Write a spec, policy doc, architecture document | **Ein Design** |
| Synthesize multiple papers / reports into one document | **Ein Design** |
| Draft a research protocol or roadmap | **Ein Design** |
| Program redesign (take an existing plan, produce a better one) | **Ein Design** |

#### How to recognise MDP-shaped vs Design-shaped prompts

**Use Ein MDP if the deliverable is a verdict, answer, or judgment call.** Prompt patterns:
- "Should we …?", "Is X safer/better than Y?", "Which …?", "How is X calculated?"
- "Evaluate / audit / assess …"
- "What's the right way to …?" (where "right" needs reasoning, not just exposition)
- "Does this plan hold up?" (stress-test)
- Risk/ethics framing: "What could go wrong with …?", "Is this responsible / compliant?"

MDP's value is **surfacing disagreement, attacking weak framing, forcing a non-hedged final verdict** (phase4 per-engine + phase5 2/3-majority synthesis by ChatGPT). Output is ~1-2 pages: verdict + reasoning + supporting evidence. Adversarial by design.

**Use Ein Design if the deliverable is a full document you'd show someone.** Prompt patterns:
- "Write a [spec / protocol / roadmap / policy / guide] for …"
- "Produce a master design document combining …"
- "Turn these sources into one unified document covering sections X, Y, Z"
- "Redesign our [program / architecture / workflow] …"
- Anything with an expected structure: "include sections on …", "cover the following dimensions …"

Ein Design's value is **convergent co-authoring** (three LLMs draft independently, then revise by reading each other's work across cross-pollination rounds, then one synthesises a final master doc via 2/3 majority). Output is 10-50+ pages with a concrete structure. Collaborative by design.

#### Borderline cases

- **"Should we do X, and if yes, give me the plan."** → Run **Ein MDP** first to get the Go/No-Go verdict + reasoning, then **Ein Design** on the Go side with the MDP verdict as the brief. Two passes, two deliverables. Don't try to squeeze both out of one pipeline — the hybrid prompt weakens both.
- **"Critique this plan AND produce a better one."** → Two-run strategy: Run 1 = Ein MDP adversarial critique (break the frame, verdict = Retain/Modify/Replace). Compact the output into a handoff artifact. Run 2 = Ein Design synthesis on the handoff artifact alone (not the original plan). See `tech-library/thinker/ein-mdp-two-run-strategy.md` for details. **Never feed the original plan into Run 2** — the narrative weight outweighs the critique.
- **"Compare these three options."** → If you want a ranked decision, Ein MDP. If you want a written comparison document (table, pros/cons, recommendation section), Ein Design.
- **"Research question with a definite answer" (e.g., "what is the population of Athens?")** → Ein MDP if the answer is contested or methodology-dependent. Plain `cc research` / `gg dr` if it's a factual lookup.

#### Prompt engineering tip

Before running either pipeline on a non-trivial brief, **consult ChatGPT Extended Thinking** (`cg` with thinking mode). Share the draft prompt and ask for critique on role specificity, task interference, constraint quality, anchoring bias. This catches brittle prompts before they burn an hour-long pipeline run. Full rationale: `memory/feedback_prompt_engineering_with_chatgpt.md`.

---

### Ein MDP — `the-thinker/ein/ein-mdp.py` + `/ein-mdp-loop` skill

**What it is:** The Mitso Decision Protocol. A 6-phase adversarial deliberation pipeline. ChatGPT, Gemini, and Claude state opening positions, attack each other with adversarial lenses, cross-examine twice, deliver final verdicts, and then ChatGPT alone synthesizes the three verdicts into one decisive answer via 2/3 majority. The right tool when you need a clear answer or decision.

Forked from the old `mralfrednemo-maker/ein-mdp` repo (now DEPRECATED) onto the proven `ein-design.py` chassis: preflight, pre-submit screenshots, browser_safety, profile suffix, WMI bypass, self-healing selectors, submit verification, heartbeat, session watchdog, staged-output inspector loop, `conversation_registry` resume, per-phase Chrome profiles at `chrome-automation-profile-ein-mdp-{1,2,3}`.

**6 phases:**
1. `phase1` — Opening positions (fresh chat per engine).
2. `phase1_5` — Contrarian critiques. Each engine attacks ONE peer with a fixed adversarial lens (ChatGPT → Claude / Opposite Conclusion; Claude → Gemini / Missing Stakeholder; Gemini → ChatGPT / Pre-Mortem).
3. `phase2` — Synthesis round with the full prior history uploaded as a context doc (fresh chat per engine). Answers 6 numbered questions.
4. `phase3` — Cross-examination R2 (SAME THREAD as phase2 — no new_chat, no select_model). Each engine sees both peers' phase2 responses inline, answers 4 questions.
5. `phase4` — Final per-engine verdicts (SAME THREAD). Each engine sees both peers' phase3 responses inline, answers 5 questions including explicit final verdict + top-3 closing positions.
6. `phase5` — **Facilitator synthesis** (ChatGPT only, SAME THREAD). Receives Gemini and Claude phase4 verdicts (ChatGPT's own is already in the thread), applies 2/3 majority on remaining disagreements, produces a decisive verdict + reasoning + supporting evidence. This is the deliverable.

Phase3/4/5 navigate back to the phase2 conversation URL stored in `ledger.conversation_registry.<engine>.phase2_url`; a wrong-thread post would pollute the live debate.

**Use when:** "Should we do X?", "Is this the right approach?", "Which option is best?", risk assessment, ethical questions, methodology debates.

**Preferred invocation — via the orchestrator skill (auto inspector + promote loop):**
```
/ein-mdp-loop <brief-file>
```
Drives phase-by-phase, runs an inspector sub-agent between phases, promotes staged output to the ledger, halts to Telegram on unrecoverable failures. Sibling skills: `/ein-mdp-status <ledger>` (dashboard), `/ein-mdp-resume <ledger>` (manual recovery).

**Direct invocation (one phase at a time):**
```bash
cd C:\Users\chris\PROJECTS\the-thinker\ein

# phase1 creates a new ledger
python ein-mdp.py --phase phase1 --prompt "C:/Users/chris/PROJECTS/briefs/my-brief.txt" \
  --profile-suffix mdp --preset deep --kill-stale

# subsequent phases --resume the ledger
python ein-mdp.py --phase phase1_5 --resume "C:/Users/chris/PROJECTS/mdp-ledger-<ts>.json" --profile-suffix mdp --preset deep
python ein-mdp.py --phase phase2   --resume "C:/Users/chris/PROJECTS/mdp-ledger-<ts>.json" --profile-suffix mdp --preset deep
python ein-mdp.py --phase phase3   --resume "C:/Users/chris/PROJECTS/mdp-ledger-<ts>.json" --profile-suffix mdp --preset deep
python ein-mdp.py --phase phase4   --resume "C:/Users/chris/PROJECTS/mdp-ledger-<ts>.json" --profile-suffix mdp --preset deep
python ein-mdp.py --phase phase5   --resume "C:/Users/chris/PROJECTS/mdp-ledger-<ts>.json" --profile-suffix mdp --preset deep
```

The skill handles the `--phase` sequencing + inspector loop for you; direct invocation is for debug / single-phase reruns.

**Key arguments:**
| Argument | Default | Purpose |
|---|---|---|
| `--phase` | required | One of `phase1`, `phase1_5`, `phase2`, `phase3`, `phase4`, `phase5` |
| `--prompt` | required for phase1 | Path to brief file. Stored in the ledger; later phases read from ledger |
| `--resume` | required for all non-phase1 | Path to the ledger JSON |
| `--preset` | `deep` | `fast` (instant/Fast/Sonnet 4.6), `standard` (latest/Pro/Opus), `deep` (thinking-heavy/Pro/Sonnet 4.6+extended-thinking) |
| `--model-chatgpt` / `--model-gemini` / `--model-claude` | preset | Override preset's per-engine choice |
| `--no-extended-thinking` | off | Disable Claude extended thinking even if preset enables it |
| `--only` | all | Restrict to specific engines (testing only; phase3/4 must be all 3; phase5 must be chatgpt only) |
| `--profile-suffix` | `mdp` | Chrome profile suffix — `chrome-automation-profile-ein-mdp-{1,2,3}` |
| `--kill-stale` | off on phase1, on for --resume | Kill orphaned automation Chrome before launching |
| `--no-rate-limit` | off | Bypass browser_safety rate limiting (only when Christo authorizes a run) |

**Preset notes:**
- `deep` currently uses `chatgpt=thinking-heavy` and `gemini=Pro` (not Thinking) because the shared `ein_preflight.py` only recognises the `Pro` chip label. Thinking-as-Pro-subset is deferred. Claude still gets `extended_thinking=True` on deep, using Sonnet 4.6.

**Examples:**
```bash
# Full pipeline via the skill (recommended)
/ein-mdp-loop C:/Users/chris/PROJECTS/briefs/partial-vs-full-reprogramming.txt

# Fast smoke test — direct, one engine, phase1 only
python ein-mdp.py --phase phase1 --prompt brief.txt --profile-suffix mdp --preset fast --only chatgpt
```

**Monitor:** The script logs `[ein-m] HH:MM:SS` per-phase progress + heartbeat (engine response size every 20s). Per-phase screenshots in `C:\Users\chris\PROJECTS\downloaded_files\`. Ledger at `C:\Users\chris\PROJECTS\mdp-ledger-<ts>.json`, staged outputs at `<ledger-stem>-staged-<phase>.json`, inspector verdict audit at `<ledger-stem>-verdicts.jsonl`.

**Rate limits:** Registered in `browser_safety.py` as `ein_mdp` — 3 calls/hour, 10/day, 300s cooldown. Matches `ein_design`.

**Location:** `C:\Users\chris\PROJECTS\the-thinker\ein\ein-mdp.py` (the old `C:\Users\chris\PROJECTS\ein-mdp\` was archived to `ein-mdp-STALE/` on 2026-04-15 and is DEPRECATED).

---

### Ein Selenium — `ein-selenium.py`

**Legacy/specialized only:** do not use this for ordinary ChatGPT consultation, ChatGPT Heavy, GECL authority reviews, orchestration/audit troubleshooting, file-upload consults, or "continue the ChatGPT discussion" requests. Those use persistent Chrome CDP (`start-chatgpt-persistent-cdp.ps1` + `chatgpt_persistent_cdp_client.py`) with the active run profile and port.

**What it is:** The adversarial deliberation engine. Drives ChatGPT, Gemini, and Claude browsers directly via Selenium (no bridge processes needed). Each engine gets a contrarian lens and cross-examines the others. Best for truth-seeking and stress-testing hypotheses.

**Difference from Ein MDP:** Ein Selenium is the underlying browser driver. Ein MDP wraps it with preflight checks, heartbeat monitoring, automatic retry logic, and a structured 5-phase protocol. For most deliberations, prefer Ein MDP. Use Ein Selenium directly only when the operator explicitly asks for that legacy engine and fine-grained phase control.

**Command:**
```bash
cd C:\Users\chris\PROJECTS\the-thinker\ein

# Full deliberation, all engines, all phases
python ein-selenium.py --phase all

# Single phase
python ein-selenium.py --phase 1

# Test with one engine
python ein-selenium.py --phase 1 --only gemini
```

**Key arguments:**
| Argument | Default | Purpose |
|---|---|---|
| `--phase` | `all` | `1`, `1.5`, `2`, `3`, `4`, or `all` |
| `--only` | all | Restrict to specific engines: `chatgpt,gemini,claude` |
| `--model-chatgpt` | `thinking-heavy` | ChatGPT model |
| `--model-gemini` | `Pro` | Gemini model |
| `--model-claude` | `Opus` | Claude model |
| `--no-extended-thinking` | off | Disable Claude extended thinking |
| `--kill-stale` | off | Kill orphaned Chrome processes |
| `--skip-check` | off | Skip brief suitability check |

**Location:** `C:\Users\chris\PROJECTS\the-thinker\ein\`

---

### Ein Design — `ein-design.py`

> **⚠ Canonical location — DO NOT use any copy elsewhere:**
> `C:\Users\chris\PROJECTS\the-thinker\ein\ein-design.py`
>
> Any copy at `C:\Users\chris\PROJECTS\ein-design.py` (root), or in any other directory, is **stale** — delete it, don't run it. A stale root-level copy was purged on 2026-04-15. The same rule applies to `ein-mdp.py` and `ein-selenium.py` — always run from `the-thinker/ein/`.

**What it is:** A collaborative document synthesis pipeline. Three LLMs independently draft a document from the same brief, then iteratively revise by reading each other's work across multiple cross-pollination rounds. Converges to a single unified document via 2/3 majority.

**Preflight requirement:** Every send path must run `the-thinker/ein/ein_preflight.py` / `PreflightGate` before clicking Submit. The gate verifies model, prompt landing, exact attachment count, attachment-contract wording, blocking errors, enabled send button, screenshot, and JSON report. Do not trust a visible file chip alone. ChatGPT requires clicking `composer-plus-btn` before using the non-image `input[type=file]`; Gemini currently requires the native Windows file picker after `data-test-id="local-images-files-uploader-button"`; Claude should click `Add files, connectors, and more` before revealing `input[data-testid="file-upload"]`. Dry-run check:

The strict provider DOM baseline lives in `the-thinker/ein/ein_preflight_baseline.json`. If any mapped selector, model label, button label, host, attachment chip, or send-button parameter changes, treat it as provider drift and start a troubleshooting session before using Ein Design again.

```bash
python the-thinker/ein/ein_preflight.py chatgpt --dry-run
python the-thinker/ein/ein_preflight.py gemini --dry-run
python the-thinker/ein/ein_preflight.py claude --dry-run
```

**Use when:** Writing specs, policy drafts, research synthesis, architecture decisions, merging sources into one document — any task where you want 3 LLMs to co-write and converge.

**Pipeline (5 phases):**
```
draft → cross_1 → cross_2 → cross_3 → final
```
1. **Draft** — 3 LLMs write independently from the same brief + uploaded sources
2. **Cross_1** — each reads the other two's drafts and produces a revised complete doc + rejection appendix
3. **Cross_2** — same, one more round of convergence
4. **Cross_3** — final convergence pass; positions typically stabilise here
5. **Final** — ChatGPT alone synthesises, resolves remaining disagreements by 2/3 support, writes the master doc

**One phase per invocation.** As of 2026-04-15 the script runs **exactly one phase per call** — this is the contract the orchestrator relies on. `--phase <name>` is now effectively required for any run past draft.

---

#### Recommended: unattended autonomous run — `/ein-design-loop`

**This is the default way to run Ein Design.** A Claude Code skill orchestrates the pipeline end-to-end: fires each phase, dispatches an inspector sub-agent between phases to read screenshots + staged output, auto-retries on fixable failures (up to 4 attempts/phase), halts to Telegram on unrecoverable errors.

```
/ein-design-loop <brief-file>                 # fresh run
/ein-design-loop <ledger-path>                # resume an in-progress ledger
/ein-design-loop                              # auto-resume most recent ledger
```

**Companion skills:**
- `/ein-design-status [ledger-path]` — dashboard: phases done, staged files awaiting inspection, recent verdicts, attempt counters
- `/ein-design-resume <ledger-path>` — manual recovery after a halt

**Artefacts per run** (all in `C:\Users\chris\PROJECTS\`):
- `design-ledger-<TS>.json` — canonical ledger, one entry per promoted phase
- `design-ledger-<TS>-staged-<phase>.json` — held pending inspector verdict; deleted after promotion
- `design-ledger-<TS>-verdicts.jsonl` — audit trail of inspector decisions
- `design-ledger-<TS>-FINAL-MASTER.md` — the master document (written after `final` promotes)
- `ein_d_<engine>_<phase>_*.png` — screenshots the inspector reads

**Rate limit** (`browser_safety.py`): 3/hour, 10/day. A 5-phase run always trips the hourly cap once; the orchestrator retries attempt 2 with `--no-rate-limit` automatically. Don't pass `--no-rate-limit` manually on attempt 1.

**Chrome profile isolation:** ein-design uses `chrome-automation-profile-ein-design-1/2/3` via `--profile-suffix design` so it never collides with ein-mdp (`-mdp-1/2/3`). Both can run on the same machine — not at the same time.

---

#### Direct invocation — for debugging or surgical re-runs only

```bash
cd C:\Users\chris\PROJECTS\the-thinker\ein

# Start a fresh run — first phase only
python ein-design.py --phase draft \
  --prompt C:\path\to\brief.txt \
  --upload-files "file1.md,file2.md" \
  --profile-suffix design

# Continue phases one at a time, feeding the ledger written by draft
python ein-design.py --phase cross_1 --resume C:\Users\chris\PROJECTS\design-ledger-YYYYMMDD-HHMMSS.json --profile-suffix design
python ein-design.py --phase cross_2 --resume ... --profile-suffix design
python ein-design.py --phase cross_3 --resume ... --profile-suffix design
python ein-design.py --phase final   --resume ... --profile-suffix design

# Rate-limit bypass (ONLY on a retry after a failed attempt)
python ein-design.py --phase cross_3 --resume ... --no-rate-limit --profile-suffix design
```

**When to go direct instead of `/ein-design-loop`:**
- Re-running a single failed phase after you've already inspected the screenshots yourself
- Testing a selector fix (`--phase draft --only <engine>`)
- Debugging the ledger structure without inspector interference

For real production runs, always use the skill — unattended operation, inspector gating, and Telegram halts are non-negotiable safety nets.

---

**Key arguments:**
| Argument | Default | Purpose |
|---|---|---|
| `--phase` | — | Which phase to run: `draft`, `cross_1`, `cross_2`, `cross_3`, `final` (one per call) |
| `--prompt` | — | Path to the brief/prompt file (required for `draft`) |
| `--resume` | — | Ledger JSON — required for any phase past draft |
| `--upload-files` | — | Comma-separated source files to upload (draft only) |
| `--profile-suffix` | `design` | Chrome profile pool suffix; keep `design` unless isolating a parallel run |
| `--only <engine>` | — | Run only one of `chatgpt \| gemini \| claude` (debugging) |
| `--kill-stale` | off | Kill orphaned Chrome processes in the matched profile pool |
| `--no-rate-limit` | off | Bypass browser_safety caps (retries only — orchestrator handles this) |
| `--skip-check` | off | Skip brief suitability validation |

**Mid-submit inspector gates:** while a phase runs, the script drops gate files into `<ledger_dir>/_gates/` at submit / streaming / completion checkpoints. The orchestrator polls these and can tell the script to `continue`, `refresh`, or `abort` per engine mid-flight (e.g., wedged spinner → refresh tab). Direct-invocation runs skip this — the script defaults all gates to `continue`.

**Proven stable:** two clean end-to-end runs on 2026-04-15 (Mobile 3D Capture + Android 3D Capture adjudication), all five phases promoted first-pass, inspector gating held, rate-limit retry handled transparently.

**Location:** `C:\Users\chris\PROJECTS\the-thinker\ein\`
**Skill source:** `C:\Users\chris\.claude\skills\ein-design-loop\`

---

## TIER 6 — Implementation

### Codex — `cx`
**What it does:** Sends implementation task to GPT-5.4 via the Codex CLI. Writes code, builds features. Continues same thread by default.

**Commands:**
```bash
cx <task>            # Continue thread, write code
cx new <task>        # Fresh thread (different task)
cx ro <task>         # Read-only investigation (no writes)
cx bg <task>         # Background, non-blocking
cx spark <task>      # Lighter model, faster tasks
```

**Examples:**
```bash
cx "Add error handling to the mitso-search.py Sonar function"
cx new "Build a PubMed batch fetcher that takes a list of PMIDs"
cx ro "Investigate why the Bing scraper is returning empty results"
```

**Rule:** `cx` always writes. Use `cx ro` for investigation only.

---

## TIER 7 — Subagents (background, parallel work)

### Context Compiler
**What it does:** Reads all relevant files and assembles a complete context brief before executing a complex task. Does NOT do the task itself — only gathers and validates context. Critical before sending prompts to other AIs.

**How:** `Agent tool, subagent_type: context-compiler`

**Example use:** Before starting a `gg dr` deep research session, run context compiler to pull all existing knowledge on the topic so the brief includes what we already know.

---

### General-Purpose Agent
**What it does:** Multi-step research, web search loops, complex background investigations. Runs independently and reports back.

**How:** `Agent tool` (default)

**Example:** "Research all clinical trials involving rapamycin in humans published after 2023 and summarize their outcomes."

---

### Explore Agent
**What it does:** Fast codebase and document exploration. Finds files by pattern, searches code for keywords, answers structural questions.

**How:** `Agent tool, subagent_type: Explore`

---

## TIER 8 — Storage & Memory

### QMD Indexing <!-- drift-ignore: operation, not a tool -->
**What it does:** After saving any file, re-indexes the relevant collection so the content becomes searchable via `qmd vsearch`.

**Commands:**
```bash
# After saving to deus/
qmd update deus && qmd embed deus

# After saving to shared/
qmd update shared && qmd embed shared

# Update all collections at once
qmd update && qmd embed
```

**Rule (Memento):** Every significant finding gets saved to a file AND indexed in QMD. If it's not in QMD, it doesn't exist for future sessions.

---

### File Storage Locations <!-- drift-ignore: reference table, not a tool -->
| What | Where |
|------|-------|
| Deus research findings | `C:\Users\chris\PROJECTS\deus\research\` |
| Mitso memory | `C:\Users\chris\PROJECTS\mitso\memories\` |
| Shared tools/resources | `C:\Users\chris\PROJECTS\shared\` |
| Tech library | `C:\Users\chris\PROJECTS\tech-library\` |
| LightRAG backup | localhost:9621 (optional legacy backup; `/techlib` is QMD-backed) |

**Tagging rule for Deus:** Every file saved starts with `[DEUS][IMMORTALITY]` on line one.

---

## AGENT MESSAGING

### Send a message to another agent <!-- drift-ignore: operation, not a distinct tool -->
```bash
/msg deus <message>     # From Mitso or Claude to Deus
/msg mitso <message>    # From Deus or Claude to Mitso
/msg claude <message>   # From Deus or Mitso to Claude Code (vanilla)
```

Messages are delivered automatically on the recipient's next prompt via the hook. No user intervention needed.

---

## PLANNED / TO BUILD
- [ ] PubMed batch fetcher — auto-pull abstract+metadata for a list of PMIDs
- [ ] Trial tracker — scrape ClinicalTrials.gov for longevity interventions, parse phase/status
- [ ] Paper summarizer — fetch full paper → compress to Deus-format briefing → auto-index in QMD
- [ ] Research gap detector — query QMD, identify known vs unknown, output gap list
