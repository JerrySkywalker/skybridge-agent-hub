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

## Commands

Validate the policy classifier:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-auto-merge-policy.ps1
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

## Safety Notes

This policy does not mutate GitHub settings, branch protection, production files, secrets or deployment configuration. GitHub repository auto-merge and branch protection are manual repository settings.

If the policy blocks a PR, the correct behavior is to notify and leave the PR for human review. Do not widen `allowed_paths` just to make a high-risk PR pass unattended.
