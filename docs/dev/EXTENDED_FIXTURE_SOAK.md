# Extended Fixture Soak

The extended fixture soak repeats safe local-session previews and checks without starting a worker.

Command:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-local-soak.ps1 -Command extended-fixture-soak
```

Defaults:

- maximum iterations: `5`;
- maximum duration: `180` seconds;
- fixture-only;
- no Codex worker;
- no workunit apply;
- no queue apply;
- no raw logs;
- no background process left running;
- `token_printed=false`.

Reports:

- `.agent/tmp/local-session/extended-fixture-soak-report.json`
- `.agent/tmp/local-session/extended-fixture-soak-report.md`
