# Delphi static analysis skill

This skill helps us run Delphi static analysis in a repeatable way from an
AI tool (Claude Code, Codex CLI, or similar). It invokes TMS FixInsight and
Peganza Pascal Analyzer through `DelphiConfigResolver.exe`, captures reports
into a stable folder tree, and produces a short summary we can review.

The scripts are thin wrappers around the DCR CLI subcommands
`analyze-project` and `analyze-unit`.

Good for:
- One-command analysis runs against a .dproj
- Consistent report collection and triage
- Comparing results across changes
- Local, repeatable analysis runs during development
