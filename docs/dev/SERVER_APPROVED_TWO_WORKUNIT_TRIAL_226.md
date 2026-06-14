# Server-approved Two-workunit Trial 226

Trial id: `server-approved-two-workunit-trial-226`.

- Workunit A writes `docs/server-approved-two-workunit-226-a.md`.
- Workunit B writes `docs/server-approved-two-workunit-226-b.md`.
- Workunit B is blocked until Workunit A is merged and finalized.
- Each workunit allows exactly one Codex execution and one task PR.
- Repo mutation is serialized with `max_parallel_repo_mutations=1`.
- Server approval, pairing, durable approval, resident polling, resource, failure budget, evidence retention, audit/redaction and safe export gates are required.
- Trusted-docs scoped merge may merge only the exact approved docs-only task PR.
- `remote_execution_enabled=false`.
- `arbitrary_command_enabled=false`.
- `generic_bounded_queue_apply_enabled=false`.
- `token_printed=false`.

Controller:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-server-approved-two-workunit-trial.ps1 -Command status -Json
```
