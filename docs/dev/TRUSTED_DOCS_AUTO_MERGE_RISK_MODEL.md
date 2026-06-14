# Trusted Docs Auto-merge Risk Model

The future trusted-docs model is intentionally narrow.

- Docs-only changes.
- Maximum one changed file.
- Maximum 20 additions.
- Zero deletions.
- Allowed paths: `docs/**`, `README.md`.
- Forbidden paths: `.github/**`, `apps/**`, `packages/**`, `scripts/**`, `server/**`, `infra/**`, `.env*`, `**/*secret*`, `**/*token*`.
- All CI must be green.
- Release, resource, failure budget, evidence retention, audit, and redaction gates must pass.
- Secret scan must pass.
- Human override is still required in this preview.
- `token_printed=false`.

Preview blockers include disabled policy, multiple files, too many changes, deletions, disallowed paths, raw artifacts, secret scan failure, missing CI, open review holds, missing human override, and `blocked_by_token_printed_true`.
