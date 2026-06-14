# Trusted Docs Scoped Merge Apply

Trusted-docs auto-merge remains disabled globally:

- `trusted_docs_auto_merge_enabled=false`
- `auto_merge_apply_enabled=false`
- `generic_auto_merge_enabled=false`
- `token_printed=false`

Goal 226 adds a narrow scoped apply gate for a single explicitly approved task PR. The gate requires:

- exact PR number match in `approval_scope`
- one changed file
- at most 25 additions and 0 deletions
- `docs/**` or `README.md` only
- all CI checks green
- redaction, raw-log and secret-pattern scans pass
- low-risk docs/local-smoke task PR
- release gate and audit event present
- human-equivalent goal approval

The only apply command is:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-trusted-docs-auto-merge.ps1 -Command scoped-merge -ScopedPrNumber <pr> -UseLivePr -Apply
```

It may call `gh pr merge` only after the live PR passes the scoped gate. It must not merge code, config, server, production, GitHub settings or secret-related paths.
