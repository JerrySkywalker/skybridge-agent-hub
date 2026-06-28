# Managed Development PR Pilot

MG357 introduces the first managed development PR pilot. It connects the bounded goal budget loop lineage to a practical repository workflow:

```text
reviewed development goal
-> managed dev preview
-> dedicated branch
-> one allowed docs or smoke change
-> local validations
-> draft PR
-> PR CI observation
-> human review hold
```

This is not autonomous long-running development. It is a single controlled pilot path for low-risk repository changes.

## Relation To MG351-MG356

MG351 defines provider ownership and keeps direct local runners separate from optional Hermes and future MCP providers. MG352 proves a single safe task can be executed once. MG353 adds static multi-step sequencing. MG354 generates proposed goal markdown only. MG355 reviews and appends a generated goal as metadata only. MG356 chooses exactly one bounded next action per invocation.

MG357 uses those gates for a managed development branch and PR workflow. It does not execute unreviewed generated goals, does not start a worker loop, and does not change deployment infrastructure.

MG359A proved the real draft PR path with a bounded manual Git/GH fallback after the controller reported `git_unavailable`. MG360 repairs the controller-native Git/GH provider path so the managed-dev controller itself can create the branch, commit the allowlisted docs change, push, create the draft PR, and observe CI.

## Controller

Script:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-managed-dev-pilot.ps1 -Command status -Json
```

Commands:

- `status`
- `preview`
- `apply-fixture`
- `apply-local`
- `create-pr-preview`
- `create-draft-pr`
- `ci-status`
- `report`
- `safe-summary`

Default behavior is fixture preview. Repository mutation requires `apply-local` plus exact confirmation:

```text
I_UNDERSTAND_APPLY_ONE_MANAGED_DEV_CHANGE_ONLY
```

Draft PR creation requires exact confirmation:

```text
I_UNDERSTAND_CREATE_ONE_DRAFT_PR_FOR_HUMAN_REVIEW_ONLY_NO_AUTO_MERGE
```

## Fixture Flow

Fixture mode is CI-safe. It simulates:

- project: `skybridge-agent-hub`
- campaign: `managed-dev-fixture-campaign-357`
- goal: `managed-dev-docs-smoke-goal-357-fixture`
- branch: `codex/mega-357-managed-dev-pr-pilot-fixture`
- change kind: `docs-note-and-smoke-fixture`
- changed files limited to orchestrator docs and managed-dev smoke fixtures
- draft PR not created
- CI status simulated as skipped
- human review hold required

Fixture mode never creates a real branch or PR.

## Local Flow

Local mode is optional and guarded. Before local apply, the controller checks:

- clean working tree
- current branch matches the base branch, normally `main`
- safe `codex/...` branch name
- planned files are inside allowed paths
- no forbidden paths are touched
- `MaxChangedFiles <= 5`
- exact apply confirmation is present

Before draft PR creation, the controller checks the draft PR confirmation and creates a draft PR only. It does not mark the PR ready, merge it, create tags, upload assets, or request deployment mutation.

MG360 adds explicit Git/GH provider reporting:

- `git_available`
- `gh_available`
- `git_detection_method`
- `gh_detection_method`
- `git_blocker`
- `gh_blocker`
- `controller_native_git_used`
- `controller_native_gh_used`
- `manual_fallback_used=false`

Provider detection uses bounded PowerShell command resolution and reports only sanitized status fields. It does not dump `PATH`, environment variables, credentials, raw process output, or auth headers. The controller distinguishes Git/GH availability from repository blockers such as dirty working tree, wrong branch, unavailable remote, existing pilot branch, failed push, and PR creation failure.

## Allowed Paths

Default allowed paths:

- `docs/orchestrator/`
- `docs/dev/`
- `scripts/powershell/smoke-managed-dev-`
- `package.json`
- `tests/fixtures/`

## Forbidden Paths

The pilot rejects deployment workflow paths, GitHub settings, Docker deployment infrastructure, OpenResty, Authelia, DNS/Cloudflare/TLS/firewall paths, secrets/config files, binary or installer artifacts, release assets, production runtime config, token files, and proxy profile material.

## Validation

Required MG357 smokes:

```powershell
corepack pnpm smoke:managed-dev-pilot-status
corepack pnpm smoke:managed-dev-pilot-preview
corepack pnpm smoke:managed-dev-pilot-fixture
corepack pnpm smoke:managed-dev-pilot-reject-no-confirm
corepack pnpm smoke:managed-dev-pilot-allowed-paths
corepack pnpm smoke:managed-dev-pilot-forbidden-paths
corepack pnpm smoke:managed-dev-pilot-no-real-pr-fixture
corepack pnpm smoke:managed-dev-pilot-no-auto-merge
corepack pnpm smoke:manual-managed-dev-pilot-fixture
```

MG360 repair smokes:

```powershell
corepack pnpm smoke:managed-dev-git-provider-detect
corepack pnpm smoke:managed-dev-gh-provider-detect
corepack pnpm smoke:managed-dev-controller-native-preview
corepack pnpm smoke:managed-dev-controller-native-apply-fixture
corepack pnpm smoke:managed-dev-controller-native-pr-fixture
corepack pnpm smoke:managed-dev-controller-native-no-fallback
corepack pnpm smoke:managed-dev-controller-native-blocker-classification
corepack pnpm smoke:manual-managed-dev-controller-native-fixture
```

The full local gate still runs Bootstrap Alpha acceptance, RC handoff/gate smokes, operator report, review gate, self-bootstrap convergence, PowerShell validation, `corepack pnpm check`, and `just check`.

## Manual M7 Test

Manual script:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\manual-managed-dev-pr-pilot.ps1 -Fixture -Preview -Json -WriteReport
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\manual-managed-dev-pr-pilot.ps1 -Fixture -ApplyLocal -Confirm I_UNDERSTAND_APPLY_ONE_MANAGED_DEV_CHANGE_ONLY -Json -WriteReport
```

Optional local preview:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\manual-managed-dev-pr-pilot.ps1 -Preview -BranchName codex/mega-357-managed-dev-pr-pilot -Json -WriteReport
```

Optional local apply and draft PR creation remain separate exact-confirmed operations. The pilot must hold for human review after the draft PR is created.

## Failure And Resume Cases

The controller reports blockers instead of retrying unboundedly. Common blockers include dirty working tree, wrong base branch, unsafe branch name, forbidden path, too many changed files, missing exact confirmation, and fixture-mode PR creation.

Resume should start with `preview` or `ci-status` and inspect the sanitized report under `.agent/tmp/managed-dev-pilot/`.

## Safety Flags

The managed development pilot reports:

- `auto_merge_enabled=false`
- `merge_performed=false`
- `release_created=false`
- `tag_created=false`
- `asset_uploaded=false`
- `deploy_mutation_requested=false`
- `task_created=false`
- `task_claimed=false`
- `worker_loop_started=false`
- `codex_generation_called=false`
- `codex_run_called=false`
- `matlab_run_called=false`
- `hermes_run_called=false`
- `mcp_run_called=false`
- `arbitrary_shell_enabled=false`
- `project_control_unpaused=false`
- `token_printed=false`

## Next Milestones

Likely follow-up options are a Hermes Planner Provider Pilot, an MCP Tool Provider Stub, or a Managed Dev v2 goal that wires this pilot into a real bounded-loop campaign while preserving the human review hold.
