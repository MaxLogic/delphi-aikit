# Triage heuristics and suppression guidance

## Generated triage.md (shortlist)

Our `postprocess.py` emits `.dak/<ProjectName>/triage.md` as a prioritized shortlist (top 20 by default; override with `DAK_TRIAGE_TOP=<N>`). It is intentionally a *short* "what to fix next" view; full detail remains in `fi-findings.*` and `pal-findings.*` / raw PAL XML.

Optional: set `DAK_TRIAGE_SNIPPETS=1` to also emit `.dak/<ProjectName>/triage-snippets.md` with small, bounded source snippets for the top triage items. This is meant to speed up fixing without opening files manually; it will only include snippets for repo-local paths that exist on disk.

## FixInsight (signal first)

FixInsight reports rule IDs like `W502`, `O801`, `C101`.

Practical triage:

1. Fix hard correctness first:
   - parser/fatal errors (tool failure)
   - warnings about resource leaks, unreachable code, empty exception handlers, suspicious free, missing inherited destructor, etc.
2. Fix low-risk hygiene next:
   - truly unused locals/units, useless code, redundant statements
3. Treat refactor pressure separately:
   - long methods, too many vars/params, deep nesting, convention style

Confidence:

- High when a finding is local and mechanically provable by the compiler (e.g., unused local variable).
- Medium when it changes control flow or resource lifetime (e.g., empty except/finally, missing inherited).
- Low when it is a design/style heuristic (e.g., long method).

## Pascal Analyzer (what to care about)

PALCMD produces multiple reports. Triage order:

1. "Strong Warnings": treat as highest priority.
2. `Exception.xml`: only treat as high-signal if it contains finding-like sections (ignore "Exception Call Tree" unless we explicitly need throw propagation).
3. `Warnings.xml`: likely defects, suspicious code, unused/uninitialized.
4. `Optimization.xml`: often safe but can be noisy; review for free wins.
5. `Complexity.xml`: style/maintainability; do in refactor batches.

## Suppressions and baselines (avoid churn)

Prefer fixing real issues over blanket suppression, but when we must suppress:

- Suppress by path for third-party/generated code:
  - use `DAK_EXCLUDE_PATH_MASKS` for deterministic post-filtering of FixInsight outputs.
- Suppress by rule id only after confirming the rule is noisy for our codebase:
  - use `DAK_IGNORE_WARNING_IDS` (post-processing; does not affect analysis runtime).
- For local, intentional exceptions:
  - FixInsight supports inline suppression comments (see FixInsight manual).
  - Pascal Analyzer supports `PALOFF`-style suppression comments (see Peganza docs).
