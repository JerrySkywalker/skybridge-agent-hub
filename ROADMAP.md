# Roadmap

## v0.9

- Multi-agent telemetry across Codex, OpenCode, Hermes and custom adapters.
- Local sidecar node registry foundation.
- Notification provider matrix and routing rules.
- Security hardening, shared redaction rules and threat model.
- Demo dataset, dogfooding smoke and release candidate checklist.
- Agent CI/CD Control Plane foundation for bounded iteration, PR CI repair, Hermes supervision and bootstrap notifications.

Status: release-candidate foundation after PR #9. Codex, server, SQLite, notification, CI/CD and smoke foundations are implemented and locally validated. OpenCode/Hermes runtime compatibility, real browser visual QA, WSS remote control, mobile readiness, docs publishing and production deployment hardening remain follow-up work.

## v1.0

- Real WSS sidecar connection with scoped auth.
- Durable approval queue and audit log.
- Browser visual QA for dashboard and embeds.
- Public docs site.
- Production deployment hardening with manual operator gates.
- External contributor onboarding.
- Durable iteration persistence beyond the current server memory store.
- Mature SkyBridge Notification Center self-supervision with bootstrap direct fallback.

## Later

- Mobile operator app readiness.
- Sidecar durable encrypted spool.
- Rich provider-specific notification delivery.
- Remote-safe artifact previews.
