# PAL Int64 and implementation-parsing checks

## Int64 Inc/Dec, Delphi 12

On Win32 and Win64, the tested Int64 locals, record fields and pointer fields
preserve deltas larger than 32 bits with both `Inc` and `Dec`. The standalone
control reads its delta from the command line and checks each operation
independently, starting from zero.

The six deltas are 2,147,483,648; 4,294,967,296; 4,294,967,297;
-2,147,483,649; -4,294,967,296; and -4,294,967,297. All 72 full-width checks
passed across the two targets. Twelve separate Integer controls showed the
expected narrowing. For example, 4,294,967,297 remains intact with Int64 and
becomes 1 with Integer. A call using only 1 cannot establish this behavior;
neither can an unchecked cancelling Inc/Dec pair.

PAL 9.21.4.0 reports all six Int64 calls as 32-bit parameter mismatches even
with `CompleteParsing=1`. The raw control report contains nine mismatch rows:
the six disputed calls, the Integer Inc, and two conversion diagnostics at the
control comparison. This result applies to the tested Int64 destinations and
values, not every ordinal combination. T-232 remains open.

## Dependency implementation parsing

Set `[Parser] CompleteParsing=1` in the effective PAL.INI to parse
implementations of non-reported units. In the receiver-reference control,
PAL 9.21.4.0 reports two disputed `lState` rows with this setting disabled.
Enabling it removes both rows while retaining the genuine `lUnused` control,
on Win32 and Win64. No new exclusions or finding filters were used.

The record-field missing-const control still produces the same five rows
with either setting. A correction is not verified; T-233 remains open.

Peganza documents the [parser option](https://www.peganza.com/PALHelp/properties___parser.htm)
and [PALCMD INI selection](https://www.peganza.com/PALHelp/how_to_use_palcmd_exe_.htm).
Parsing dependency implementations supplies caller context while leaving
routine vendor reporting exclusions in place.

## Routine setup and verification

Our routine PAL setup uses `CompleteParsing=1`. DAK inherits PAL's effective
configuration; its executable does not enforce this value. An explicit `/I`
or saved PAP project can override installation defaults. See the
[analysis setup instructions](../agentskills/dak-static-analysis/SETUP.md).

Two normal DAK project runs with the setting disabled reproduced the receiver
rows. Four enabled runs, covering project and project-context unit analysis on
both targets, retained only the genuine unused control. Raw and normalized
rows agree, and all six finalized diagnostic outputs passed verification.

The configuration change leaves source and executables unchanged. Record the
effective INI hash and review affected PAL baselines before reuse; these
diagnostic outputs do not replace maintained acceptance baselines.

## Remaining receiver cases

The isolated maxTdb caller comparison removes three of four disputed rows on
both Win32 and Win64. `RecordExpressionPlanBuild`, `RecordIrProgramDecode` and
`RecordProgramMetadataDecode` clear with complete parsing enabled. `Snapshot`
still reports its `lState` receiver, whose Int64 fields are read through
`TInterlocked.Read`. Raw and normalized occurrences agree. The larger caller
context has the same three unresolved dependencies with either setting; this
comparison does not certify complete project analysis.

A separate RTL-only reduction has no missing dependencies. Its object and
record `Read` cases and a direct `CompareExchange` case all retain the receiver
warning with either setting, on both targets. The genuine unused-variable
control also remains. Both builds and executions pass: each target checks six
positive/negative full-width reads and four unchanged-input comparisons.
All four analyzer outputs pass normalized-report verification.

In Delphi 12, `TInterlocked.Read` calls `CompareExchange`, whose Int64 overload
calls `AtomicCmpExchange`. The runtime checks show that the receiver is used;
they do not establish PAL's internal cause. T-234 remains open. Complete parsing
is still our default because it resolves the verified Increment/Add cases.

The new BSON control also reproduces T-293 with complete parsing enabled. Two
enabled runs yield 19 and 59 cast findings, as do the two disabled controls.
The same 40 complete observations differ in each pair, with unchanged inputs
and no missing dependencies. This setting does not resolve that instability.

Commands, source hashes, raw reports, normalized comparisons and standalone
sources are retained under
`projects/.dak/DelphiAIKit/goal-current/pal-acceptance-20260911/`.
