# Contributing

This repository is open source and AI-agent friendly.

## Branch naming

```text
ai/<goal-id>-<slug>
feat/<topic>
fix/<topic>
docs/<topic>
```

## Pull request requirements

Every PR should include:

- Summary
- Tests
- Risk level
- Rollback notes
- Related goal file or issue

## Local development quickstart

```powershell
corepack pnpm install
corepack pnpm --filter @skybridge-agent-hub/server dev
corepack pnpm --filter @skybridge-agent-hub/web dev
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\seed-demo-events.ps1
```

Use `corepack pnpm smoke:product-console` for the fixture-backed dashboard smoke before sending UI/API changes for review.

## Issue and goal workflow

Use goals for autonomous work that spans multiple commits. Keep each phase reviewable, record validation commands in the PR, and create follow-up goals for blocked high-risk changes rather than widening scope.

## Architecture summary

Adapters normalize source events to `skybridge.agent_event.v1`. The server persists safe events, notifications, audit records and iterations. `packages/client` exposes typed API helpers. `packages/react-widgets`, `packages/web-components` and `apps/web` consume the same safe summaries.

## Risk labels

```text
risk:low
risk:medium
risk:high
needs-human-after-defense
ai-generated
yolo
```

## Public repository safety

Do not run untrusted public PR code on self-hosted runners.

External PRs should use GitHub-hosted runners without secrets.

PR-triggered workflows must not use production deploy keys, self-hosted runners or privileged Docker operations.
