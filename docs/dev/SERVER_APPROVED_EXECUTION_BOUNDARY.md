# Server-approved Execution Boundary

The Goal 225 boundary is intentionally narrower than queue execution.

- Only one local worker is eligible.
- Only one workunit, one task, one claim, one Codex execution, and one task PR are allowed.
- The workunit type is fixed to `docs/local-smoke`.
- The prompt is constrained to one docs file and forbids tests, package managers, git, gh, config changes, and secret access.
- Changed files must stay within `README.md` or `docs/**`, with a strong preference for exactly `docs/server-approved-workunit-225.md`.
- Resident polling remains preview-only and cannot claim tasks or execute work by itself.
- Remote execution and arbitrary command dispatch remain disabled.
- Generic bounded queue apply remains disabled.
- `token_printed=false`.
