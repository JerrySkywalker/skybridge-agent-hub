# Tag Publish Policy

Tags may trigger existing repository workflows. Before creating a tag, run:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-release-workflow-guard.ps1 -Command report -Json
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-release-workflow-guard.ps1 -Command tag-safety-gate -Json
```

Policy:

- Manual GitHub Release creation remains disabled unless a future explicit goal authorizes it.
- Manual artifact upload remains disabled.
- Docker and artifact workflow side effects must be classified before tag.
- Release tag closeout must report expected workflow side effects.
- If tag workflow behavior is unknown or unsafe, skip the tag and report the blocker.

`token_printed=false`
