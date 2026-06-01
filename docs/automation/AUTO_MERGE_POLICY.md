# Auto-Merge Policy

SkyBridge auto-merge mode is a guarded low-risk workflow. It is disabled by default and must stay disabled unless an operator explicitly chooses to run a sweep or Guardian command with auto-merge enabled.

The shareable example policy is `config/auto-merge-policy.example.json`.

## Default Policy

The default policy allows only low-risk documentation and goal queue files:

- `docs/**`
- `goals/ready/**`
- `goals/backlog/**`
- `goals/done/**`
- top-level project docs such as `README.md`, `CHANGELOG.md`, `ROADMAP.md` and `CONTRIBUTING.md`

It blocks paths that can change CI, deployment, secrets or production behavior:

- `.env` and `.env.*` files at any depth;
- secret, credential and token-like filenames;
- `.github/workflows/**`;
- `deploy/**`;
- production config paths;
- OpenResty, Authelia, 1Panel and Docker daemon config paths.

Required checks are:

- `AI branch validation`
- `Project check`
- `Docker build (server)`
- `Docker build (web)`

## Eligibility Rules

A PR is eligible only when all of these are true:

- the source branch starts with an allowed prefix such as `ai/`;
- the PR is not draft;
- all changed files are inside allowed paths;
- no changed file matches a blocked path;
- required checks are present;
- required checks are green, or a command explicitly allows GitHub auto-merge to wait for pending required checks.

The local classifier reports:

- `low`: all files are allowed and no blocked patterns matched;
- `needs_review`: no blocked file matched, but one or more files are outside allowed paths;
- `blocked`: one or more blocked patterns matched.

Only `low` is eligible for unattended auto-merge.

## CI Guardian And Finalizer Behavior

`skybridge-ci-guardian.ps1` and `skybridge-pr-finalize.ps1` use the same conservative operating model:

- pending checks are reported as pending and may be watched only for a bounded timeout;
- transient-looking failures such as checkout, setup, cache, network, rate-limit or timeout failures may be retried once;
- real CI failures block auto-merge and stay available for human or bounded repair review;
- low-risk draft child PRs may be marked ready only when changed files are within the expected or allowed path set;
- high-risk draft PRs, unsafe paths, unknown CI, cancelled checks and repeated transient failures stay manual;
- merged child PR evidence repair records safe metadata such as PR URL, changed files, CI status and merge commit, not raw command output or logs.

The finalizer is dry-run unless `-Apply` is supplied. Evidence repair also requires `-AllowEvidenceRepair` and `-Apply`.

## Commands

Validate the policy classifier:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-auto-merge-policy.ps1
```

Validate focused finalizer decisions:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-pr-finalizer-pending-wait.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-pr-finalizer-transient-retry.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-pr-finalizer-draft-ready.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-pr-finalizer-safe-merge.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-pr-finalizer-blocks-unsafe-files.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-pr-finalizer-evidence-repair.ps1
```

Run the CI Guardian without auto-merge:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-ci-guardian.ps1 -CurrentBranch
```

Run the CI Guardian with explicit auto-merge eligibility gates:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-ci-guardian.ps1 `
  -CurrentBranch `
  -EnableAutoMerge `
  -PolicyFile .\config\auto-merge-policy.example.json
```

Dry-run a sweep across open PRs:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-auto-merge-sweep.ps1 `
  -PolicyFile .\config\auto-merge-policy.example.json
```

Run a real sweep that enables GitHub auto-merge for eligible PRs only:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-auto-merge-sweep.ps1 `
  -PolicyFile .\config\auto-merge-policy.example.json `
  -EnableAutoMerge
```

The sweep is dry-run by default. `-EnableAutoMerge` is the explicit mutation flag; it calls `gh pr merge --auto --squash` only for PRs that pass the local policy classifier.

## Safety Notes

This policy does not mutate GitHub settings, branch protection, production files, secrets or deployment configuration. GitHub repository auto-merge and branch protection are manual repository settings.

If the policy blocks a PR, the correct behavior is to notify and leave the PR for human review. Do not widen `allowed_paths` just to make a high-risk PR pass unattended.
