# User Preferences & Global Instructions

## Environment
- OS: Windows 11 Pro
- Shell: WSL Ubuntu (default WSL distro)
- Docker runs inside WSL Ubuntu
- Working directory: C:\Users\chris\PROJECTS

## Communication Style
- Keep responses concise and direct
- No emojis unless requested
- Use tables for structured data where helpful
- At the end of each response, proactively suggest 0-3 logical next actions the user might want to take

## Hard Rules
- **NEVER say "no" or "we don't have" without searching first.** When asked "do we have X?", "is there a Y?", "where is Z?" — ALWAYS glob/grep the project tree before answering. Search broadly (parent dirs, sibling dirs, not just the current working dir). Only say "no" after a search returns zero results.
- **Brain, Chamber, and Thinker have NO time/token budgets.** All components of the deliberation platform get generous timeouts and max_tokens. Thinking models (R1, Reasoner) get 30k tokens and 720s. Non-thinking models get 8k-16k. If anything fails, the entire pipeline must ERROR and stop. No degraded mode, no partial results, no budget enforcement, no graceful degradation. Don't touch timeouts or max_tokens unless explicitly asked.
- **Spec compliance verification is mandatory.** Before declaring ANY multi-step implementation complete, you MUST:
  1. Run a spec-vs-code gap analysis (read each spec requirement, verify the code implements it end-to-end — not just that a file exists)
  2. Scan for dead code signals (imported but never called, types defined but never instantiated, TODO comments, hardcoded empty values where real data should flow)
  3. Verify replacements actually replace (if spec says "X replaces Y", confirm Y is REMOVED, not that X was added alongside Y)
  4. Never delegate orchestrator/integration wiring to agents with summarized prompts — the entity writing the integration must hold the full spec
  Passing tests and successful runs are NOT verification. They prove parts work in isolation. They do not prove the system matches the spec. See [full playbook](../projects/C--Users-chris-PROJECTS/memory/feedback_implementation_verification_playbook.md).

## Unified Memory (LightRAG)
- LightRAG Docker service at `http://localhost:9621` — vector + knowledge graph, replaces both tech-library and mitso-memory
- **When the user says "check the tech library", "search the library", "have we seen this before", or any memory/knowledge search** → use the `lightrag-query` skill
- **When troubleshooting infrastructure issues** → proactively use `lightrag-query` to search for past solutions before proposing fixes
- **After resolving significant issues** → use the `lightrag-upload` skill to save the solution
- **After saving a file to `tech-library/`** → also use `lightrag-upload` to index it into the graph
- Skills: `lightrag-query`, `lightrag-upload`, `lightrag-status`, `lightrag-explore`, `lightrag-save-session`
- Web UI: `http://localhost:9621` | Swagger: `http://localhost:9621/docs`
- **Recovery** (LightRAG unreachable): `cd C:\Users\chris\PROJECTS\LightRAG && wsl docker compose up -d`
- **CRITICAL**: Never change `EMBEDDING_MODEL` in `.env` after indexing — requires full re-index. LLM model (`LLM_MODEL`) can be changed freely.
- Data backup: zip `C:\Users\chris\PROJECTS\LightRAG\data\rag_storage\` to Google Drive

## Shortcuts
- When a message starts with `kk `, run the ChatGPT browser automation script via Bash: `python.exe "C:/Users/chris/PROJECTS/the-thinker/browser-automation/test_chatgpt_upload.py" --prompt "<everything after kk>"`. Do NOT rephrase or expand the prompt — pass it verbatim. Return the script's stdout directly without additional commentary. Thread continues automatically (same conversation URL reused between calls).
- `kk new <prompt>` — start a fresh ChatGPT thread: add `--new` flag to the script call.
- If the `kk` message contains a file path, pass it via `--file "<path>"` instead of inlining the content.
- When a message starts with `jj `, run the Gemini browser automation script via Bash: `python.exe "C:/Users/chris/PROJECTS/the-thinker/browser-automation/test_gemini_upload.py" --prompt "<everything after jj>"`. Same rules — verbatim prompt, no rephrasing. Return stdout directly. Thread continues automatically (same conversation URL reused between calls).
- `jj new <prompt>` — start a fresh Gemini thread: add `--new` flag to the script call.
- If the `jj` message contains a file path, pass it via `--file "<path>"` the same way.
- `jj dr <prompt>` — run Gemini **Deep Research** (Pro model, full web research report, ~10-30min): `python.exe "C:/Users/chris/PROJECTS/the-thinker/browser-automation/test_gemini_deep_research.py" --prompt "<everything after jj dr>" --timeout 1800`. Returns the full research report. Use `jj dr new <prompt>` to start a fresh deep research thread.
- When a message starts with `cc `, run the Claude web automation script via Bash: `python.exe "C:/Users/chris/PROJECTS/the-thinker/browser-automation/test_claude_research.py" --prompt "<everything after cc>"`. Returns Claude's response. Thread continues automatically.
- `cc new <prompt>` — start a fresh Claude web thread: add `--new` flag.
- `cc opus <prompt>` — use Opus model: add `--model opus`.
- `cc sonnet <prompt>` — use Sonnet + extended thinking (default).
- `cc no-think <prompt>` — disable extended thinking: add `--no-thinking`.
- `cc research <prompt>` — Claude with **web search enabled** (+ → Research → Web search) + extended thinking + auto-save response: add `--web-search --new`. Timeout auto-extends to 15min. Response saved to `deus/research/` automatically.
- When a message starts with `cx `, run `node "C:/Users/chris/.claude/plugins/marketplaces/openai-codex/plugins/codex/scripts/codex-companion.mjs" task --model gpt-5.4 --write "<task>"` directly via Bash (not through the subagent). Always include `--write` — Codex is used for implementation. Do NOT add `--fresh` — continue existing thread by default. Return Codex's output verbatim without additional commentary.
- `cx new <task>` — force a fresh Codex thread (adds `--fresh`).
- `cx ro <task>` — read-only investigation, no writes (omits `--write`).
- `cx bg <task>` — same as `cx` but with `--background` (non-blocking, notifies when done).
- `cx spark <task>` — use `--model spark` instead of gpt-5.4 (faster, lighter tasks).

## OpenClaw Agents
- You can talk directly to OpenClaw agents inside the Docker container using:
  ```
  wsl docker exec openclaw-stack-openclaw-gateway-1 node openclaw.mjs agent --agent <id> --message "<msg>" --json --timeout 300
  ```
- Agent IDs: `main` (Alfred), `turing`, `daedalus`, `hermes`, `themis`, `ikarus`, `inspector`, `prism`, `descartes`, `socrates`, `athena`
- Response is in `result.payloads[0].text` of the JSON output
- Use `--session-id <id>` to continue an existing conversation (session ID is in `result.meta.agentMeta.sessionId`)
- When the user asks you to discuss something with an agent, collaborate with an agent, or get an agent's opinion — call them directly and relay the response
- You can have multi-turn conversations: call the agent, read the response, call again with the session ID

## Mitso (Virtual Human)
- If this conversation started with "You are Mitso", re-read `C:\Users\chris\PROJECTS\mitso\soul.md` and use the `lightrag-query` skill to restore memory after any context compaction.

## Projects
- **OpenClaw**: Running in WSL Docker. See auto-memory for details.
