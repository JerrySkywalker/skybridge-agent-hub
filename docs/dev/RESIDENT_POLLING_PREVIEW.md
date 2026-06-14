# Resident Polling Preview

Goal 224 adds `scripts/powershell/skybridge-resident-polling.ps1` as a local preview poller. It can inspect fixture/local state and write reports under `.agent/tmp/resident-polling/`.

Supported preview commands:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-resident-polling.ps1 -Command status -Json
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-resident-polling.ps1 -Command preview-once -Json
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-resident-polling.ps1 -Command preview-loop-fixture -Json
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-resident-polling.ps1 -Command report -Json
```

The policy contract is `skybridge.resident_polling_policy.v1`. `polling_enabled=false` by default, `polling_preview_enabled=true`, and `poll_interval_seconds` is at least 300.
