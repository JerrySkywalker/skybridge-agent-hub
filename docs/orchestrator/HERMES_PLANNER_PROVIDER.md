# Hermes Planner Provider Pilot

MG366C introduces Hermes as an optional planner/provider surface for SkyBridge.
Hermes is advisory only. It can help draft planner advice or an unapproved
candidate goal markdown file, but it is not an executor and it does not own the
SkyBridge state machine.

## Provider Role

Hermes may:

- report planner-provider availability;
- preview a planner request without making a network call;
- return fixture planner advice for CI-safe validation;
- optionally, with exact operator confirmation, perform a read-only live status
  check;
- optionally, with separate exact operator confirmation, produce one sanitized
  unapproved candidate goal or advisory response.

Hermes must not:

- create tasks;
- claim tasks;
- start or complete execution;
- approve goals;
- append goals;
- create branches or pull requests;
- merge pull requests;
- deploy;
- run a worker loop or queue runner;
- mutate `project_control`;
- call Codex, MATLAB, MCP, git, gh, Docker, deploy tooling, or shell commands.

## Execution Boundary

The direct provider remains the execution path for already-approved local
runners. Hermes output is untrusted until reviewed by a human and imported
through the MG355-style review/approval/append gate. A Hermes candidate cannot
execute in the same invocation that generated it.

## Candidate Handling

Fixture mode writes one deterministic candidate under:

```text
.agent/tmp/hermes-planner-provider/candidates/hermes-fixture-goal-366c.md
```

The candidate is intentionally low risk and oriented toward a future MG367A
Vite chunk remediation planning goal. It remains:

- `candidate_approved=false`;
- `candidate_appended=false`;
- `task_created=false`;
- `execution_started=false`.

## Live Status And Live Plan

Live status and live planning are disabled unless exact confirmations are
provided:

```text
I_UNDERSTAND_CHECK_HERMES_PLANNER_PROVIDER_STATUS_ONLY
I_UNDERSTAND_CALL_HERMES_PLANNER_READ_ONLY_TO_GENERATE_UNAPPROVED_CANDIDATE
```

Live calls must not persist planner inputs, planner outputs, process streams,
headers, environment snapshots, credentials, or token values. Reports include only
sanitized booleans, safe paths, hashes, blockers, and warnings.

## Manual Test

Run the fixture flow:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\manual-hermes-planner-provider-test.ps1 -RunFixture -Json -WriteReport
```

Validate the generated candidate:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\manual-hermes-planner-provider-test.ps1 -ValidateCandidate -Json -WriteReport
```

Optional live status is a separate read-only gate and is not required for CI.

## Safety Flags

Every MG366C report must keep these values false:

- `candidate_approved=false`
- `candidate_appended=false`
- `task_created=false`
- `task_claimed=false`
- `execution_started=false`
- `branch_created=false`
- `pr_created=false`
- `merge_performed=false`
- `deploy_triggered=false`
- `raw_prompt_persisted=false`
- `raw_response_persisted=false`
- `secrets_persisted=false`
- `token_printed=false`

## Next Milestones

Likely follow-up options:

- MG367A Vite Chunk Remediation
- MG366D Worker Service Install/Daemonization
- MG367C Hermes Candidate Review/Append Gate
