# Delphi global vars skill

Use this skill to run DelphiAIKit's `global-vars` command for:

- project-wide global variable inventory
- unused-global discovery
- "who uses this global?" questions
- focused runs on one unit or symbol family
- careful handling of ambiguous matches

The skill assumes:

- DelphiAIKit already implements `global-vars`
- reports and caches live under sibling `.dak/<ProjectName>/global-vars/`
- SQLite cache reuse is the default behavior

This skill covers analysis and reporting. Work on the analyzer's implementation follows the repository's development workflow.

