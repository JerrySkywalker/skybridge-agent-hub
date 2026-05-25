# API Overview

SkyBridge APIs are local-first and return safe derived metadata for an agent-agnostic control plane. They must not expose raw prompts, patches, stdout, stderr, tokens, cookies or production secrets.

## Product Summary APIs

- `GET /v1/summary`: top-level health, counts, latest states, recent failures and recommended action.
- `GET /v1/projects`: local project summaries derived from runs and iterations.
- `GET /v1/iterations/summary`: iteration counts, latest iteration, repair attempts and blocked reasons.
- `GET /v1/prs/summary`: local PR/CI summary derived from iteration records and safe events.
- `GET /v1/notifications/summary`: notification counts, provider state and bootstrap fallback status.
- `GET /v1/hermes/summary`: optional private Hermes adapter tunnel/API/capability status from local telemetry.
- `GET /v1/automerge/summary`: dry-run default, eligibility decisions, blocked reasons and local merged history when available.
- `GET /v1/adapters`: neutral planner, executor, SCM/CI, notification and runtime provider capability registry.

## Core APIs

- `GET /v1/health`
- `POST /v1/events`
- `GET /v1/events`
- `GET /v1/runs`
- `GET /v1/runs/:runId`
- `GET /v1/iterations`
- `GET /v1/iterations/:iterationId`
- `GET /v1/notifications`
- `GET /v1/audit`
- `GET /v1/sources`
- `GET /v1/adapters`
- `GET /v1/nodes`
- `GET /v1/metrics`
- `GET /v1/approvals`
- `GET /v1/stream`

## Stability Notes

The product summary APIs are intended for dashboard and embed consumption. Field names use snake_case to match existing server responses. Derived PR, Hermes and auto-merge summaries are local/fixture-backed unless future integrations explicitly persist richer state. Hermes, Codex, GitHub and ntfy remain adapters/providers, not core API dependencies.

Remote execution and production deployment APIs are intentionally absent.
