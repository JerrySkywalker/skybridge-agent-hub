# Tool Provider Contract

MG351 defines the first formal provider inventory for SkyBridge long-running
goal orchestration. The inventory answers what the Windows local side can see,
which provider owns each tool today, and whether later campaign steps may even
consider a runner. It is a read-only contract; it is not an execution grant.

## Control Plane

SkyBridge is the long-running goal orchestration control plane. It owns:

- campaign state;
- goal budgets;
- dependency gates;
- task creation policy;
- evidence requirements;
- retry, hold and abort decisions;
- audit records;
- provider inventory consumption.

Campaign advance may use the inventory to decide whether a future step has a
candidate provider. A detected provider only means the step can continue to
template and gate review. It does not create a task, claim a task, start a
worker, invoke Codex, invoke MATLAB, call Hermes, or call MCP.

## Windows Local Execution Plane

The Windows local worker is the execution plane. It may:

- inspect local tools;
- run fixed local runner paths after a future exact confirmation and gate;
- return bounded evidence;
- report safe provider status.

The Windows local worker must never own campaign state. It does not decide the
next campaign step, skip dependencies, override holds, unpause project control
or expand into an always-on queue runner by itself.

## Provider Types

Provider records use these types:

- `direct`: local, fixed runner ownership for tools already proven in the
  Bootstrap Alpha path.
- `hermes`: optional planner, gate, notification, or provider boundary.
- `mcp`: future/disabled MCP provider boundary.
- `disabled`: intentionally unavailable execution surfaces.
- `future`: reserved provider slots for later goals.

## Tool Capabilities

The first inventory covers:

- `powershell`
- `git`
- `gh`
- `node`
- `pnpm`
- `rust`
- `tauri`
- `codex`
- `matlab`
- `hermes`
- `mcp`

Each tool record includes a provider id, detection method, sanitized executable
path, safe version summary, status, preview support and the execution gates
that would still be required later.

## Current Defaults

The direct provider is the current default for fixed Codex and MATLAB runner
paths that already exist. That does not enable arbitrary Codex prompts or
arbitrary MATLAB commands.

Hermes is optional. It may advise, plan, gate, notify or act as a future
provider, but it is not the mandatory owner of all local tool execution and does
not replace the SkyBridge state machine.

MCP is future/disabled unless a later goal explicitly adds repo-local
configuration and a separate execution gate.

## Safety Model

- Provider inventory is read-only.
- Provider detection does not execute workloads.
- Provider availability does not imply execution approval.
- Every future execution still needs a template, a gate, exact confirmation and
  bounded evidence.
- Reports must include only safe booleans, counts, status fields and sanitized
  paths.
- Reports must not include tokens, credentials, cookies, provider auth headers,
  proxy profiles, raw logs, process streams, prompt bodies or complete env
  listings.
- `execution_allowed=false` and `token_printed=false` are mandatory inventory
  invariants.

## Non-Goals

MG351 does not add:

- a general shell provider;
- an arbitrary prompt provider;
- an arbitrary MATLAB provider;
- an unbounded worker loop;
- an autonomous queue runner;
- MCP execution;
- Hermes takeover of SkyBridge campaign state;
- task creation, task claim or task execution.

## Schema

The inventory schema is `skybridge.tool_provider.v1`. Top-level fields include:

- `schema`
- `generated_at`
- `host_os`
- `host_name_safe`
- `project_id`
- `provider_inventory`
- `providers`
- `tools`
- `defaults`
- `disabled_capabilities`
- `warnings`
- `blockers`
- safety flags fixed to false, including `execution_allowed`,
  `task_created`, `task_claimed`, `execution_started`, `codex_run_called`,
  `matlab_run_called`, `hermes_run_called`, `mcp_run_called`,
  `worker_loop_started`, `project_control_unpaused` and `token_printed`.

Provider fields:

- `provider_id`
- `provider_type`
- `display_name`
- `status`
- `tools`
- `default_for_tools`
- `execution_enabled=false`
- `notes`
- `warnings`
- `blockers`

Tool fields:

- `tool_id`
- `display_name`
- `provider_id`
- `detection_method`
- `executable_path_safe`
- `version_summary_safe`
- `status`
- `can_preview`
- `can_execute_now=false`
- `requires_exact_confirmation=true`
- `requires_template=true`
- `requires_allowlist=true`
- `warnings`
- `blockers`

## Commands

Read-only inventory:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-tool-provider.ps1 `
  -Command inventory `
  -Json
```

Write sanitized reports:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-tool-provider.ps1 `
  -Command audit `
  -WriteReport `
  -Json
```

Manual milestone:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\manual-tool-provider-check.ps1 `
  -WriteReport
```

Reports are written to:

- `.agent/tmp/tool-provider/tool-provider-inventory.md`
- `.agent/tmp/tool-provider/tool-provider-inventory.json`

## Future Use

MG352 is the first consumer of this inventory. It proves one exact-confirmed
`safe-local-smoke.v1` task can bridge a server campaign step to Windows-local
execution evidence without enabling a generic execution provider. The inventory
still reports `execution_allowed=false`; the MG352 apply gate grants only the
single fixed runner selected by the controller.

MG353-MG359 should continue consuming this inventory before deciding whether a
campaign step can progress toward execution. The expected sequence is:

1. SkyBridge reads campaign state and step dependencies.
2. SkyBridge checks the provider inventory for required tools.
3. SkyBridge checks the task template, allowlist and exact-confirmation gate.
4. SkyBridge decides hold, retry, abort or explicit one-step execution.
5. The Windows local worker runs only the fixed runner selected by that gate.

If inventory is missing or a required provider is disabled, the campaign should
hold with evidence instead of inventing a fallback execution path.

`token_printed=false`
