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
