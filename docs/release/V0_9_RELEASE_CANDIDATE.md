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

## Known Gaps

- Real WSS remote node implementation.
- Browser visual QA artifacts.
- Mobile app readiness.
- Production deployment hardening.
- Public docs site generation.
- External contributor onboarding.

## Release Checklist

1. Update version and changelog.
2. Run `corepack pnpm check`.
3. Run release dry-run and release candidate smoke.
4. Validate Docker compose dev/test/prod config.
5. Build server and web images.
6. Tag `v0.9.0` only after review.
