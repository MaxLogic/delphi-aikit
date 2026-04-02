---
name: delphi-project-unit-topology
description: "Inspect Delphi project unit topology with DelphiAIKit `deps`: resolved and unresolved units, project vs external edges, SCCs, cycle hotspots, and focused unit views. Use when Codex needs to answer what depends on what, why a unit is present, whether project-unit cycles exist, where to start reducing cycle debt, which `uses` edge is the best first candidate to cut, or when a Delphi `.dproj` needs dependency-topology diagnosis."
---

# Delphi Project Unit Topology

Use `DelphiAIKit.exe deps` for project-level dependency shape and cycle triage.

Load [setup.md](setup.md) first.

Preflight:

```bash
test -x "$DAK_EXE" || { echo "DAK_EXE not executable"; exit 1; }
```

## Route The Request

Use this routing before running commands:

| User intent | Command | Read first |
| --- | --- | --- |
| "What depends on what?" / "Why is this unit here?" | `deps --format json` | `summary`, `nodes`, `edges` |
| "Do we have cycles?" | `deps --format json` | `cycleComponents` |
| "Where do we start fixing cycle debt?" | `deps --format json` | `cycleComponents`, `unitHotspots`, `edgeHotspots` |
| "Show one unit in context" | `deps --format text --unit "<UnitName>"` | focused text report |
| "Give me a short ranked list" | `deps --format text --top <N>` | hotspot text sections |
| "Who reads or writes this global?" | switch skill | `delphi-global-vars` |
| "Will this build succeed?" | switch skill | `delphi-build` |

Start with JSON unless the user only wants a quick human-readable follow-up.

## Command Patterns

Full graph:

```bash
"$DAK_EXE" deps --project "<path-to-project.dproj>" --format json
```

Focused unit:

```bash
"$DAK_EXE" deps --project "<path-to-project.dproj>" --format text --unit "ProblemUnit"
```

Compact hotspot summary:

```bash
"$DAK_EXE" deps --project "<path-to-project.dproj>" --format text --top 10
```

Rules:

1. `--top` affects text hotspot sections only. Default is `20`; `0` means unlimited.
2. If `--output` is omitted, DAK still writes an artifact under `.dak/<ProjectName>/deps/`.
3. Read `project.contextMode` and `project.contextNote` before making strong claims.

## What The JSON Means

Treat JSON as the primary interface. The important fields are:

- `project.contextMode`: `full` or `degraded`
- `summary.*`: node, edge, unresolved, and parser-problem counts
- `nodes[*].isProjectUnit`: project-owned vs external resolved unit
- `nodes[*].resolution`: `resolved`, `unresolved`, or `parserProblem`
- `nodes[*].unitCycleScore`: SCC-internal degree; `0` means not in a detected cycle
- `nodes[*].sccId`: SCC membership; `null` means acyclic
- `edges[*].edgeKind`: `project`, `contains`, `interface`, or `implementation`
- `edges[*].isCycleEdge`: `true` if both endpoints are in the same SCC
- `unresolvedUnits[*]`: unresolved referenced unit names
- `parserProblems[*]`: units whose parsing failed
- `cycleComponents[*]`: structured SCC records; prefer these over `cycles`
- `cycleComponents[*].representativeCycle`: real traversal path, not a synthetic alphabetical join
- `unitHotspots[*]`: ranked hub candidates inside SCCs
- `edgeHotspots[*]`: ranked edge-cut candidates inside SCCs
- `cycles[*]`: compatibility array only; do not use as the primary analysis surface

Minimal shape:

```json
{
  "project": { "contextMode": "full" },
  "summary": { "nodeCount": 4, "edgeCount": 4 },
  "nodes": [
    { "name": "Main", "resolution": "resolved", "unitCycleScore": 4, "sccId": 1 }
  ],
  "edges": [
    { "from": "Main", "to": "Shared", "edgeKind": "interface", "isCycleEdge": true }
  ],
  "cycleComponents": [
    {
      "sccId": 1,
      "sccSize": 2,
      "sccInternalEdgeCount": 2,
      "members": ["Main", "Shared"],
      "representativeCycle": "Main -> Shared -> Main"
    }
  ],
  "unitHotspots": [
    { "name": "Main", "unitCycleScore": 4, "sccId": 1 }
  ],
  "edgeHotspots": [
    {
      "from": "Main",
      "to": "Shared",
      "edgeKind": "implementation",
      "edgeHotspotRank": 7,
      "refactorabilityHint": "easier",
      "sccId": 1
    }
  ]
}
```

## Interpretation Rules

Use these rules consistently:

1. If `contextMode=degraded`, lower confidence. Missing search-path edges can distort SCCs and hotspot scores.
2. If `cycleComponents` is empty, report that the resolved project graph is acyclic and stop the hotspot analysis.
3. `unitCycleScore` is intra-SCC degree, not a simple-cycle count. Do not say "appears in N cycles."
4. `edgeHotspotRank` is the sum of endpoint scores. It is a heuristic for leverage, not proof that one cut breaks the SCC.
5. Prefer `implementation` edges when ranks tie. They are usually cheaper to break in Delphi than `interface` edges.
6. Treat `refactorabilityHint=easier` as a first candidate, not a guarantee of low effort.
7. Do not claim the hotspot list is exhaustive when unresolved units or parser problems are nearby.
8. Re-run `deps` after a refactoring. Use the new SCC and hotspot output as proof of improvement.

Use `deps` to answer:

- what depends on what
- why a unit is present
- whether a dependency is internal or external
- whether project-unit cycles exist
- where to start reducing cycle debt
- which unit is the main hub in a cycle cluster
- which `uses` edge is the best first candidate to cut

Do not use `deps` alone to answer:

- who reads or writes a variable
- which routine calls a method
- how a symbol binds
- whether the project builds successfully

## Operating Workflow

For topology questions:

1. Run `deps --format json`.
2. Read `project.contextMode`, `summary`, `nodes`, `edges`, `unresolvedUnits`, `parserProblems`.
3. Quote exact unit names and edge kinds.
4. If the user asks about one unit, rerun with `--format text --unit`.

For cycle-remediation questions:

1. Run `deps --format json`.
2. Read `cycleComponents` first.
3. If there are no SCCs, report that there is no detected cycle debt in resolved project units.
4. Read `unitHotspots` to identify the most connected hubs.
5. Read `edgeHotspots` to identify likely first-cut edges.
6. Prefer `implementation` edges over equal-rank `interface` edges.
7. Recommend one concrete first cut and explain why it is a candidate.
8. State that one cut may reduce hub connectivity without dissolving the whole SCC.

## Reporting Pattern

For topology findings, report:

1. context quality: `full` or `degraded`
2. target unit or subsystem
3. relevant edges, unresolved units, parser problems, or SCC membership
4. what `deps` does not prove

For cycle-hotspot findings, report:

1. number of SCCs and the largest component
2. top unit hubs with `unitCycleScore`
3. top edge candidates with `edgeKind`, `edgeHotspotRank`, and `refactorabilityHint`
4. one concrete first-cut recommendation
5. a caveat that the SCC may survive and should be re-checked with another `deps` run

Example hotspot summary:

```text
The graph has 2 cycle components. The largest SCC has 11 units and 23 internal edges.
`DataModule` is the main hub (`unitCycleScore=12`), followed by `GlobalVars` (`9`).
The best first candidate is `DataModule -> GlobalVars` because it is an
`implementation` edge with the highest reported rank. That makes it a cheaper first
cut than an equal-rank `interface` dependency, but it is still only a candidate. Re-run
`deps` after the change to confirm whether the SCC shrank or disappeared.
```
