# Autonomous Iteration Panel

The Operator Console includes an autonomous iteration control panel for one-glance supervision of the controller, CI Guardian, optional Hermes planner adapter and bootstrap notification path.

The panel shows safe metadata only:

- latest iteration state;
- open PR number when known;
- CI Guardian status derived from PR/CI iteration states;
- planner/supervisor status from `/v1/supervisor/status`;
- bootstrap notification path;
- notification provider configuration state;
- blocked reason;
- next recommended action from `/v1/supervisor/next-action`.

The panel does not fetch raw prompts, local logs, patches, stdout, stderr, Codex JSONL or secrets.

## Validation

Focused widget validation:

```powershell
corepack pnpm --filter @skybridge-agent-hub/react-widgets test
corepack pnpm --filter @skybridge-agent-hub/react-widgets typecheck
corepack pnpm --filter @skybridge-agent-hub/client test
corepack pnpm --filter @skybridge-agent-hub/client typecheck
corepack pnpm --filter @skybridge-agent-hub/web build
```

Console smoke:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-operator-console.ps1 -UseTempDatabase
```
