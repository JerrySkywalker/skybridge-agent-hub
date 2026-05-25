# GitHub Provider

Status: `dogfooding`

Role: `SCMProvider` and CI provider.

GitHub is the current provider for PR summaries, CI checks, branch policy visibility and dry-run auto-merge decisions. GitHub repository settings remain operator-owned.

Core boundary:

- Core must not mutate GitHub settings.
- Auto-merge remains disabled by default and must not become always-on unattended behavior.
- Non-GitHub SCM/CI providers should be able to report equivalent PR, check and policy records.

Related docs:

- [../../automation/AUTO_MERGE_POLICY.md](../../automation/AUTO_MERGE_POLICY.md)
- [../../automation/GITHUB_AUTOMATION_READINESS.md](../../automation/GITHUB_AUTOMATION_READINESS.md)
