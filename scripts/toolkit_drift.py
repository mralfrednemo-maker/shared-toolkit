"""Detect drift between shared/TOOLKIT.md and shared/TOOLKIT-INDEX.md.

Parses:
- TOOLKIT.md:       `### <tool name>` headers under any `## TIER` section
- TOOLKIT-INDEX.md: first column of every markdown table row

Reports tools present in one file but not the other.
Exit 0 = in sync, exit 1 = drift detected.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TOOLKIT = ROOT / "TOOLKIT.md"
INDEX = ROOT / "TOOLKIT-INDEX.md"

TIER_RE = re.compile(r"^## TIER\b", re.MULTILINE)
TOOL_HEADER_RE = re.compile(r"^### (.+?)\s*(?:<!--\s*drift-ignore.*?-->)?\s*$", re.MULTILINE)
IGNORE_TAG_RE = re.compile(r"<!--\s*drift-ignore\b")
TABLE_ROW_RE = re.compile(r"^\|\s*([^|]+?)\s*\|(.*)$", re.MULTILINE)


def normalise(s: str) -> str:
    s = s.strip().lower()
    s = re.sub(r"[`*_]", "", s)
    s = re.sub(r"\s+", " ", s)
    return s


def extract_toolkit_tools(text: str) -> set[str]:
    tier_start = TIER_RE.search(text)
    scope = text[tier_start.start():] if tier_start else text
    tools = set()
    for line in scope.splitlines():
        if not line.startswith("### "):
            continue
        if IGNORE_TAG_RE.search(line):
            continue
        name = line[4:].split("<!--")[0].strip()
        tools.add(normalise(name))
    return tools


def extract_index_tools(text: str) -> set[str]:
    tools = set()
    for m in TABLE_ROW_RE.finditer(text):
        cell = m.group(1).strip()
        rest = m.group(2)
        if IGNORE_TAG_RE.search(cell) or IGNORE_TAG_RE.search(rest):
            continue
        cell = re.sub(r"<!--.*?-->", "", cell).strip()
        if cell.lower() in {"tool", "agent", "pipeline", "profile"} or re.match(r"^-+$", cell):
            continue
        tools.add(normalise(cell))
    return tools


def main() -> int:
    if not TOOLKIT.exists() or not INDEX.exists():
        print(f"missing file: {TOOLKIT if not TOOLKIT.exists() else INDEX}", file=sys.stderr)
        return 2
    toolkit = extract_toolkit_tools(TOOLKIT.read_text(encoding="utf-8"))
    index = extract_index_tools(INDEX.read_text(encoding="utf-8"))

    missing_in_index = sorted(toolkit - index)
    extra_in_index = sorted(index - toolkit)

    if not missing_in_index and not extra_in_index:
        print(f"[sync] {len(toolkit)} tools in TOOLKIT.md, {len(index)} entries in INDEX — no drift")
        return 0

    print(f"[drift] TOOLKIT.md has {len(toolkit)} tools, INDEX has {len(index)} entries")
    if missing_in_index:
        print("\n  In TOOLKIT.md but missing from TOOLKIT-INDEX.md:")
        for t in missing_in_index:
            print(f"    - {t}")
    if extra_in_index:
        print("\n  In TOOLKIT-INDEX.md but not found in TOOLKIT.md (normalise mismatch or stale):")
        for t in extra_in_index:
            print(f"    - {t}")
    return 1


if __name__ == "__main__":
    sys.exit(main())
