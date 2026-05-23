# Reusable Project Integration

SkyBridge's Agent CI/CD Control Plane can supervise repositories beyond `skybridge-agent-hub` when they follow the same safe boundaries.

## Adoption Steps

1. Copy a project config example from `config/project.*.example.json`.
2. Set `project.id`, `project.repository`, `project.localPath`, `baseBranch` and `branchPrefix`.
3. Choose a goal queue path, usually `goals/ready`.
4. Define local checks that are safe to run unattended.
5. Configure GitHub required checks and branch protection manually.
6. Keep `github.autoMerge` false until branch protection is proven.
7. Configure `NTFY_TOPIC_URL` or `NTFY_URL` plus `NTFY_TOPIC` for bootstrap notifications.
8. Point Hermes at `skybridge-hermes-supervisor.ps1` instead of teaching it repo-specific paths.
9. Enable SkyBridge telemetry after the local server is available.

## Required Repository Shape

Minimum:

- Git repository with a remote;
- GitHub CLI access for PR operations;
- Codex CLI for implementation work;
- one deterministic local check command;
- a goal file or queue;
- no required production secrets for CI.

Recommended:

- `AGENTS.md` with safety boundaries;
- `README.md` and development docs;
- GitHub Actions workflow for PR checks;
- protected base branch;
- AI branch prefix such as `ai/`;
- fixture-only smoke checks for local validation.

## Command Pattern

One dry-run iteration:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-iterate.ps1 `
  -ConfigFile .\config\project.generic-node-app.example.json `
  -GoalFile .\goals\ready\001-example.md `
  -DryRun `
  -One `
  -NoAutoMerge
```

CI Guardian dry run:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-ci-guardian.ps1 `
  -PR 123 `
  -DryRun `
  -MaxRepairAttempts 3
```

Hermes supervisor dry run:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-hermes-supervisor.ps1 `
  -Mode StartNext `
  -DryRun `
  -ConfigFile .\config\project.generic-node-app.example.json
```

## Boundaries

Reusable integration does not authorize production deployment, secret mutation, privileged public PR runners, branch protection mutation or destructive remote command execution.

SkyBridge events are observability metadata. Bootstrap direct notifications remain the phone fallback for the supervisor until SkyBridge Notification Center is mature enough to self-host critical alerts.
