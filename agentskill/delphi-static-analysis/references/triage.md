# Triage heuristics and suppression guidance

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

1. `Exception.xml` / "Strong Warnings": treat as highest priority.
2. `Warnings.xml`: likely defects, suspicious code, unused/uninitialized.
3. `Optimization.xml`: often safe but can be noisy; review for free wins.
4. `Complexity.xml`: style/maintainability; do in refactor batches.

## Suppressions and baselines (avoid churn)

Prefer fixing real issues over blanket suppression, but when we must suppress:

- Suppress by path for third-party/generated code:
  - use `DCR_EXCLUDE_PATH_MASKS` for deterministic post-filtering of FixInsight outputs.
- Suppress by rule id only after confirming the rule is noisy for our codebase:
  - use `DCR_IGNORE_WARNING_IDS` (post-processing; does not affect analysis runtime).
- For local, intentional exceptions:
  - FixInsight supports inline suppression comments (see FixInsight manual).
  - Pascal Analyzer supports `PALOFF`-style suppression comments (see Peganza docs).
