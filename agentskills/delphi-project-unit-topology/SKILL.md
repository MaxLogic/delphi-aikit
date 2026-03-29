---
name: delphi-project-unit-topology
description: Use DelphiAIKit `deps` to inspect Delphi project unit topology, unresolved unit references, focused neighborhood views, and resolved project-unit cycles. Use this whenever the user asks what depends on what, why a unit is included, where cycles exist, which units fan into an area, or needs dependency/topology debugging for a Delphi `.dproj`, even if they do not explicitly mention `deps`.
version: "1.0"
---

# Delphi Project Unit Topology

Use this skill to inspect project-level unit relationships in a Delphi `.dproj`.

What it does:

- exports deterministic unit-dependency topology
- shows project units versus external resolved units
- surfaces unresolved unit references
- surfaces parser-problem-linked units
- reports resolved project-unit cycles
- provides focused text views around one unit

Canonical interface:

- always use `DelphiAIKit.exe deps`
- prefer `--format json` for the first pass
- use `--format text --unit "<UnitName>"` for a concise follow-up view

Load [setup.md](setup.md) first.

Required environment:

- `DAK_EXE`: absolute path to `DelphiAIKit.exe`

Preflight:

```bash
test -x "$DAK_EXE" || { echo "DAK_EXE not executable"; exit 1; }
```

## When To Use It

Use it when we need to:

- see what units depend on a target area
- explain why a unit is present in the project graph
- inspect outgoing dependencies for one unit
- find unresolved unit references in the indexed project graph
- find resolved project-unit cycles
- separate project-owned units from external search-path units
- gather topology context before debugging or refactoring

Do not use it as sole proof when we need to:

- prove call flow between routines
- prove symbol binding or member resolution
- prove who reads or writes a variable
- prove runtime initialization order beyond unit dependency shape
- replace an actual build result

If the question becomes symbol-usage or shared-state analysis, switch to `delphi-global-vars`.

If the question becomes compile failure or build verification, switch to `delphi-build`.

## Parameters

| Switch | Required | Purpose |
| --- | --- | --- |
| `--project <file.dproj>` | yes | project to analyze |
| `--format json\|text` | no | output format; prefer `json` |
| `--output <path\|->` | no | write to file or terminal |
| `--unit "<UnitName>"` | no | focus the text report on one unit |

Rules:

1. Start with `json` unless the user only needs a quick human-readable summary.
2. Use `text` with `--unit` when the user asks about one specific unit.
3. When `--output` is omitted, DAK still writes a sibling artifact under `.dak/<ProjectName>/deps/`.
4. Read `project.contextMode` and `project.contextNote` before making strong claims; `degraded` means reduced confidence for search-path-sensitive projects.

## Command Patterns

Full project export:

```bash
"$DAK_EXE" deps --project "<path-to-project.dproj>" --format json
```

Focused unit follow-up:

```bash
"$DAK_EXE" deps --project "<path-to-project.dproj>" --format text --unit "ProblemUnit"
```

Explicit artifact output:

```bash
"$DAK_EXE" deps --project "<path-to-project.dproj>" --format json --output "<report.json>"
```

## Output And Confidence

Prefer JSON. The top-level object is:

```json
{
  "project": {
    "name": "SampleProject",
    "path": "F:\\projects\\SampleProject\\SampleProject.dproj",
    "mainSource": "F:\\projects\\SampleProject\\SampleProject.dpr",
    "contextMode": "full"
  },
  "summary": {
    "nodeCount": 4,
    "resolvedNodeCount": 3,
    "edgeCount": 4,
    "unresolvedUnitCount": 1,
    "parserProblemCount": 1
  },
  "nodes": [
    {
      "name": "SampleProject.Main",
      "path": "F:\\projects\\SampleProject\\SampleProject.Main.pas",
      "isProjectUnit": true,
      "resolution": "resolved"
    }
  ],
  "edges": [
    {
      "from": "SampleProject.Main",
      "to": "SampleProject.Shared",
      "edgeKind": "interface"
    }
  ],
  "unresolvedUnits": ["Missing.Dependency"],
  "parserProblems": [
    {
      "unitName": "Broken.Unit",
      "fileName": "F:\\projects\\SampleProject\\Broken.Unit.pas",
      "description": "..."
    }
  ],
  "cycles": ["CycleA -> CycleB -> CycleA"]
}
```

Key fields:

- `project.contextMode`: `full` or `degraded`
- `project.contextNote`: why the run is degraded, when present
- `summary.*`: quick graph counts
- `nodes[*].isProjectUnit`: whether the node belongs to the project-owned unit set
- `nodes[*].resolution`: `resolved`, `unresolved`, or `parserProblem`
- `edges[*].edgeKind`: `project`, `contains`, `interface`, or `implementation`
- `unresolvedUnits[*]`: unresolved referenced unit names
- `parserProblems[*]`: units whose parsing failed
- `cycles[*]`: resolved project-unit cycle strings

Confidence:

- `high`: `contextMode=full`, target units are resolved, and the claim is only about graph shape
- `medium`: `contextMode=degraded`, but the relevant units and edges still appear clearly
- `low`: unresolved units, parser problems, or degraded context directly affect the claim

Text output is acceptable for quick inspection, but JSON is the topology interface.

Rule:

- use `json` for any review, diagnosis, or tool-driven reasoning
- use `text` for quick summaries and focused follow-up around one unit

## Agent Workflow

1. Run `deps --format json` for the full project.
2. Read `project.contextMode` and `project.contextNote`.
3. Inspect `summary`, then `nodes`, `edges`, `unresolvedUnits`, `parserProblems`, and `cycles`.
4. If the user cares about one unit, rerun with `--format text --unit "<UnitName>"`.
5. Quote exact unit names and edge kinds when explaining conclusions.
6. If the graph shows ambiguity through unresolved units or parser problems, state that clearly instead of over-claiming.

## Interpretation Rules

Use `deps` to answer questions like:

- "What fans into this area?"
- "Why is this unit here?"
- "Is this dependency internal or external?"
- "Do we have a cycle among project units?"
- "Which unresolved units are still in this graph?"

Do not stretch `deps` into questions like:

- "Which routine calls this method?"
- "Does this property access bind to a field or a getter?"
- "Who writes this global?"
- "Will this build succeed?"

Those require another tool or direct source/build evidence.

## Reporting Pattern

When summarizing findings, prefer this structure:

1. state the context mode and whether confidence is reduced
2. name the target unit or subsystem
3. cite the specific outgoing edges, unresolved units, or cycles
4. say what `deps` does not prove if the user is pushing beyond topology

Example:

```text
The topology run was full-context. `Order.Entry` depends on `Order.Shared` through an `interface` edge and on `Order.Import` through an `implementation` edge. `Legacy.OrderBridge` is resolved but external (`isProjectUnit=false`). One unresolved reference remains: `Missing.OrderTypes`. This proves project-unit topology, not call flow or symbol binding.
```
