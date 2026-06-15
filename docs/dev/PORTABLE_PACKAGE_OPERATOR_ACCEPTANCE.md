# Portable Package Operator Acceptance

The operator acceptance report aggregates clean-room rehearsal, extracted runtime validation, artifact integrity, reproducibility preview, fixture soak, and restart cleanup rehearsal.

Run:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-operator-acceptance.ps1 -Command report
```

Reports:

- `.agent/tmp/operator-acceptance/operator-acceptance-report.json`
- `.agent/tmp/operator-acceptance/operator-acceptance-report.md`

The report is acceptance metadata only. It does not install, upload, release, enable execution, or mutate host settings. `token_printed=false`.

