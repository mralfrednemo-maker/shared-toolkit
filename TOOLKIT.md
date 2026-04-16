# Shared Toolkit — Mitso, Deus, Gemini, Codex & Claude Code
**Location:** `C:\Users\chris\PROJECTS\shared\TOOLKIT.md` — canonical, single source of truth
**Last updated:** 2026-04-14
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

### Headless / Headful Browser — `mitso/browser-automation/`
**What it does:** Persistent Playwright Chromium profile for accessing authenticated services (Gmail, Telnyx, dashboards) headlessly. Login once, reuse session forever. No browser visible during automated runs. **Windows-native — runs in Claude Code (Mitso's environment), not in WSL/OpenClaw.**

**Location:** `C:\Users\chris\PROJECTS\mitso\browser-automation\`

#### What's Already Authenticated (as of 2026-04-15):
- Gmail: `mr.alfred.nemo@gmail.com` — use `gmail-search.js`
- Telnyx: `portal.telnyx.com` — use `telnyx-check.js`

**Profile dir:** `C:\Users\chris\PROJECTS\mitso\browser-automation\profile\` — cookies persist here. Never delete.

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

## TIER 3 — AI Conversations (minutes, back-and-forth)

### ChatGPT — `cg`
**What it does:** Sends prompt to ChatGPT in the browser, continues same thread. Returns response. Best for debate, idea testing, pushback, synthesis.

**Commands:**
```bash
cg <prompt>              # Continue current thread
cg new <prompt>          # Start fresh thread (new topic only)
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

### WHICH PIPELINE TO USE?

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
| `--preset` | `deep` | `fast` (instant/Fast/Sonnet), `standard` (latest/Pro/Opus), `deep` (thinking/Pro/Opus+extended-thinking) |
| `--model-chatgpt` / `--model-gemini` / `--model-claude` | preset | Override preset's per-engine choice |
| `--no-extended-thinking` | off | Disable Claude extended thinking even if preset enables it |
| `--only` | all | Restrict to specific engines (testing only; phase3/4 must be all 3; phase5 must be chatgpt only) |
| `--profile-suffix` | `mdp` | Chrome profile suffix — `chrome-automation-profile-ein-mdp-{1,2,3}` |
| `--kill-stale` | off on phase1, on for --resume | Kill orphaned automation Chrome before launching |
| `--no-rate-limit` | off | Bypass browser_safety rate limiting (only when Christo authorizes a run) |

**Preset notes:**
- `deep` currently uses `gemini=Pro` (not Thinking) because the shared `ein_preflight.py` only recognises the `Pro` chip label. Thinking-as-Pro-subset is deferred. Claude still gets `extended_thinking=True` on deep.

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

**What it is:** The adversarial deliberation engine. Drives ChatGPT, Gemini, and Claude browsers directly via Selenium (no bridge processes needed). Each engine gets a contrarian lens and cross-examines the others. Best for truth-seeking and stress-testing hypotheses.

**Difference from Ein MDP:** Ein Selenium is the underlying browser driver. Ein MDP wraps it with preflight checks, heartbeat monitoring, automatic retry logic, and a structured 5-phase protocol. For most deliberations, prefer Ein MDP. Use Ein Selenium directly when you want fine-grained phase control.

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
| `--model-chatgpt` | `thinking` | ChatGPT model |
| `--model-gemini` | `Pro` | Gemini model |
| `--model-claude` | `Opus` | Claude model |
| `--no-extended-thinking` | off | Disable Claude extended thinking |
| `--kill-stale` | off | Kill orphaned Chrome processes |
| `--skip-check` | off | Skip brief suitability check |

**Location:** `C:\Users\chris\PROJECTS\the-thinker\ein\`

---

### Ein Design — `ein-design.py`

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

### QMD Indexing
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

### File Storage Locations
| What | Where |
|------|-------|
| Deus research findings | `C:\Users\chris\PROJECTS\deus\research\` |
| Mitso memory | `C:\Users\chris\PROJECTS\mitso\memories\` |
| Shared tools/resources | `C:\Users\chris\PROJECTS\shared\` |
| Tech library | `C:\Users\chris\PROJECTS\tech-library\` |
| LightRAG backup | localhost:9621 (via /techlib skill) |

**Tagging rule for Deus:** Every file saved starts with `[DEUS][IMMORTALITY]` on line one.

---

## AGENT MESSAGING

### Send a message to another agent
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
