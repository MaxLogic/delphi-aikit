# Delphi static analysis skill

This skill helps us run Delphi static analysis in a repeatable way from an
AI tool (Claude Code, Codex CLI, or similar). It invokes TMS FixInsight and
Peganza Pascal Analyzer through `DelphiAIKit.exe`, captures reports into a
stable folder tree, and produces a short summary we can review.

The scripts are thin wrappers around the DAK CLI subcommand
`analyze`, using `--project` or `--unit`.

WSL path contract:
- Direct DAK calls accept Linux absolute paths only in `/mnt/<drive>/...` form.
- Other Linux absolute paths (for example `/home/...`) are rejected.
- Wrapper scripts remain the canonical safe route because they normalize paths with `wslpath`.

Good for:
- One-command analysis runs against a .dproj
- Consistent report collection and triage
- Comparing results across changes
- Local, repeatable analysis runs during development

Newer additions:
- FixInsight normalization (`fi-findings.md` / `fi-findings.jsonl`)
- Per-project baselines + delta reports (`baseline.json`, `delta.md`)
- Optional CI gating via env vars (see `SKILL.md`)
- `doctor.*` preflight checks

Defaults:
- Outputs go to the analyzed project root (VCS root if we find `.git`/`.svn`, otherwise the `.dproj` directory).
- If we detect Git, we ensure `_analysis/` is added to that repo’s `.gitignore`.
