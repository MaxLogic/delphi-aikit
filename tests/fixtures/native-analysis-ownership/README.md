# Ownership row reference

Generated with the retained Python postprocess.py development reference.

Reference SHA-256: D76C7B85E45E63825F46BB52D45A32DD2D62C159522F7A3C048D7FF28FC0F09D
Raw corpus SHA-256: 456509E52B49EFC71A257C710CBEA195F1A43F8BABB65004694A9EA7F2398519

The corpus contains seven FI and seven PAL rows, including external/local
paths, ambiguous and missing sources, empty paths and nested extension fields.
The reference produced identical complete rows on three annotation passes.

Only the isolated absolute root was replaced: @ROOT_WIN@ substitutes its
JSON-escaped Windows spelling; @ROOT_POSIX@ substitutes its forward-slash
spelling. No finding, field, row order or diagnostic was normalized.

Retained generation evidence:
projects/.dak/DelphiAIKit/native-analysis-migration/t324/complete-row-reference-run.json.
The native test creates equivalent local files and compares complete arrays
after each of three passes. Python is not required to run this test.

The extended corpus adds saved policy-only filename resolution, an absolute
external DCCReference, mixed-case relative input and JSON-null paths. It
contains 20 rows; all are stable across three reference annotation passes.
Extended raw corpus SHA-256: 5A1CBFD383C30E83B88DCC0E8348FDA6996ADDF48731B67ED0BF32B45C2D24D4
Its optional files object records additional fixture files before context creation.
Generation receipt: t324/extended-row-reference-run.json under the evidence root.
