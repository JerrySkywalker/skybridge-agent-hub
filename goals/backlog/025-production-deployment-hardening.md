# Backlog: Production Deployment Hardening

## Background

PR #9 adds self-hosting docs and dry-run smoke, but intentionally avoids real deployment and production server config.

## Tasks

- Add manual deployment gates and operator checklist.
- Verify backup and rollback scripts against a local disposable environment.
- Document secret-management integration outside Git.
- Define trusted runner policy for private deployment jobs.
- Add staging smoke that does not mutate production.
- Add a preflight that confirms target host, image tag, backup path and rollback plan before any deploy.
- Document which commands are dry-run safe and which require explicit operator approval.

## Completion Criteria

- Backup/rollback dry-runs are reproducible.
- Deployment docs identify all required operator inputs.
- No public PR workflow receives production secrets or self-hosted runner access.
- Real deployment remains manual and gated after CI passes.
- Rollback verification uses disposable local or staging data, not production data.

## Safety Boundaries

- Do not touch `/opt/skybridge-agent-hub`.
- Do not alter real OpenResty, Authelia, 1Panel or Docker daemon config.
- Do not commit `.env` or secrets.
- Do not deploy to a real host.
- Do not add public CI jobs that can mutate a server.
- Do not print rendered secret values in dry-run output.

## Validation Commands

```powershell
corepack pnpm smoke:release-dry-run
corepack pnpm smoke:self-hosting-dry-run
docker compose -f deploy/docker-compose.prod.yml config
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\validate-powershell.ps1
```

## CI/CD Impact

This may add stricter dry-run validation and manually triggered trusted deployment workflows. Public PR and AI-branch CI must remain read-only and secret-free.
