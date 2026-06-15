# Operator Acceptance v4

Operator acceptance v4 verifies the installer promotion RC preview layer:

- release workflow guard;
- installer promotion gate;
- release artifact manifest;
- long sandbox soak;
- update channel manifest;
- offline update and rollback preview;
- host mutation gate;
- installer safety interlock;
- read-only Web/Desktop panels.

Run:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-release-walkthrough.ps1 -Command acceptance-v4 -Json
```

Acceptance v4 is safe metadata only. `token_printed=false`.
