# v0.9 Release Candidate Audit

Date: 2026-05-22

This audit classifies v0.9 release-candidate readiness after PR #9 and the nightly local CI/CD guardian pass. It does not authorize production deployment, real remote command execution or secret-backed provider testing.

| Subsystem | Classification | Evidence | Follow-Up Goal |
| --- | --- | --- | --- |
| Event schema | ready | `skybridge.agent_event.v1` packages build and test; adapters normalize into documented event families. | Continue schema compatibility checks as new adapters land. |
| Server APIs | ready | Event ingestion, run detail, summary, sources, nodes, metrics, notifications, approvals and derived audit APIs pass server tests and smokes. | Durable audit work remains separate in `029-durable-audit-trail`. |
| SQLite persistence | ready | Server tests cover SQLite-backed local persistence and smokes use temporary SQLite databases. | Add durable audit tables in `029-durable-audit-trail`. |
| Codex integration | ready | Hook fixture smoke, online/offline integration smoke and self-observation smoke pass with redacted normalized events. | Shared PowerShell JSON redaction consolidation in `028-powershell-shared-redaction-rules`. |
| OpenCode adapter | needs smoke | Fixture-backed adapter normalization exists and multi-agent platform smoke ingests representative OpenCode events. | Real-runtime contract validation remains future work. |
| Hermes adapter | needs smoke | Fixture-backed adapter normalization exists and multi-agent platform smoke ingests representative Hermes events. | Real-runtime contract validation remains future work. |
| Sidecar/node foundation | skeleton only | Node identity, heartbeat and registry foundations are present; real WSS and execution are intentionally absent. | `023-remote-node-wss-implementation`. |
| Notification center | ready | Provider matrix, skipped placeholder behavior and notification records pass local tests and smokes without credentials. | Credentialed provider tests require a separate private, secret-aware plan. |
| Operator Console | needs smoke | Build, static widget tests and HTTP smoke pass; no real browser screenshot artifacts yet. | `022-real-browser-visual-qa`. |
| Web components/embed | needs smoke | Compact embed package builds/tests and is included in Operator Console smoke scope, but lacks browser screenshot QA. | `022-real-browser-visual-qa`. |
| CI/CD/release | ready | Latest PR #9, main and v0.9 tag workflows are green; local check, compose config, release dry-run and Docker builds passed. | Keep nightly script/log current before release tags. |
| Security/redaction | ready | Shared TypeScript redaction rules, threat model, hook redaction tests and security docs exist. | `028-powershell-shared-redaction-rules` for direct PowerShell consumption. |
| Docs/demo | ready | README, roadmap, changelog, docs index, release notes and deterministic demo dataset smoke pass. | Public docs site in `026-public-docs-site`; contributor polish in `027-external-contributor-onboarding`. |
| Smoke scripts | ready | PowerShell parse validation passes and all requested safe smoke scripts passed in temp or dry-run mode. | Nightly orchestration script added for repeatable local validation. |

## Blocking Issues

No blocking local CI/CD issue was found during this audit.

## Release Notes

- v0.9 is ready for human release-candidate review as a local-first telemetry and notification platform foundation.
- v0.9 is not ready for production remote control, mobile app operation or real deployment automation.
- The remaining risky surfaces are explicitly deferred to backlog goals with validation commands and safety boundaries.
