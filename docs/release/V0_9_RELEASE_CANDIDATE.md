# v0.9 Release Candidate

## Scope

v0.9 is the first credible public platform release candidate for SkyBridge Agent Hub.

Included foundation:

- Codex, OpenCode, Hermes, SkyBridge and custom source metadata.
- MVP OpenCode and Hermes adapter normalization.
- Sidecar node identity, heartbeat and safe spool behavior.
- Notification job records, provider matrix and routing rules.
- Shared redaction rules and payload size limits.
- Demo dataset, dogfooding smoke and release candidate smoke.
- Approval queue API skeleton and dashboard panel.
- Metrics summary endpoint and audit design.

Smoke-tested foundation:

- Full monorepo `check`.
- Dev/test/prod compose config rendering.
- Operator Console, release dry-run, self-hosting dry-run, Codex hook integration, multi-agent platform, dogfooding, release-candidate and self-observation smokes.
- Local server and web Docker image builds.

Skeleton-only or fixture-backed foundation:

- OpenCode and Hermes adapters are fixture-backed until real runtime compatibility is validated.
- Sidecar/node registry exists, but real WSS transport and command execution are deferred.
- `/v1/audit` is a safe derived audit view, not a durable append-only audit table yet.

## Known Gaps

- Real WSS remote node implementation.
- Browser visual QA artifacts.
- Mobile app readiness.
- Production deployment hardening.
- Public docs site generation.
- External contributor onboarding.
- PowerShell scripts still need direct consumption of the shared redaction JSON.

See `docs/release/V0_9_RELEASE_CANDIDATE_AUDIT.md` for subsystem-level readiness classifications.

## Release Checklist

1. Update version and changelog.
2. Run `corepack pnpm check`.
3. Run release dry-run and release candidate smoke.
4. Run self-hosting dry-run smoke.
5. Validate Docker compose dev/test/prod config.
6. Review `docs/release/RELEASE_TRAIN_AUDIT.md`.
7. Build server and web images.
8. Tag `v0.9.0` only after review.
