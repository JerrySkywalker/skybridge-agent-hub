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

## CI/CD Threat Model

SkyBridge is intended to be developed in a public repository. CI assumes pull request code may be untrusted.

Public PR and AI-branch workflows must:

- run on GitHub-hosted runners;
- require no production secrets;
- avoid self-hosted deployment runners;
- avoid SSH, cloud credentials or server mutation;
- upload only sanitized smoke logs and generated summaries.

Release and image-publish workflows may use the repository `GITHUB_TOKEN` for GHCR publishing. They must not require external registry passwords or production deploy tokens.

## Public PR Runner Policy

Privileged self-hosted runners are forbidden for public PR triggers. If a self-hosted runner is added later, it must be isolated behind manual approval and trusted refs only.

## Deploy Token Policy

Deployment credentials, SSH keys, cloud tokens and ntfy tokens must be stored outside the repository. Public workflows must not print, archive or echo these values. Staging automation in this repository is dry-run only unless a future explicitly authorized goal changes that boundary.

## Artifact And Redaction Policy

CI artifacts may include:

- smoke script logs that use temporary databases and fake fixtures;
- release dry-run summaries;
- compose render logs with env values omitted.

CI artifacts must not include:

- `.env` files;
- `.data` databases;
- `.agent/runs` logs;
- tokens, cookies or SSH keys;
- full agent prompts, command output, patches or raw Codex JSONL.
