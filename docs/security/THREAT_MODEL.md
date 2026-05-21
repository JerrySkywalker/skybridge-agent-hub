# SkyBridge Threat Model

SkyBridge collects agent telemetry from local and remote-capable workflows. The main security goal is useful observability without leaking secrets or enabling silent remote control.

## Protected Assets

- API keys, tokens, cookies, SSH keys and private keys.
- Raw prompts, patches, stdout, stderr and tool result bodies.
- Private local paths and repository contents.
- Production deployment configuration and server credentials.
- Operator approval decisions and audit trails.

## Primary Risks

- Public CI running untrusted pull request code with privileged runners.
- Codex hooks accidentally forwarding prompts, command output or patch bodies.
- Notification providers receiving secrets in message text.
- Remote sidecars becoming an unaudited command channel.
- Local spool files retaining sensitive data.
- Deployment dry-runs printing env values.

## Controls

- All adapters must emit `skybridge.agent_event.v1` and redact before ingestion.
- Shared redaction rules live at `packages/event-schema/src/redaction-rules.json`; TypeScript and PowerShell consumers must report that source path in telemetry metadata when the JSON file is available.
- Event payloads over 128 KiB are rejected by the server.
- Provider status endpoints report configuration without exposing credential values.
- Sidecar remote command execution is not implemented; remote control is feature-flagged/design-only.
- Public workflows use GitHub-hosted runners and no production secrets.

## Redaction Policy Versioning

The current redaction policy version identifier is the canonical rule source path, `packages/event-schema/src/redaction-rules.json`. Changes to that JSON file are policy changes and should be reviewed with fixture parity coverage for both TypeScript and PowerShell consumers. If a local hook cannot read the JSON file, it may use the embedded fail-open fallback, but emitted telemetry should mark the policy source as `fallback` so audits can distinguish degraded local execution from the canonical shared policy.

## Follow-Up Work

- Add a durable encrypted spool option for sidecars.
- Add an append-only audit table for operator actions and approvals.
- Add browser visual QA for release candidates.
