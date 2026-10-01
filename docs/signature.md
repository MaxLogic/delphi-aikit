# Signature comparison

`signature` provides declaration/implementation comparison and provisional
alignment suggestions. `compare` inspects parseable source without building.
`align` invokes a native baseline rebuild and reports bound parameter-name edits.
With `--plan-out`, a successful, revalidated alignment can save an artifact for
`refactor-apply`. The signature command does not apply suggested edits. Its
baseline build can run project-defined hooks.

```text
DelphiAIKit.exe signature --project Project.dproj --platform Win64 --config Debug --delphi 23.0 --format json --request request.json [--plan-out new-plan.json]
```

The request explicitly selects the declaration that supplies the expected
signature:

```json
{
  "schemaVersion": 1,
  "operation": "compare",
  "declaration": {
    "fileName": "Subject.pas",
    "offset": 145
  }
}
```

`offset` is the 1-based UTF-16 source offset of the method name in the selected
class declaration. It is not a byte offset or a location in preprocessed text.
Relative declaration filenames resolve against the `.dproj` directory. The file
must occur in the analyzed project models; selecting an unrelated file does not
cause the command to analyze or modify it. Unknown fields, unsupported schema or
operation values, and non-integer/non-positive offsets are rejected. Request files
must be valid UTF-8 and no larger than 64 KiB. `--plan-out` requires an `align`
request; it is rejected for `compare`.

The report includes `schemaVersion`, `operation`, project/configuration/platform,
`contextFingerprint`, `scope`, `comparison`, `diagnostics`, `summary` and
`artifacts`. The comparison includes available declaration and implementation signature facts: parameter names/types/modifiers, return type, calling convention, owner and source coordinates. Its status is `aligned`, `name-drift`, `mismatch` or
`unknown`. A known comparison returns top-level `ok` and exit 0 even when it
reports mismatching signatures. Missing or ambiguous facts return `incomplete`;
invalid requests or unavailable context return `blocked`. These rejected results
use DAK's existing exit 3 convention; CLI syntax errors use exit 2.

All current comparison reports have `applicable=false`,
`buildVerification.status="not-run"`, no edit artifact and no omitted results.
A known comparison is neither a successful compiler baseline nor permission to
apply a repair. Automatic alignment must retain successful baseline and
post-edit builds and the shared same-intent, stale-input and recovery checks.

Comparison currently uses source-backed class methods with uniquely paired
signatures. Unsupported or incomplete semantic facts remain explicit unknowns.
The command reads on-disk source; unsaved editor buffers are outside its scope.

For a provisional alignment suggestion, use the same request with
`"operation": "align"`. The report operation is
`signature.align-implementation`. A failed compiler baseline returns exit 3,
status `repair-suggestion`, `applicable=false`, the native compiler diagnostics
and retained log directory in `buildVerification`, and `suggestedEdits` with
1-based, half-open UTF-16 line/column ranges. Only uniquely paired matching
parameter types, modes, order and return types are eligible. Other differences
remain diagnostics.

Failed-baseline suggestions remain evidence for an ordinary source-repair workflow:
no artifact is written, even when `--plan-out` is supplied. A build hook that
changes observed source/context causes a blocked report without an artifact.

After a successful baseline and unchanged-context check, `--plan-out` writes a
new file exclusively. Existing output files are preserved and cause exit 3.
An already aligned method returns `no-change`, exit 0 and a zero-edit artifact.
A complete nonempty plan returns `ok`, exit 0 and `applicable=true`.
The report's `artifacts` array contains the saved filename.

```text
DelphiAIKit.exe refactor-apply --project Project.dproj --platform Win64 --config Debug --delphi 23.0 --apply-plan new-plan.json
```

Apply replans the saved signature request against fresh semantic context, compares
the complete artifact and uses the shared guarded transaction. Stale context or
changed intent is refused. Nonempty applies retain baseline/post-build and
rollback requirements. A saved artifact never authorizes its own edits.

Declaration/implementation name drift normally fails the Delphi compiler baseline;
such repairs therefore remain non-applicable. Broader semantic prerequisite,
independent-review and final acceptance work remains tracked by DAK-357.
