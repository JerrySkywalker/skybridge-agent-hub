# GitHub Automation Readiness

SkyBridge AI-only CI/CD must be enabled through GitHub safeguards, not by direct `main` pushes or script-owned branch protection changes.

Run the read-only checker:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\check-github-automation-readiness.ps1
```

Machine-readable output:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\check-github-automation-readiness.ps1 -Json
```

Smoke validation:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-github-automation-readiness.ps1
```

## Report Statuses

- `ready`: the local or remote check passed.
- `warning`: the checker could not inspect something optional or degraded, such as missing `gh` auth on a local machine.
- `blocker`: a required local capability is missing, such as Git, Corepack or local workflow files.
- `manual_setup_required`: GitHub settings must be reviewed by a human operator.

The checker always reports:

- whether it mutated remote settings: expected `false`;
- whether it mutated branch protection: expected `false`;
- local tool readiness;
- current repository metadata when `gh` is available;
- default branch metadata when `gh repo view` exposes it;
- open PR visibility;
- local and remote workflow availability;
- latest workflow results when `gh run list` is available;
- auto-merge availability when GitHub exposes it.

## Manual Settings Before AI-Only Auto-Merge

Before enabling `github.autoMerge` in project config or passing an explicit auto-merge flag, configure GitHub manually:

- require pull requests before merging into the base branch;
- require the project check workflow, currently `Project check`;
- decide whether branches must be up to date before merging;
- disable force pushes;
- enable repository auto-merge;
- do not use privileged self-hosted runners for public PRs;
- keep production secrets out of public PR workflows.

This repository's scripts do not modify branch protection or enable auto-merge by default.
