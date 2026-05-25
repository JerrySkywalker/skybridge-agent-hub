# Dashboard Quickstart

Use this path for a safe local product demo of the agent-agnostic control plane. It uses a temporary or local SQLite database, fake events and no production services.

## Start The Console

```powershell
corepack pnpm install
corepack pnpm --filter @skybridge-agent-hub/server dev
corepack pnpm --filter @skybridge-agent-hub/web dev
```

Open:

```text
http://127.0.0.1:3000/#/overview
```

## Seed Product State

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\seed-demo-events.ps1
```

The seeded state includes Hermes and rule-based planner examples, Codex and manual executor examples, GitHub and generic SCM/CI provider examples, ntfy and generic notification provider examples, PR/CI records, an auto-merge dry-run, failed CI, notification events, audit records and a blocked high-risk PR.

## Smoke Validate

```powershell
corepack pnpm smoke:product-console
```

The smoke starts a temporary SQLite-backed server, seeds demo data, queries product summary APIs and builds the web console. It does not open a browser by default.

## Routes

- `#/overview`
- `#/runs`
- `#/iterations`
- `#/pr-ci`
- `#/notifications`
- `#/hermes` optional Hermes adapter detail
- `#/sources`
- `#/settings`
- `#/embed/compact`
