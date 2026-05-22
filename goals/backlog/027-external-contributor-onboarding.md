# Backlog: External Contributor Onboarding

## Background

PR #9 updates public-facing docs, but external contributor onboarding remains minimal.

## Tasks

- Add issue and PR templates.
- Add architecture tour for first-time contributors.
- Define labels for first-good-issues and safety-sensitive work.
- Add local setup smoke for contributors.
- Add review checklist covering tests, docs, risks and rollback notes.
- Add a short "what is implemented vs deferred" contributor guide for v0.9.
- Add guidance for reporting security-sensitive issues without posting secrets.

## Completion Criteria

- New contributor can run setup and a smoke test from docs.
- PR template captures validation and risk notes.
- Issue templates route bugs, features and security-sensitive reports.
- Templates do not ask contributors to paste tokens, logs with secrets or private agent output.
- The setup path works with `corepack pnpm check` and at least one smoke command.

## Safety Boundaries

- Do not expose private infrastructure details.
- Do not request secrets in templates.
- Do not weaken security reporting guidance.
- Do not encourage running production deploy scripts as a contributor setup step.

## Validation Commands

```powershell
corepack pnpm check
corepack pnpm smoke:operator-console
corepack pnpm smoke:release-dry-run
```

## CI/CD Impact

This should improve PR quality through templates and contributor docs. It should not add privileged CI behavior; any new template checks should remain text-only or standard repo validation.
