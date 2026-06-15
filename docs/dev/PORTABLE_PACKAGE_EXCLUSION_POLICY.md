# Portable Package Exclusion Policy

Excluded from package candidates:

- `.git/**`
- `node_modules/**` and `**/node_modules/**`
- `target/**` and `**/target/**`
- `dist/**`, `build/**`, `.next/**`, `coverage/**`
- `.env*`, `**/*.log`, `**/logs/**`
- `**/*secret*`, `**/*token*`, `**/*key*`, `**/*cookie*`
- `**/raw/**`
- `.agent/tmp/**`
- raw prompts, transcripts, stdout/stderr captures, worker logs, CI logs and GitHub logs
- Authorization, Bearer, cookie and private-key-like content

The package is constructed from a fixed allowlist rather than broad filesystem traversal.
