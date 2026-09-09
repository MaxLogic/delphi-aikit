# Vendor analyzer retry, 2026-09-08

The three PAL reports map to T-232, T-233 and T-234. The FixInsight packed-include reproducer belongs to T-225. All four remain open after fresh, serialized runs against unchanged isolated fixtures.

| Task | Installed analyzer result | Additional control |
| --- | --- | --- |
| T-232, `Inc/Dec(Int64, Int64)` | PAL 9.21.4.0 reports all four disputed calls and the deliberate narrowing control on Win32 and Win64. | Evaluation 9.21.5.0 still exposes disputed rows; its report limits the displayed details. |
| T-233, record-field writes and missing `const` | PAL 9.21.4.0 reports the three disputed parameters plus the pointer/read-only controls on both targets. | Evaluation 9.21.5.0 still exposes disputed rows. Compiling the `CONST_VARIANT` fails with E2064 and E2197 on both targets, confirming that the proposed `const` changes are invalid. |
| T-234, object-field receiver references | PAL 9.21.4.0 reports both disputed receiver variables and the unused control on both targets. | Evaluation 9.21.5.0 reports zero rows, but explicitly omits identifiers beginning with J, K or L. That hides both `lState` and `lUnused`; it cannot establish a fix. |
| T-225, include-based `packed class` | FixInsightCL Pro 2026.01beta fails at line 9, column 34 with `InvalidStructuredType found class` on both targets. | The public archive supplies 2023.12 and fails identically. Both executables accept the equivalent direct `packed class` declaration. |

The six normal PAL fixture builds and four FixInsight control builds passed with zero errors and warnings. All six PAL runtime checks exited successfully. Both deliberately invalid `CONST_VARIANT` builds failed as expected. The source manifests still match. These upstream reproductions received no new exclusions; the PAL raw status files retain the analyzer's existing System/RTL exclusions and show all reproducer source files loaded.

The approved routine policy excludes third-party libraries while retaining our maintained shared libraries. A fresh ownership review found that resolved external and nested maintained sources still need the T-265 policy correction before T-212 can be certified. Neither routine exclusions nor ownership classification prove a vendor parser is corrected. No vendor or external project source was edited.

PAL's [published history](https://www.peganza.com/history_pal.html) lists 9.21.5, but the evaluation build cannot certify the hidden receiver findings. The smallest next step is a licensed or vendor-supplied build that passes the same raw reproductions without evaluation omissions. FixInsight likewise needs a vendor build that passes the include-based fixture.

Exact commands, durations, binary versions and hashes, raw XML excerpts, control classifications and source hashes are retained under `projects/.dak/DelphiAIKit/goal-current/`:

- `vendor-pal-runs.json` and `vendor-pal-fresh-review.json`
- `vendor-fixinsight-runs.json` and `vendor-fixinsight-source-proof.json`
- `vendor-repro/*/.dak/*/retry-20260908/`

The separate real DelphiLSP retry is recorded in [lsp-capability-probe.md](lsp-capability-probe.md).


## Availability check, 2026-09-09

Installed PAL remains 9.21.4.0; its executable hash matches the retained retry evidence.

[Peganza's current history](https://peganza.com/history_pal.html) still lists 9.21.5, dated August 11, 2026. [TMS's FixInsight history](https://www.tmssoftware.com/site/fixinsight.asp?s=history) lists 2026.01. Neither entry explicitly documents correction of these retained reproductions. This refresh checked published version availability only; the raw native reproduction results above remain dated September 8. No vendor source or analyzer installation was changed.

Evidence: `projects/.dak/DelphiAIKit/goal-current/vendor-availability-20260909.json` and `vendor-installed-metadata-20260909.json`. The upstream tasks and three active PAL reports remain open.
