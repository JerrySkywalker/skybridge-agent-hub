# Operator Walkthrough Demo

Run the safe walkthrough:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-operator-walkthrough.ps1 -Command report
```

The walkthrough checks bootstrap complete, productization RC, local config, doctor, start preview, demo mode, local session status, diagnostics, smoke fast and next safe action.

It does not execute workers, apply workunits, run queue apply, mutate host settings or persist raw logs. token_printed=false
