---
name: delphi-build
description: Build Delphi projects via DelphiAIKit and optionally run DFM validation with `--dfmcheck`.
---

# Delphi Build

Canonical command:

```bash
"$DAK_EXE" build --project "<path-to-project.dproj>" --delphi 23.0 --platform Win32 --config Release --ai
```

Build plus DFM validation:

```bash
"$DAK_EXE" build --project "<path-to-project.dproj>" --delphi 23.0 --platform Win32 --config Release --dfmcheck --ai
```

`--dfmcheck` is a presence flag. If present, build runs the DFM streaming validation step after a successful compile.

For full build skill details used in this repo, see:
- `agentskill/delphi-build/SKILL.md`
