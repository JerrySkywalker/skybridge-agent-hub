# PR9 Gap Audit

PR: #9, `Super Goal 005-014: SkyBridge platform release train`

Audit purpose: verify that each Super Goal phase is either implemented and validated or explicitly deferred behind a safe follow-up goal. This audit does not authorize production deployment, real remote command execution or secret-bearing provider tests.

## Phase 005: Multi-Agent Adapter Platform

Classification:

- implemented
- fixture-only for live OpenCode and Hermes runtime compatibility
- smoke-tested
- needs follow-up for real-runtime contract validation

Evidence:

- OpenCode and Hermes adapter packages normalize representative fixtures into `skybridge.agent_event.v1`.
- Source capability metadata includes Codex, OpenCode, Hermes, SkyBridge and custom sources.
- Multi-agent smoke exercises Codex/OpenCode/Hermes events through the server APIs.

Deferral:

- Real runtime plugin/API verification remains a future integration task. It must not use real secrets or private agent logs.

## Phase 006: Remote Node Sidecar Foundation

Classification:

- implemented
- skeleton-only for WSS control plane
- smoke-tested
- unsafe to implement real remote execution now

Evidence:

- Local node identity, heartbeat, node summary and safe sidecar status foundations exist.
- Remote-control boundary docs define WSS lifecycle, auth concepts, heartbeat and approval boundaries.

Deferral:

- Real WSS transport and command envelopes are deferred to `goals/backlog/023-remote-node-wss-implementation.md`.

## Phase 007: Notification Center Provider Matrix

Classification:

- implemented
- smoke-tested
- needs follow-up for credentialed provider integration tests

Evidence:

- Notification jobs include provider/status/category/severity/dedupe metadata.
- Provider matrix exposes safe configured/skipped status without credential values.
- Providers without credentials return structured skipped or failed results.

Deferral:

- Live credentialed provider tests are intentionally out of scope for public CI and must use fake/local fixtures unless a future private test goal explicitly authorizes secrets.

## Phase 008: Security Hardening And Redaction

Classification:

- implemented
- docs updated
- smoke-tested through hook and release smokes
- needs follow-up for PowerShell direct JSON rules consumption

Evidence:

- Shared TypeScript redaction rules and payload-size guards exist.
- Threat model and SECURITY updates cover public CI, self-hosted runner risk, hooks, sidecar remote control, providers and local spool privacy.

Deferral:

- PowerShell direct consumption of shared redaction JSON is deferred to `goals/backlog/028-powershell-shared-redaction-rules.md`.

## Phase 009: Docs Site, Demo Dataset And Packaging

Classification:

- implemented
- docs-only for hosted docs site
- smoke-tested
- needs follow-up for public docs publishing

Evidence:

- Documentation index, demo dataset docs, release checklist, changelog and public README orientation exist.
- Demo dataset generation is deterministic and covered by local smoke/test paths.

Deferral:

- Hosted public documentation site packaging is deferred to `goals/backlog/026-public-docs-site.md`.

## Phase 010: Dogfooding Loop

Classification:

- implemented
- fixture-driven
- smoke-tested

Evidence:

- Dogfooding docs and smoke script simulate safe Codex hook, exec, runner, notification and dashboard query behavior.
- The smoke can start a temporary local server and uses fake events only.

Deferral:

- Real user hook installation remains opt-in and is not required for PR #9.

## Phase 011: Remote Approval Queue

Classification:

- implemented
- skeleton-only for remote execution integration
- smoke-tested
- unsafe to connect to destructive remote commands now

Evidence:

- Approval event model includes requested, resolved, denied and expired states.
- Server approval queue APIs list/get/resolve pending approvals.
- Dashboard approval panel and smoke fixtures exercise the local-first operator model.

Deferral:

- Binding approvals to real remote commands is deferred to `goals/backlog/023-remote-node-wss-implementation.md`.

## Phase 012: Staging And Self-Hosted Readiness

Classification:

- implemented
- docs-only for real production deployment
- smoke-tested
- unsafe to deploy now

Evidence:

- Self-hosting docs, placeholder OpenResty/Authelia examples and dry-run smoke exist.
- Compose config checks are part of the validation path.

Deferral:

- Production deployment hardening is deferred to `goals/backlog/025-production-deployment-hardening.md`.

## Phase 013: Observability, Metrics And Audit

Classification:

- implemented
- skeleton-only for durable append-only audit storage
- smoke-tested
- needs follow-up for persistence-grade audit records

Evidence:

- `/v1/metrics` exposes event, run, notification, node and recent failure counts.
- `/v1/audit` now derives safe audit entries from already-redacted approval, node, notification and failed-run events.
- Audit entries do not include raw payloads.

Deferral:

- Durable append-only audit storage is deferred to `goals/backlog/029-durable-audit-trail.md`.

## Phase 014: Release Candidate Hardening

Classification:

- implemented
- docs updated
- smoke-tested
- needs follow-up for browser visual QA, mobile, docs site, contributor onboarding and production hardening

Evidence:

- Release candidate docs, roadmap, release train audit, smoke scripts and backlog goals exist.
- PR #9 hardening repaired Linux PowerShell smoke startup and Docker Buildx cache setup.

Deferrals:

- Browser visual QA: `goals/backlog/022-real-browser-visual-qa.md`.
- Mobile readiness: `goals/backlog/024-mobile-app-readiness.md`.
- Public docs site: `goals/backlog/026-public-docs-site.md`.
- External contributor onboarding: `goals/backlog/027-external-contributor-onboarding.md`.
- Production deployment hardening: `goals/backlog/025-production-deployment-hardening.md`.

## Audit Conclusion

PR #9 is a broad release-candidate foundation, not a production-ready remote-control release. The acceptance criteria are materially covered for local telemetry, fixtures, safe APIs, dashboard visibility, docs and smoke validation. The remaining gaps are intentionally deferred where they would require real remote execution, real provider credentials, production infrastructure or visual/browser QA beyond the current local checks.
