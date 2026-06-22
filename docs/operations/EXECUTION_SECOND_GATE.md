# Execution Second Gate

Goal 318 adds `skybridge-execution-second-gate-readiness.ps1` as the explicit
readiness layer between convergence and any execution-class command.

This goal is preview-only. The second gate does not authorize `start-one`,
`run-until-hold`, task claim, task requeue, Codex execution, live notification
send, or `project_control` unpause.

## Run

```powershell
. "$HOME\.skybridge\skybridge.env.ps1"
. "$HOME\.skybridge\worker.env.ps1"

pwsh -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\powershell\skybridge-execution-second-gate-readiness.ps1 `
  -ApiBase $env:SKYBRIDGE_API_BASE `
  -TokenFile "$HOME\.skybridge\worker-token.txt" `
  -Json
```

The output schema is `skybridge.execution_second_gate_readiness.v1`.

Key fields:

```text
status = blocked | preview_ready | ready
allowed_preview_only = true | false
allowed_execution = true | false
project_control_state = paused | ...
hermes_tool_execution_risk = true | false
second_gate_configured = true | false
token_printed = false
```

## Policy

`preview_ready` is the expected Goal 318 state when cloud/local readiness is
healthy enough for a read-only start-one preview but execution remains
forbidden. Current production posture should keep:

```text
project_control_state=paused
allowed_preview_only=true
allowed_execution=false
```

Hermes server tool execution remains a risk unless a documented second gate is
configured. The readiness script reports that risk without printing Hermes raw
responses, tokens, endpoints, prompts, logs or environment dumps.

`allowed_execution=true` is not expected for the generic queue. Goal 319 does
not open that gate. It adds only a task-specific pilot path for
`start-one-apply-pilot-docs-001`, with exact operator confirmation and
`project_control` still paused. Generic `start-one`, batch execution and
`run-until-hold` remain unavailable.

## Smoke

```powershell
corepack pnpm smoke:execution-second-gate-readiness
```

The smoke is fixture-only. It verifies that Hermes server tool execution blocks
execution when not second-gated, preview-only remains allowed while
`project_control` is paused, unsafe state blocks preview, and
`token_printed=false`.
