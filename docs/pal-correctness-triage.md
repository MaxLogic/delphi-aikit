# PAL correctness review, 2026-09-07

T-252 reviewed 30 owned findings from the retained PAL 9.21.4.0 report in
`projects/.dak/DelphiAIKit/remove-with-performance-20260907/reviewed-analysis/`.
The scope is one strong warning plus all findings in the out-parameter,
possible-bad-assignment, 32/64-bit mismatch, and malformed-Format categories.
No runtime defect was confirmed. This is source review, not a claim that all
PAL findings are false positives or that the entire codebase is warning-free.

| Finding | Count | Disposition and source evidence |
| --- | ---: | --- |
| Ambiguous unit references | 1 | `dak.analyze.unitrunner.pas:251` imports two `TryFindPalReportRoot` declarations. The selected implementation in `dak.pascalanalyzerrunner.pas:1335` delegates directly to `Dak.PascalAnalyzer.Artifacts`. The collision is real; current behavior is equivalent. Explicit qualification would be optional clarity cleanup. |
| Misformed call to Format-function | 4 | `dak.lsp.runner.pas:570`: all four `%d` arguments use `GetValue<Integer>`. The installed RTL declares its return type as `T`. These are analyzer type-inference false positives. |
| Out parameter is read before set, or never set | 12 | Conditional-output contracts and managed output strings, detailed below. Successful scalar results are assigned; callers reject failure before reading them. No uninitialized read was found. |
| Possible bad assignment | 3 | `dak.pascalanalyzerrunner.pas:900` converts processor count and clamps the thread request to 64. `dak.build.runner.pas:1610` converts elapsed milliseconds to `Int64`. `dak.dfmcheck.pas:156` deliberately preserves window-style bits in an unsigned value. No failing supported case was found. |
| Mismatch parameter value (32/64-bits) | 7 | Safe or bounded operations, detailed below. |
| Mismatch parameter value (32/64-bits) | 3 | Real collection-count narrowing at `Dak.GlobalVars.Cache.pas:704` and `dak.globalvars.pas:222/223`. These remain documented limits, not false positives. |

The twelve output-parameter findings were checked at these call boundaries:

- `dak.build.runner.pas:547`: callers at 620/624 test the Boolean result.
- `dak.cli.pas:527/529/530`: implementations at 636/689/705 assign successful outputs; callers guard failure.
- `Dak.Settings.pas:412/425`: callers at 458/859 guard the parse result.
- `Dak.GlobalVars.Semantics.pas:76`: caller at 235 reads the kind only on success.
- `Dak.RemoveWith.Symbols.pas:283`: callers at 377/379 guard resolution.
- `dak.rsvars.pas:100`: process creation failure returns false; caller at 174 exits before reading the exit code.
- `Dak.RemoveWith.Resolver.pas:3676/3697` and `Dak.SymbolMap.pas:638`: managed `out string` errors are cleared on entry. Successful paths need no error text; callers propagate failures before using results.

Seven of the width warnings describe valid operations:

- `dak.dfmcheck.pas:147` dereferences a `Cardinal` record field through the pointer. It does not truncate the pointer.
- `dak.dfmcheck.pas:1735/1737` explicitly widens exit codes to `Int64`.
- `dak.build.runner.pas:1207` widens the high FILETIME word before shifting.
- `Dak.RemoveWith.pas:369` checks `High(Integer)` before narrowing elapsed milliseconds.
- `Dak.RemoveWith.Source.pas:348` widens an integer list index to `NativeInt`.
- `dak.analyze.common.pas:307` narrows a dictionary count. Its rule keys are constrained to one ASCII letter plus three digits, at most 26,000 distinct keys.

The three remaining count conversions use the existing `Integer` summary
contract. Overflow would require more than 2,147,483,647 retained entries.
We found no reachable supported workload at that size. Widening the public
summary contract is outside this fix; a future requirement to support that size
should specify rejection or wider counters and test the boundary without
allocating billions of objects. These findings remain visible in PAL reports.

No production code or analyzer suppression was changed for this review.
The task proof checks coverage against the selected raw findings and hashes
the inspected source files. A later source change requires reviewing affected
dispositions again.

## T-293: BSON cast report varies between runs, 2026-09-10

PAL changes its native STWA6 findings for unchanged `Grijjy.Bson.pas` source.
This is separate from the three existing PAL reports and from T-265's ownership
classification. No source conversion or warning exclusion was changed.

| Controlled run | Observed difference |
| --- | --- |
| PAL 9.21.4.0, full frozen Win32 Release project, `/T=32` | 92,367 versus 92,327 normalized PAL findings. Exactly 40 BSON cast findings disappear; every other row matches. |
| Same compiler context, BSON unit entry point, `/T=32` | 293 versus 333 findings. The same 40 cast findings appear. |
| Direct BSON unit replay, `/T=1` | Native typecast-section totals of 59 and 19. Single-threaded reporting does not prevent the variation. |
| PAL 9.21.5.0 evaluation, `/T=32` | Declared typecast totals of 19 and 59. Evaluation masking prevents a complete detail-row comparison. |
| Exact repeated command and output path, 9.21.4.0 `/T=1` | Retained before/after reports still differ by the same 40 rows. Output-path choice is not a verified workaround. |
| Narrow search path and an explicit, hash-checked PAL.INI, original source location | Typecast totals of 19 and 59, with unchanged source/configuration hashes. |

The 40 rows cover both operands in 20 equality/inequality statements. Each of
the ten record types declares a conversion to `TgoBsonValue`. This source review
establishes deliberate conversions; it does not certify every cast in the
library or identify PAL's internal cause.

The unit runs load six Grijjy files and 32 Delphi RTL source/include files,
with zero missing files. They need no maxTdb or TE5 application source. The
six files are `Grijjy.Bson.pas`, `Grijjy.Bson.IO.pas`, `Grijjy.BinaryCoding.pas`,
`Grijjy.DateUtils.pas`, `Grijjy.SysUtils.pas` and `Grijjy.inc`.

A narrowed control retains only that library directory and Delphi 12's
`source/rtl/common`, `source/rtl/sys` and `source/rtl/win` in explicit `/S`.
An explicit scratch PAL.INI disables automatic Delphi browsing/library path
imports. Its parser, namespace and report settings remain recorded. The
installed user configuration and all source files are preserved. The tool's
existing System.pas exclusion remains; none of the six Grijjy files is excluded.
PAL documents source-file input, `/S`, `/I` and `/T` in its
[PALCMD reference](https://www.peganza.com/PALHelp/how_to_use_palcmd_exe_.htm).

A relocated six-file copy with extracted analysis settings preserves the
38-file loaded closure, but all four runs after restoring the General settings
reported 59 typecasts. That copy has not yet reproduced the variation. Do not
present it as a portable reproduction of alternating results.

Evidence remains under `projects/.dak/DelphiAIKit/goal-current/`:
`t265-frozen-pal-strong-delta.json`, `t293-bson-unit-comparison.json`,
`t293-pal-controls.json`, `t293-output-crossover.json`,
`t293-fixed-config-results.json` and `t293-portable-final-results.json`.
Each record identifies commands, raw reports and input hashes. Raw XML confirms
the variation before DAK normalization. Fresh unit-wrapper outputs created local
baselines automatically; those diagnostic baselines are not approved replacements
for the historical T-212 project baselines and do not prove its policy gate.

The [9.21.5 release notes](https://www.peganza.com/history_pal.html) mention a
generics correction, but the evaluation control above still varies. T-293 and
T-212 remain open. The next external unblock is a vendor correction verified
against the retained source/configuration case; no supported workaround has
passed this proof. No mail was sent.
