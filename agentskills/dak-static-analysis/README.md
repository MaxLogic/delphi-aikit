# Delphi static analysis skill

Use this skill to run TMS FixInsight and Peganza Pascal Analyzer through
`DelphiAIKit.exe` from Claude Code, Codex CLI, or another AI tool. It collects
reports in a consistent folder structure and produces a short review summary.

All analysis, report finalization and verification run inside `DelphiAIKit.exe`
(`analyze`, `analyze-unit`, `analyze-doctor`, `analyze-report`). The `.bat` and
`.sh` files are thin launchers: they find the executable, forward their
arguments and, under WSL, convert paths. No Python is required.

WSL path contract:
- Direct DAK calls accept Linux absolute paths only in `/mnt/<drive>/...` form.
- Other Linux absolute paths (for example `/home/...`) are rejected.
- Prefer the shell launchers for path conversion; they use `wslpath`.

Use it for:
- One-command analysis runs against a .dproj
- Consistent report collection and triage
- Comparing results across changes
- Local, repeatable analysis runs during development

Reports and checks:
- FixInsight normalization (`fi-findings.md` / `fi-findings.jsonl`)
- Per-project baselines and delta reports (`baseline.json`, `delta.md`)
- Optional CI gating via env vars (see `SKILL.md`)
- `doctor.*` preflight checks
- Read-only verification: `DelphiAIKit.exe analyze-report --out <output> --verify`

Defaults:
- Project runs write under the analyzed `.dproj` directory in sibling `.dak/<ProjectName>/`.
- Unit runs write under the analyzed unit directory in sibling `.dak/_unit/<UnitName>/`.
