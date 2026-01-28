# Pascal Analyzer XML findings normalization

This spec slice documents which PAL XML reports are actionable findings, and how we normalize them into
`pal-findings.md` (and optional `pal-hotspots.md` / `pal-findings.jsonl`).

## Scope

We only parse **finding-like** PAL XML reports:

- `Warnings.xml`
- `Strong Warnings.xml`
- `Optimization.xml`
- `Exception.xml` (call tree entries)

Metrics-only reports remain **unchanged** and are only used for hotspots:

- `Complexity.xml`
- `Module Totals.xml`

## PAL XML patterns (observed)

### Shared structure

Each report is a `<report>` with one or more `<section name="...">` nodes. We read sections in file order.

### Warnings / Strong Warnings / Optimization

Patterns inside a section:

1. **Item with id/kind + locmod**

```xml
<item>
  <id>ParseList</id>
  <kind>Func, Interfaced</kind>
  <locmod>Dcr.ReportPostProcess (18)</locmod>
</item>
```

- `locmod` may include a line number in parentheses; we parse it when present.

2. **Item with multiple locs**

```xml
<item>
  <loc>
    <kind>Read+Set</kind>
    <locmod>Dcr.FixInsightRunner</locmod>
    <locline>106</locline>
  </loc>
</item>
```

- `locline` is the authoritative line when present.

3. **Name + loc pairs (flat)**

```xml
<name>Dcr.ReportPostProcess.TryNormalizeRuleId</name>
<loc>
  <locmod>Dcr.ReportPostProcess</locmod>
  <locline>467</locline>
</loc>
```

4. **Standalone loc**

```xml
<loc>
  <locmod>Dcr.Cli</locmod>
  <locline>337</locline>
</loc>
```

### Exception report

`Exception.xml` exposes a call tree:

```xml
<section name="Exception Call Tree">
  <branch index="1">
    <called_by>
      <name>IsHelpRequested</name>
      <locmod>Dcr.Cli</locmod>
      <locline>16</locline>
      <called_by>...</called_by>
    </called_by>
  </branch>
</section>
```

We emit a finding for each `<called_by>` node (flattened tree).

## Normalized outputs

### `pal-findings.md`

One line per finding, no header:

```
<severity> | <report> | <section> | <module>:<line> | <message>
```

Rules:

- `severity` is one of: `warning`, `strong-warning`, `optimization`, `exception`
- `report` is the source XML filename (e.g., `Warnings.xml`)
- `section` is the `<section name="...">`
- `module:line` is derived from `<locmod>` + `<locline>`
  - If `<locline>` is missing, parse a trailing `(NNN)` from `<locmod>`
  - If no line exists, use `0`
- `message` uses the first available of:
  - `<id>`
  - `<name>`
  - `<kind>`
  - `<loc>/<kind>`

### `pal-findings.jsonl` (optional)

One JSON object per line. Each object includes at least:

```json
{
  "severity": "warning",
  "report": "Warnings.xml",
  "section": "Local variables that are referenced before they are set",
  "module": "Dcr.FixInsightRunner",
  "line": 106,
  "message": "Read+Set",
  "id": "ParseList",
  "kind": "Func, Interfaced"
}
```

The `id` and `kind` fields are only present when available.

### `pal-hotspots.md` (optional)

Derived from `Complexity.xml` and `Module Totals.xml`.

- **Routines by decision points**: Top 20 routines by `dp` (decision points)
- **Modules by decision points**: Top 20 modules by `dp`
- **Modules by lines**: Top 20 modules by `lines` from `Module Totals.xml`

Format:

```
dp=<value> | loc=<lines_of_code> | <name>
lines=<value> | <name>
```

## Location of outputs

When PALCMD is run via `--run-pascal-analyzer`, outputs are written next to the PAL output root (the folder
containing the PAL XML reports, usually `--pa-output`).

