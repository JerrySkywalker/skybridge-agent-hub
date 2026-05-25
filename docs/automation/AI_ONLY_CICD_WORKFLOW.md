# AI-Only CI/CD Workflow

SkyBridge supports an AI-only development loop through GitHub safeguards, not through direct pushes to `main`.

## Flow

1. Codex or the controller creates an `ai/*` branch.
2. The branch is pushed to GitHub.
3. A draft PR is opened against `main`.
4. GitHub Actions runs required checks on GitHub-hosted runners.
5. The CI Guardian repairs failures on the AI branch.
6. GitHub branch protection and required checks decide whether the PR is mergeable.
7. GitHub auto-merge may merge the PR only when explicitly enabled and all required checks are green.

Production deployment remains a separate operator action. This workflow does not authorize server deployment, production secrets, `/opt` changes, OpenResty/Authelia/1Panel edits or Docker daemon changes.

## Branch Protection

Recommended manual GitHub settings for AI-only mode:

- require a pull request before merging;
- require status checks to pass before merging;
- require the public `PR CI`/project check workflow;
- require branches to be up to date if that fits repository policy;
- disable force pushes;
- enable auto-merge;
- do not require human review only when the repository intentionally chooses full AI-only mode.

Do not use privileged self-hosted runners for public PRs. Public PR checks must run without production secrets.

## Auto-Merge

Controller and CI Guardian auto-merge support is disabled by default. It requires:

- `github.autoMerge: true` in project config;
- an explicit CLI flag such as `-EnableAutoMerge`;
- green required checks;
- GitHub branch protection as the merge gate.

The scripts should call `gh pr merge --auto`, not push to `main`.

The auto-merge sweep and Hermes nightly sweep default to dry-run. Their job is to make the operator state visible: eligible PRs, blocked/high-risk files, drafts, non-`ai/**` branches, missing checks and pending checks. Real sweep mode is only for low-risk docs/goals PRs and must remain explicitly operator-gated.

## Bootstrap Notifications

Critical lifecycle phone notifications use `scripts/powershell/notify-bootstrap.ps1` directly. SkyBridge events are useful for dashboards, but phone notification must still work when the SkyBridge server is offline.

Nightly pilot summaries use non-urgent ntfy notifications only when `-Send` is explicit. Urgent notification is not used for ordinary tunnel loss, missing PRs or dry-run sweep results.

## Readiness Check

Run a read-only local readiness check:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\check-github-automation-readiness.ps1
```

The checker inspects local tools, repository metadata, workflows, open PR visibility and config defaults. It does not modify GitHub branch protection.
