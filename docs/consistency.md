# Read-only consistency inspection

`consistency` reports interface GUID inventory and source-backed DFM event
signature comparisons for one explicit Delphi project configuration:

```powershell
DelphiAIKit.exe consistency --project C:\work\App.dproj --config Debug --platform Win64 --delphi 23.0 --format json
```

All four context switches are required. JSON is the default and currently the
only format. There is no apply, repair, request-file or saved-plan mode. The
command does not compile or modify the analyzed source. Continue using
`dfm-check` for runtime streaming validation; semantic inspection does not
replace it.

The implementation is partial while Refactoring Light slice 7 remains active.
Broader ancestry, semantic and resource-discovery coverage are still open.
For supported source-backed signatures, an omitted calling convention compares
as `register`. Explicit convention differences remain mismatches.
Supported source-defined aliases resolve in their own declaring import context.
Ordinary aliases share target identity; strong aliases remain distinct. Event-type
evidence points to the underlying procedure declaration, whose scope governs its
parameters. Missing, ambiguous, cyclic or stale declaration evidence stays unknown.

## JSON contract

The report contains:

- `schemaVersion: 1`, `operation: "consistency.inspect"` and `status`.
- Absolute `project`, selected `config`, `platform`, `delphiVersion` and the
  semantic project's `contextFingerprint`. The fingerprint identifies context;
  it is not an apply authorization or a source mutation plan.
- `scope.complete` and, when a session opens, `scope.analyzedRoots`.
- `guids`: declaration unit, file, name, GUID, dispinterface flag and status
  (`unique`, `valid-pair`, `duplicate`, `missing-guid` or `unknown`).
- `events`: assignment DFM path/line, effective `formFileName`, component name/class, form class, property and handler
  names, result/reason, and available event-property, event-type and handler
  declaration locations.
- `diagnostics`: stable `reason` codes, file names and explanatory messages.
- `summary.guidCount`, `eventCount`, `diagnosticCount`, `omittedResultCount`.
  Results are not truncated. `artifacts` is currently empty; the full report is
  written to stdout.

`ok` with exit 0 means the requested inspection completed. It can contain
duplicate or missing GUIDs, mismatched signatures or missing handlers. Inspect
the findings; `ok` does not mean the project has no consistency problems.
`incomplete` and `blocked` return exit 3. Missing projects/environment, model
diagnostics, unresolved facts and unsupported DFM coverage cannot produce an
empty successful report. Argument errors retain DAK's exit 2 convention.

## Current coverage and limits

DelphiSemantics owns GUID classification, event-property/type/handler lookup,
source class ancestry and signature comparison. DAK supplies DFM bindings and
report locations. A resolved event can be `match`, `mismatch` or
`missing-handler`; unavailable or ambiguous semantic facts remain `unknown`
and make the report incomplete.

DAK currently inspects text DFM files beside analyzed source files with the
same stem. It retains `On...` assignments and also considers identifier-valued
properties, so source-defined events such as `Changed = HandleChange` are not
silently omitted. Properties whose source declarations prove an enum, class,
record or interface type are excluded from event results, even when their names
start with On. Unresolved aliases and other unproved ordinary types can remain
unknown; general non-event property classification is unfinished. `nil`
assignments have no attached handler to compare.
Inherited text forms now merge supported ancestor resources from base to child.
An unchanged assignment retains its ancestor `fileName` and line; an override
uses the child's location. `formFileName` identifies the effective form being
inspected, so an ancestor binding can appear for both the base and child forms.
A `nil` override clears the inherited binding. Component class lookup retains
the original declaration unit while handler lookup starts at the descendant.
An inherited component must exist at the same parent path with the same class.
Missing/conflicting components and inline frames remain incomplete. The merge
must reach an ordinary `object` resource through guarded source class ancestry;
a partial semantic chain alone is insufficient.
Every traversed source class must have supported resource coverage. A class
without a DFM resource may be skipped; a declared resource that is missing or
unmapped stops the merge, including at an intermediate ancestor.

The following have explicit incomplete dispositions:

- Binary DFM: `dfm.binary-unsupported`. Existing binary streaming remains
  available through `dfm-check`.
- Inherited form/component or inline frame data without merged ancestor DFM
  evidence: `dfm.ancestry-unavailable`. Semantic class ancestry alone does not
  establish the full streamed form state.
- Missing standard DFM resource: `dfm.resource-unavailable`.
- Nonstandard resource layout: `dfm.resource-layout-unsupported`.
- Included source whose resource mapping has not been proved:
  `dfm.include-resource-coverage-unknown`.

Resource discovery is conservative and can report incomplete for inactive
directives or includes without DFM resources. Do not reinterpret these results
as evidence that no event binding exists. Source-less components, unresolved
aliases, partial models and ambiguous declarations remain subject to the
semantic layer's refusal rules. No automatic repair is offered.
