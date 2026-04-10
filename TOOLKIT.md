# Shared Toolkit — Mitso, Deus & Claude Code
**Location:** `C:\Users\chris\PROJECTS\shared\TOOLKIT.md` — canonical, single source of truth
**Last updated:** 2026-04-09
**Maintained by:** ALL agents (Mitso, Deus, Claude Code). Any agent that discovers or adds a new tool updates this file immediately, then runs `qmd update shared && qmd embed shared`.

---

## DECISION GUIDE — Which Tool to Use?

```
Question or research task?
├── Already have context? → QMD first (qmd vsearch)
├── Need current web data? → WebSearch → Bing → Sonar (escalate as needed)
├── Need a second opinion / debate? → kk (ChatGPT) or jj (Gemini)
├── Need deep comprehensive research? → jj dr OR cc research
├── Need 3 LLMs to reach a decision together? → Ein Deliberation (**NOT manual kk+jj+cc**)
├── Need 3 LLMs to co-write a document/spec? → Ein Design (**NOT manual kk+jj+cc**)
└── Need to implement code? → cx (Codex)
```

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

## TIER 3 — AI Conversations (minutes, back-and-forth)

### ChatGPT — `kk`
**What it does:** Sends prompt to ChatGPT in the browser, continues same thread. Returns response. Best for debate, idea testing, pushback, synthesis.

**Commands:**
```bash
kk <prompt>              # Continue current thread
kk new <prompt>          # Start fresh thread (new topic only)
```

**Examples:**
```bash
kk "What are the strongest objections to partial epigenetic reprogramming?"
kk new "Completely different topic: explain the Hayflick limit"
```

**Rules:**
- NEVER use `kk new` mid-topic — kills all context
- Always push back on ChatGPT's answers — don't just accept them
- Good for adversarial review and stress-testing ideas

---

### Gemini — `jj`
**What it does:** Sends prompt to Gemini Pro in the browser, continues same thread. Good for second opinions, cross-checking, and broad synthesis.

**Commands:**
```bash
jj <prompt>              # Continue current thread
jj new <prompt>          # Start fresh thread
```

**Examples:**
```bash
jj "Cross-check: is this interpretation of the Yang 2023 paper correct?"
jj new "New topic: what are the latest findings on NAD+ and aging?"
```

**Rule:** Same thread continues automatically. Fresh thread only for genuinely unrelated topics.

---

### Claude Web Sonnet — `cc`
**What it does:** Sends to Claude.ai (Sonnet + extended thinking) in the browser. Best for nuanced analysis, reasoning through complex problems.

**Commands:**
```bash
cc <prompt>              # Continue thread (Sonnet + extended thinking)
cc opus <prompt>         # Use Opus model (maximum reasoning)
cc no-think <prompt>     # Disable extended thinking (faster)
```

**Example:**
```bash
cc "Analyze the methodological weaknesses in this mouse study on senolytics"
cc opus "Design a research protocol for testing X in humans"
```

---

### Claude Web + Research — `cc research`
**What it does:** Claude web with real-time web search enabled. Searches the live web AND reasons about it with extended thinking. Auto-saves response to `deus/research/`. Best of both worlds.

**Command:**
```bash
cc research <prompt>
```

**Example:**
```bash
cc research "What are the latest clinical trial results for dasatinib + quercetin?"
```

**When to use:** When you need live web data AND deep reasoning together.

---

## TIER 4 — Deep Research (10–30 min, comprehensive)

### Gemini Deep Research — `jj dr`
**What it does:** Gemini's full deep research mode. Visits 100+ websites, synthesizes into a comprehensive report. Takes 10–30 minutes.

**Commands:**
```bash
jj dr <prompt>           # Continue thread
jj dr new <prompt>       # Fresh thread
```

**Example:**
```bash
jj dr "Comprehensive review of senolytics mechanisms, clinical evidence, and safety profile as of 2025"
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
> Never call `kk`, `jj`, `cc` one by one, collect responses, and summarize them yourself. That is not facilitation — that is you doing the work that Ein exists to do, worse and slower. Use the right pipeline below.

### WHICH PIPELINE TO USE?

| I want to... | Use |
|---|---|
| Make a decision / answer "should we do X?" | **Ein MDP** |
| Stress-test a hypothesis / adversarial review | **Ein Selenium** |
| Write a spec, policy doc, or research synthesis | **Ein Design** |
| Synthesize multiple papers into one document | **Ein Design** |
| Draft a research protocol | **Ein Design** |
| Risk assessment, ethical question | **Ein MDP** |

---

### Ein MDP — `ein-mdp/watchdog.py`

**What it is:** The Mitso Decision Protocol. A 5-phase adversarial deliberation pipeline. ChatGPT, Gemini, and Claude argue, challenge each other, cross-examine, and reach a verdict. The right tool when you need a clear answer or decision.

**5 phases:**
1. Opening positions — each LLM states its view independently
2. Contrarian challenges — each attacks the others' positions
3. Cross-examination R1 — rebuttals
4. Cross-examination R2 — final positions
5. Final verdicts — synthesized conclusion

**Use when:** "Should we do X?", "Is this the right approach?", "Which option is best?", risk assessment, ethical questions.

**Command:**
```bash
cd C:\Users\chris\PROJECTS

# Minimal — question only
python ein-mdp/watchdog.py --question "YOUR QUESTION" --preset deep

# With a detailed brief file
python ein-mdp/watchdog.py --question "YOUR QUESTION" --brief path/to/brief.txt --preset deep
```

**Key arguments:**
| Argument | Default | Purpose |
|---|---|---|
| `--question` | required | The deliberation question |
| `--brief` | optional | Path to detailed brief file. If omitted, `--question` is used as the full prompt |
| `--preset` | `deep` | `fast` (quick models), `standard`, `deep` (thinking models — best quality) |
| `--only` | all | Restrict to specific engines: `chatgpt`, `gemini`, `claude` |
| `--kill-stale` | off | Kill orphaned Chrome processes before starting |

**Presets:**
- `--preset fast` — lighter models. Use for quick takes or testing.
- `--preset standard` — balanced models.
- `--preset deep` — thinking models (R1, Reasoner). Default. Use for anything important.

**Examples:**
```bash
# Simple question, no brief
python ein-mdp/watchdog.py \
  --question "Is partial reprogramming safer than full reprogramming for in vivo use?" \
  --preset deep

# With a detailed brief
python ein-mdp/watchdog.py \
  --question "Should we prioritize senolytics over epigenetic reprogramming in Phase 2?" \
  --brief C:\Users\chris\PROJECTS\deus\research\phase2-brief.txt \
  --preset deep

# Quick smoke test — one engine only
python ein-mdp/watchdog.py \
  --question "What is the population of Athens?" \
  --preset fast --only gemini
```

**Monitor:** While running, check `_mdp_status.txt` for current phase and response sizes (updated every 60s).

**Location:** `C:\Users\chris\PROJECTS\ein-mdp\`

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

**Use when:** Writing specs, policy drafts, research synthesis, architecture decisions, merging sources into one document — any task where you want 3 LLMs to co-write and converge.

**Pipeline:**
```
draft → cross_1 → cross_2 → [cross_3] → [cross_4] → final
```
1. **Draft** — 3 LLMs write independently from the same brief
2. **Cross_1** — each reads the other two's drafts and revises
3. **Cross_2** — same with cross_1 outputs
4. **Cross_3 / Cross_4** — only if significant divergence remains (cross_4 = forced concession)
5. **Final** — ChatGPT synthesizes with 2/3 majority on remaining disagreements

**Command:**
```bash
cd C:\Users\chris\PROJECTS\the-thinker\ein

# Phase 1: Draft (all 3 engines write independently)
python ein-design.py \
  --phase draft \
  --prompt C:\path\to\brief.txt \
  --upload-files "file1.md,file2.md"

# Subsequent phases: resume from ledger
python ein-design.py --phase cross_1 --resume C:\Users\chris\PROJECTS\design-ledger-YYYYMMDD-HHMMSS.json
python ein-design.py --phase cross_2 --resume <ledger>
python ein-design.py --phase final   --resume <ledger>
```

**Key arguments:**
| Argument | Default | Purpose |
|---|---|---|
| `--phase` | required | `draft`, `cross_1`, `cross_2`, `cross_3`, `cross_4`, `final` |
| `--prompt` | `phase1-v5-prompt.txt` | Path to the brief/prompt file |
| `--resume` | — | Ledger JSON from a previous phase (required for cross/final phases) |
| `--upload-files` | — | Comma-separated source files to upload to each engine |
| `--quality-criterion` | "more thorough, better reasoned, and more actionable" | What "stronger" means during cross-pollination |
| `--kill-stale` | off | Kill orphaned Chrome processes |
| `--skip-check` | off | Skip brief suitability validation |

**Examples:**
```bash
# Synthesize 3 research papers into one summary
python ein-design.py \
  --phase draft \
  --prompt deus/research/synthesis-brief.txt \
  --upload-files "deus/research/paper1.md,deus/research/paper2.md,deus/research/paper3.md"

# Continue from where you left off
python ein-design.py --phase cross_1 --resume design-ledger-20260409-143022.json

# Test with one engine
python ein-design.py --phase draft --prompt brief.txt --only chatgpt
```

**When to stop cross-pollination:**
- After cross_2: if all topics have 2/3 majority → go to `final`
- If 2+ topics still split → run `cross_3`
- If cross_3 still has splits → run `cross_4` (forced concession)

**Location:** `C:\Users\chris\PROJECTS\the-thinker\ein\`

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

**Example use:** Before starting a `jj dr` deep research session, run context compiler to pull all existing knowledge on the topic so the brief includes what we already know.

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
