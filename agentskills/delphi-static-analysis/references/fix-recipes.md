# Fix Recipes (FixInsight + Pascal Analyzer)

This file is a **conservative** cookbook: for a given warning kind/section, it outlines safe fixes we can apply in small steps, plus what we should verify (build/tests + re-run analysis).

Principles:

- Prefer **small, local** changes we can prove by compile + tests.
- When the finding points at **ownership/lifetime**, follow our rules in `conventions.md` (especially **Managed Types** and **AutoFree.GC()**).
- If a finding is a **metric/code smell** (complexity/too many params), treat it as refactor pressure, not a quick auto-fix: add tests first, then refactor in PR-sized chunks.

## Workflow (repeatable)

1. Pick 3–5 high-signal items from `.dak/<ProjectName>/triage.md`.
2. Fix one item (or a tight cluster in one unit).
3. Build + run the relevant DUnitX tests.
4. Re-run static analysis; confirm the finding disappears and deltas don’t regress.

## FixInsight Recipes

FixInsight codes are useful for grouping, but the **message text is the source of truth**. Always read the exact message line in:

- `.dak/<ProjectName>/fixinsight/fixinsight.txt`
- `.dak/<ProjectName>/fixinsight/fi-findings.md`

### Resource management / leaks

Common signal: “resource leak”, “might not be freed”, “lost reference”.

Safe fixes:

- Prefer `try..finally` for non-local ownership (allocated outside the current scope or stored globally).
- For local `TObject` lifetime, prefer **AutoFree.GC()** using a scope holder:
  - Use one `TGarbos` per routine/block (typically named `g`).
  - Register immediately after creation/assignment.
  - Never use “bare” `GC(...)` without a holder (see `conventions.md` → **AutoFree.GC()**).

Verify:

- Build cleanly.
- Add/adjust a unit test that exercises the allocation path and runs it under a small loop (to catch “sometimes” leaks).
- Re-run analysis; confirm the leak finding is gone.

### Empty `try..finally` / `try..except`

Common signal: “empty FINALLY section”, “empty EXCEPT section”.

Safe fixes:

- If conditional compilation can remove the only statement: add a harmless explicit statement under the same define (e.g. a comment does not count; prefer a real statement).
- If the block is intentionally empty: reconsider if it should exist at all; otherwise add minimal logging/trace (but keep user-visible strings out of `resourcestring`; see `conventions.md` → Localization).

Verify:

- Build + run tests for the code path that enters the block.
- Re-run analysis; confirm the warning disappears.

### Complexity / “too long” / “too many parameters”

These are not correctness bugs, but they predict bugs.

Safe process (not a one-shot refactor):

- Add tests around the method first (cover edge cases and error paths).
- Extract **private** helpers (avoid changing public/protected signatures; see `AGENTS.md` refactoring guardrail).
- Keep behavior identical; refactor in slices that are easy to review.

Verify:

- Tests pass before/after.
- Re-run analysis and confirm the metric warning count drops (or at least doesn’t worsen).

## Pascal Analyzer Recipes

PAL sections can be noisy. Prefer fixing “strong warnings” first, then the highest-confidence warnings.

### “Local variables that are referenced before they are set”

This often indicates an uninitialized local being read on some path.

Safe fixes:

- Initialize locals explicitly at declaration (`lX := 0;`, `lS := '';`, `lObj := nil;`).
- For records, use `Default(T)` / `Initialize` (do **not** use `FillChar` on managed types; see `conventions.md` → **Managed Types**).
- For `out` params: avoid “pre-setting” unless the callee expects `var` instead of `out`.

Verify:

- Add a test that exercises the path PAL flagged (often an early-exit/exception path).
- Re-run PAL; confirm the section count drops and no new strong warnings appear.

### “Possible nil access” / “possible nil dereference”

Safe fixes:

- Add explicit guards (`if lObj = nil then Exit(False);`) at the point of use.
- Consider narrowing lifetimes: keep object creation and use close together.
- If an interface-backed lifetime is involved, re-check our `AutoFree.GC()` holder rules (see `conventions.md`).

Verify:

- Add a test that executes the nil path (and a non-nil path) to lock in behavior.
- Re-run analysis; confirm the warning disappears.

### “Set before passed as out parameter”

Delphi `out` params are **zero-initialized before call**; setting them beforehand is usually dead code.

Safe fixes:

- Remove the redundant assignment.
- If the callee requires an input value, the signature should be `var` (not `out`) — treat that as a design change and do it only with tests + review.

Verify:

- Build + run tests that cover the callsite.
- Re-run analysis; confirm the warning disappears.

### “Possible bad typecast (consider using \"as\" for objects)”

Safe fixes:

- Prefer `as` for class casts and handle `EInvalidCast` where appropriate.
- If performance matters and we must use hard casts, add a guard (`if lObj is TFoo then ...`) and keep the unsafe cast local.

Verify:

- Add tests for both cast-success and cast-failure paths.
- Re-run analysis; confirm the strong warning disappears.

### “Generic interface has GUID”

This usually matters for COM/QueryInterface scenarios.

Safe guidance:

- Avoid GUIDs on generic interfaces unless we have a concrete interop requirement.
- If this is public API, treat it as a design task (tests + migration plan) rather than a drive-by change.

Verify:

- Compile + run tests.
- If COM is involved, add a smoke test that exercises `Supports`/`QueryInterface`.

## Suppression (last resort)

If we must suppress, do it **locally** and leave a short reason:

- Single line: `//PALOFF reason`
- Specific sections: `//PALOFF STWA;WARN1;OPTI8`

Prefer fixing root causes over suppression; suppress only when we understand and accept the behavior.
