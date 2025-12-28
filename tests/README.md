# Tests

Manual checks

- Run DelphiConfigResolver against `tests\fixtures\Sample.dproj` with `--platform Win32 --config Debug` and verify:
  - Defines contain OPTSET_WIN32, OPTSET_BASE, BASE, DEBUG, WIN32CFG (order may vary by overrides).
  - Unit search path starts with `tests\fixtures\src` and includes `tests\fixtures\optset` before IDE library path.
  - Unit scopes include System and Vcl.
- Repeat with `--platform Win64` to confirm the Win32-only optset define is absent.
