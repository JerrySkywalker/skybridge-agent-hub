# Goal 034: Real Auto-Merge Rerun Docs Smoke

## Mission

Rerun the real SkyBridge AI auto-merge loop with a tiny docs-only change after the Docker workflow and Codex CLI automation fixes have landed on `main`.

## Required Change

Create or update `docs/dev/REAL_AUTO_MERGE_RERUN.md` with a concise note that records:

- this is the corrected real AI auto-merge rerun;
- the change is intentionally harmless and docs-only;
- GitHub Actions, CI Guardian and GitHub auto-merge are the merge gate;
- no production deployment, secret handling or privileged automation is part of this trial.

## Safety Boundaries

Do not:

- deploy to production;
- read, write or commit secrets;
- create, edit or commit `.env` files;
- change deploy scripts;
- mutate GitHub repository settings;
- mutate branch protection;
- run WSS remote execution;
- use privileged or self-hosted public PR runners;
- touch production server files or host-level configuration.

## Validation

Run the smallest relevant local validation for a docs-only change. Prefer:

```powershell
corepack pnpm check
```

If a faster focused check is used instead, explain why in the commit or final message.

## Done

- The docs note exists.
- The change is committed on an `ai/**` branch.
- Local validation passes or any failure is documented.
- The branch is pushed and a PR is opened for GitHub Actions and auto-merge gating.
