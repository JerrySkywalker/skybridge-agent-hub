# Codex Adapter

Status: `dogfooding`

Role: `ExecutorAdapter` and telemetry adapter.

Codex is used during SkyBridge development for local implementation work, hook telemetry, exec JSONL telemetry and phone-notification dry-run smokes. Codex is not required by SkyBridge Core.

Core boundary:

- Codex CLI flags, hook file paths, JSONL logs and prompts stay in adapter packages and Codex docs.
- Codex payloads must be normalized and redacted before ingestion.
- Manual executor fixtures prove SkyBridge can track work without Codex.

Related docs:

- [../../codex/CODEX_LOCAL_INTEGRATION.md](../../codex/CODEX_LOCAL_INTEGRATION.md)
- [../../codex/HOOKS.md](../../codex/HOOKS.md)
