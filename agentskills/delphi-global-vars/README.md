# Delphi global vars skill

This skill helps an AI agent use DelphiAIKit's `global-vars` command effectively.

It is designed for:

- project-wide global variable inventory
- unused-global discovery
- "who uses this global?" questions
- focused runs on one unit or symbol family
- careful handling of ambiguous matches

The skill assumes:

- DelphiAIKit already implements `global-vars`
- reports and caches live under sibling `.dak/<ProjectName>/global-vars/`
- SQLite cache reuse is the default behavior

Use this skill when the task is analysis/reporting. Do not use it for backend implementation work on the analyzer itself.

