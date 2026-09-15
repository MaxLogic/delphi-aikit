# Native analysis projection references

`cases.json` contains complete ordered findings from the retained Python
projection implementation, processed twice. The corpus covers masks, rule
identity, version aliases, policy precedence, repeated processing, scalar
conversion and XML catalog names. Tests compare complete objects and errors.

Reference `postprocess.py` SHA-256:
`D76C7B85E45E63825F46BB52D45A32DD2D62C159522F7A3C048D7FF28FC0F09D`.
Generation receipts and the unchanged reference are retained under the local
`projects/.dak/DelphiAIKit/native-analysis-migration/` evidence directory.

`raw-numbers.json` retains exact input lines, untouched Python output, and
separate native expectations. The native expectations preserve the original
number token as required by T-335; derived annotations come from the reference.
The `proposed_native_passes` name records their origin and does not claim test
acceptance. T-341 owns numeric conversion proof; T-340 owns Unicode parity.

These are synthetic fixtures. They contain no production source or private
correspondence. Passing this corpus alone does not prove complete replay,
performance, or delivery without Python.
