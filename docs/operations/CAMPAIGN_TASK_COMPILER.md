# Campaign Task Compiler

Mega Goal 322 adds a constrained compiler from a high-level campaign plan to a bounded SkyBridge task queue.

The compiler is intentionally narrow. It may generate only deterministic low-risk docs or fixture-test tasks with exact repo-relative allowed paths. It rejects deployment, secrets, server-root, OpenResty, Authelia, DNS, Cloudflare, GitHub settings, branch-protection, and external infrastructure work.

## Operator Commands

Preview is the default:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-compile-campaign-tasks.ps1 -Json
```

Apply requires the exact confirmation string:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-compile-campaign-tasks.ps1 `
  -Apply `
  -Confirm I_UNDERSTAND_COMPILE_SAFE_CAMPAIGN_TASKS_ONLY `
  -Json
```

Generated campaign tasks should be executed only through bounded run-until-hold with a campaign selector:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-run-until-hold-bounded.ps1 `
  -CampaignId campaign-policy-compiler-pilot-001 `
  -Preview `
  -Json
```

## Safety Contract

- `project_control` remains paused.
- The bounded runner keeps `max_tasks` at 2 by default and clamps the absolute maximum to 3.
- The compiler reports unsafe requests instead of converting them into tasks.
- `blocked_paths` are guardrails only; unsafe text, requested work surface, or `allowed_paths` reject a task.
- Old failed, blocked, or completed residue is not claimed or requeued.
- No raw prompts, raw logs, credentials, cookies, token values, or environment dumps are printed.
- `token_printed=false`.
