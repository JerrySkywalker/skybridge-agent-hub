# Roadmap

## v0.9

- Agent-agnostic control plane boundaries across planner, executor, SCM/CI, notification and runtime adapters.
- Multi-agent telemetry across Codex, OpenCode, Hermes and custom adapters.
- Local sidecar node registry foundation.
- Notification provider matrix and routing rules.
- Security hardening, shared redaction rules and threat model.
- Demo dataset, dogfooding smoke and release candidate checklist.
- Agent CI/CD Control Plane foundation for bounded iteration, PR CI repair, Hermes supervision and bootstrap notifications.

Status: productized local operator slice after Super Goal 061-080 plus agent-agnostic core boundary work. Codex, Hermes, GitHub and ntfy are preserved as dogfooding adapters/providers, while rule-based planner and manual executor proofs demonstrate that core product state does not require them. The console now has overview, runs, iterations, PR/CI, auto-merge, notifications, Hermes adapter detail, sources/audit, settings and compact embed surfaces. OpenCode/Hermes runtime compatibility remains fixture/local-telemetry-backed; real browser screenshots are optional and skip safely when Playwright is unavailable. WSS remote control, mobile app readiness, docs publishing and production deployment hardening remain follow-up work.

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
