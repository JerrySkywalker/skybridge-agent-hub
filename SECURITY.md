# Security Policy

## Secrets

Never commit:

- `.env`
- API keys
- GitHub tokens
- ntfy passwords
- SSH keys
- production server credentials
- cloud provider credentials

## Agent Safety

The default agent mode is autonomous but bounded:

- allowed: repository edits, tests, docs, local Docker dev/test;
- denied: production secrets, destructive cleanup, force-push main, server root config.

## Codex Hook Redaction

Codex hooks and exec adapters must normalize to `skybridge.agent_event.v1` before ingestion and must not upload full prompts, commands, stdout, stderr, patches or Codex JSONL logs by default.

The Codex hook path redacts or bounds:

- `Authorization` and bearer token values;
- API-key, token, password, secret, cookie and credential fields;
- long command and output text;
- unknown nested payloads beyond depth/key limits;
- patch and content bodies, represented by presence and length metadata only.

Offline spool files contain normalized redacted events, not raw hook stdin. Treat spool files as local operator telemetry and delete them when they are no longer useful.

## Reporting

For a personal project, open a private issue or contact the maintainer directly.
