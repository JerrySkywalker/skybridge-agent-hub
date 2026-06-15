# Operator Acceptance v2

Operator acceptance v2 aggregates the sandboxed install, uninstall, upgrade, rollback, channel migration preview, extended fixture soak and stability cleanup reports.

Command:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-operator-acceptance.ps1 -Command v2-report
```

Acceptance v2 records:

- install sandbox status;
- uninstall sandbox status;
- upgrade sandbox status;
- rollback sandbox status;
- version channel migration preview;
- extended fixture soak;
- stability cleanup;
- extracted and sandbox launcher validation;
- disabled capabilities;
- known limitations;
- next safe action;
- Web and Desktop read-only panel status.

The report does not include raw prompts, transcripts, stdout, stderr, worker logs, CI logs, GitHub logs, environment dumps, Authorization headers, cookies, private keys or tokens. `token_printed=false`.

Reports:

- `.agent/tmp/operator-acceptance/operator-acceptance-v2-report.json`
- `.agent/tmp/operator-acceptance/operator-acceptance-v2-report.md`
