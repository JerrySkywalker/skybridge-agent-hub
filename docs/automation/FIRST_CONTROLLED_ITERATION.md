# First Controlled Iteration Dry Run

The first controlled autonomous iteration is a dry-run proof only. It validates the operating model without editing production files, requiring credentials, opening a PR, enabling auto-merge or deploying.

Goal file:

```text
goals/backlog/030-controller-dry-run-validation.md
```

Command:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-iterate.ps1 `
  -ConfigFile .\config\iteration-controller.example.json `
  -GoalFile .\goals\backlog\030-controller-dry-run-validation.md `
  -DryRun `
  -One `
  -NoAutoMerge `
  -SkyBridgeApiBase http://127.0.0.1:1
```

Expected dry-run evidence:

- branch name: `ai/030-controller-dry-run-validation`;
- Codex command shape contains `codex exec`;
- local metadata and prompt preview are written under `.agent/iterations/<iteration-id>/`;
- SkyBridge API outage is fail-open;
- auto-merge is disabled;
- bootstrap notification path is no-send unless an operator passes `-Send` to `notify-bootstrap.ps1`.

Smoke:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-iteration-controller.ps1 -DryRun
```

The smoke removes its generated local run directory after validation. It does not create commits, branches, PRs or remote settings.
