# Backlog: Production Deployment Hardening

## Background

PR #9 adds self-hosting docs and dry-run smoke, but intentionally avoids real deployment and production server config.

## Tasks

- Add manual deployment gates and operator checklist.
- Verify backup and rollback scripts against a local disposable environment.
- Document secret-management integration outside Git.
- Define trusted runner policy for private deployment jobs.
- Add staging smoke that does not mutate production.

## Completion Criteria

- Backup/rollback dry-runs are reproducible.
- Deployment docs identify all required operator inputs.
- No public PR workflow receives production secrets or self-hosted runner access.

## Safety Boundaries

- Do not touch `/opt/skybridge-agent-hub`.
- Do not alter real OpenResty, Authelia, 1Panel or Docker daemon config.
- Do not commit `.env` or secrets.
- Do not deploy to a real host.
