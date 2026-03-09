---
name: delphi-global-vars
description: Use DelphiAIKit `global-vars` to inventory Delphi project globals, inspect declarations and usages, detect unused/shared mutable state, and assess ambiguity before refactoring globals.
version: "1.0"
---

# Delphi Global Vars

Use this skill to analyze and refactor project-level shared state in a Delphi `.dproj`.

What it does:

- finds unit-level `var`
- finds `threadvar`
- finds typed constants
- finds `class var`
- reports declaration metadata
- reports `usedBy` routines with access kind
- reports unresolved `ambiguities`
- reports project summary counts

Canonical interface:

- always use `DelphiAIKit.exe global-vars`
- do not use PAL, FixInsight, or direct cache queries for normal refactoring work

Load [setup.md](setup.md) first.

Required environment:

- `DAK_EXE`: absolute path to `DelphiAIKit.exe`

Preflight:

```bash
test -x "$DAK_EXE" || { echo "DAK_EXE not executable"; exit 1; }
```

## When To Use It

Use it when we need to:

- find globals in a project
- see where a global is declared
- see which routines read or write a global
- find unused globals
- assess cross-unit coupling through shared state
- decide whether a global is a removal, rename, or encapsulation candidate

Do not use it as sole proof when we need to:

- prove exact binding at an ambiguous site
- reason about local variables inside one routine
- prove that a member/property access cannot be a global when ambiguity remains

## Parameters

| Switch | Required | Purpose |
| --- | --- | --- |
| `--project <file.dproj>` | yes | project to analyze |
| `--format json\|text` | no | output format; prefer `json` |
| `--output <path\|->` | no | write to file or terminal |
| `--unused-only` | no | emit only globals with no resolved usages |
| `--unit "<pattern>"` | no | wildcard filter on declaring unit |
| `--name "<pattern>"` | no | wildcard filter on symbol name |
| `--reads-only` | no | emit only globals with read/readwrite usage |
| `--writes-only` | no | emit only globals with write/readwrite usage |
| `--delphi <version>` | no | Delphi version, for example `23.0` |
| `--platform <name>` | no | build platform, for example `Win32` |
| `--config <name>` | no | build config, for example `Release` |
| `--refresh auto\|force` | no | reuse or rebuild analysis |
| `--cache <sqlite-file>` | no | override default cache path |

Rules:

1. `--reads-only` and `--writes-only` are mutually exclusive.
2. `--unused-only` cannot be combined with `--reads-only` or `--writes-only`.
3. If `--unit` or `--name` has no wildcard, DAK treats it like `*text*`.
4. If `--delphi` is omitted, DAK tries `[Build] DelphiVersion` from cascading `dak.ini`.

## Command Patterns

Full project export:

```bash
"$DAK_EXE" global-vars --project "<path-to-project.dproj>" --format json --output "<report.json>"
```

Unused globals:

```bash
"$DAK_EXE" global-vars --project "<path-to-project.dproj>" --format json --unused-only
```

Writes in one subsystem:

```bash
"$DAK_EXE" global-vars --project "<path-to-project.dproj>" --format json --writes-only --unit "*Data*"
```

One symbol family:

```bash
"$DAK_EXE" global-vars --project "<path-to-project.dproj>" --format json --name "Cache"
```

Force re-scan:

```bash
"$DAK_EXE" global-vars --project "<path-to-project.dproj>" --format json --refresh force
```

## Output And Confidence

Prefer JSON. The top-level object is:

```json
{
  "summary": {
    "total": 5,
    "used": 4,
    "unused": 1,
    "ambiguities": 0,
    "emitted": 5,
    "filter": "all"
  },
  "symbols": [
    {
      "declaringUnit": "GlobalVarsFixture.Globals",
      "fileName": "F:\\projects\\MaxLogic\\DelphiAiKit\\tests\\fixtures\\GlobalVarsFixture.Globals.pas",
      "name": "GCounter",
      "type": "Integer",
      "kind": "var",
      "line": 12,
      "column": 3,
      "usedBy": [
        {
          "unit": "GlobalVarsFixture.Consumer",
          "routine": "RunConsumer",
          "file": "F:\\projects\\MaxLogic\\DelphiAiKit\\tests\\fixtures\\GlobalVarsFixture.Consumer.pas",
          "line": 14,
          "column": 3,
          "access": "write"
        }
      ]
    }
  ],
  "ambiguities": []
}
```

This sample comes from the fixture project and matches the real field names. Actual arrays may be longer.

Key fields:

- `summary.total`: all discovered globals
- `summary.used`: globals with at least one resolved usage
- `summary.unused`: globals with no resolved usage
- `summary.ambiguities`: unresolved usage sites
- `summary.emitted`: symbols left after filters
- `symbols[*].fileName`, `line`, `column`: declaration location
- `symbols[*].usedBy`: resolved usage evidence
- `symbols[*].usedBy[*].file`, `line`, `column`: usage location
- `ambiguities[*]`: follow-up required before strong claims

Confidence:

- `high`: target symbol has clear declaration and no relevant ambiguity
- `medium`: some ambiguity exists, but not on the target symbol or key write sites
- `low`: ambiguity touches the target symbol or behavior-critical write sites

Text output is acceptable for quick inspection, but JSON is the refactor interface.

Rule:

- use `text` only for quick inventory
- use `json` for any review or refactor decision

## Refactor Workflow

1. Export JSON for the project.
2. Narrow with `--name` or `--unit` if needed.
3. Read `summary`.
4. Inspect the target symbol's declaration, kind, type, and `usedBy`.
5. Inspect `ambiguities`.
6. Choose one action:
   - remove
   - rename
   - encapsulate
   - stop and inspect source manually

## Refactor Actions

Remove:

- only when the symbol is emitted by `--unused-only`
- and no ambiguity appears to affect that symbol
- and source inspection does not show initialization/finalization or other non-routine usage we still care about

Rename:

- only when the declaration is clear
- and important usage sites are attributable
- and ambiguity does not affect the target symbol or key write sites

Encapsulate:

- when the symbol has many write sites
- or is written from multiple routines or units
- or creates hidden cross-unit coupling
- or is a `class var` or typed constant behaving like mutable shared state

Stop and inspect manually:

- when ambiguity touches the target symbol
- when a decision depends on an unresolved write site
- when the symbol participates in startup, shutdown, threading, persistence, caching, or error handling

Kind-specific caution:

- `threadvar`: verify thread semantics before changing ownership or lifetime
- `typedconst`: if writes exist, treat it as mutable shared state
- `class var`: treat it as cross-instance shared state by default

## Limits

Strong for:

- inventorying globals
- finding many concrete usage sites
- identifying unused globals
- spotting cross-unit shared state

Weaker for:

- exact semantic proof at ambiguous sites
- absolute claims when several same-name globals are visible
- parser edge cases that still require heuristic handling

Cache note:

- default cache path is `.dak/<ProjectName>/global-vars/cache/global-vars-cache.sqlite3`
- the cache exists for speed
- review and refactor decisions should be based on command output, preferably JSON
