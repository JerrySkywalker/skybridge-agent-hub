# Operator Demo Mode

Demo mode is fixture-only and safe for screenshots or operator walkthroughs.

Run:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-local-session.ps1 -Command demo
```

Demo mode does not start a worker, execute a workunit, create tasks, mutate system settings or persist raw logs. It reports component fixture data with `token_printed=false`.
