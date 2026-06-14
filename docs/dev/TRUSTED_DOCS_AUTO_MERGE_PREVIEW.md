# Trusted Docs Auto-merge Preview

The trusted-docs auto-merge gate is a preview-only classifier for future exploration.

- `trusted_docs_auto_merge_enabled=false`.
- `auto_merge_apply_enabled=false`.
- The gate may classify a docs-only PR as theoretically eligible.
- The gate still returns `auto_merge_allowed=false`.
- The gate does not merge PRs, enable platform auto-merge, change branch protection, or bypass human review.
- `token_printed=false`.

Preview command:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-trusted-docs-auto-merge.ps1 -Command gate -Fixture eligible-docs-only
```
