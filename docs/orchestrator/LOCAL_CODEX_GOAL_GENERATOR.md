# Local Codex Goal Generator

MG354 adds the first local goal authoring surface for SkyBridge. It can turn a
campaign context, operator objective and fixed safety template into one proposed
goal markdown file. The output is a review candidate only.

The generator is deliberately separate from import, append and execution. MG355
is the first milestone that may review or import generated proposals. MG356 and
later loop goals may consume reviewed work, but MG354 never mutates campaign
state and never creates or claims tasks.

## Relation To Provider Contract

The script uses the MG351 tool provider inventory before generation:

- direct provider must be available;
- Codex detection is evidence only;
- fixture mode never calls Codex;
- local Codex mode is optional and exact-confirmed;
- MATLAB, Hermes and MCP are not called;
- MCP remains future/disabled.

Provider availability never implies approval to import or execute a generated
goal.

## Relation To Loop Controllers

MG352 and MG353 prove exact-confirmed execution loops for fixed templates. MG354
does not extend those loops. It produces markdown only and stops before review.

This boundary keeps authoring separate from:

- task creation;
- task claim;
- campaign append/import;
- campaign advance;
- worker-loop or queue-runner execution;
- arbitrary shell or arbitrary prompt surfaces.

## Commands

Controller:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-local-goal-generator.ps1 `
  -Command preview `
  -Fixture `
  -Json
```

Fixture generate-one:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-local-goal-generator.ps1 `
  -Command generate-one `
  -Fixture `
  -Confirm I_UNDERSTAND_GENERATE_ONE_GOAL_MARKDOWN_ONLY_NO_IMPORT_NO_EXECUTION `
  -Json `
  -WriteReport
```

Manual M4 wrapper:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\manual-local-goal-generate-test.ps1 `
  -Fixture `
  -GenerateOne `
  -Confirm I_UNDERSTAND_GENERATE_ONE_GOAL_MARKDOWN_ONLY_NO_IMPORT_NO_EXECUTION `
  -WriteReport
```

## Fixture Flow

Fixture mode is CI-safe and deterministic:

- project: `skybridge-agent-hub`;
- campaign: `local-goal-generator-fixture-354`;
- objective: `Create a safe documentation validation goal for a future campaign.`;
- generated goal id: `generated-docs-validation-goal-354-fixture`;
- output: `.agent/tmp/generated-goals/fixture/generated-goal-354-fixture.md`.

Preview validates the candidate shape without writing markdown. Generate-one
requires the exact MG354 confirmation and writes exactly one file under ignored
`.agent/tmp/generated-goals`.

## Local Codex Flow

Local Codex mode is optional:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\manual-local-goal-generate-test.ps1 `
  -UseCodex `
  -Preview `
  -ProjectId skybridge-agent-hub `
  -CampaignId local-codex-goal-generator-354-001 `
  -GoalBudgetRemaining 1 `
  -Objective "Generate one safe follow-up goal for validating goal append review only." `
  -Json `
  -WriteReport
```

Generation requires:

- provider inventory checked;
- direct provider available;
- Codex detected;
- `-UseCodex`;
- exact confirmation
  `I_UNDERSTAND_GENERATE_ONE_GOAL_MARKDOWN_ONLY_NO_IMPORT_NO_EXECUTION`;
- output under `.agent/tmp/generated-goals`.

Codex is invoked at most once through the fixed goal-generation prompt template.
The script accepts only a generated markdown file that passes metadata and
safety validation.

## Validation Rules

Generated markdown must include a fenced JSON metadata block with
`skybridge.generated_goal_metadata.v1` and these required fields:

- `human_review_required=true`;
- `import_allowed=false`;
- `execution_allowed=false`;
- `token_printed=false`.

The markdown must also include:

- title;
- context;
- mission;
- hard safety boundaries;
- allowed scope;
- forbidden scope;
- implementation requirements;
- validation requirements;
- CI/CD requirements;
- manual milestone script requirement;
- evidence requirements;
- final report requirements;
- explicit no-execution statement.

The generator rejects unsafe goal ids, unsafe operator objectives and output
directories outside `.agent/tmp/generated-goals`. Direct writes to
`goals/proposed` are deferred to MG355 instead of being implemented in MG354.

## Reports

When `-WriteReport` is used:

- `.agent/tmp/generated-goals/local-goal-generator.md`
- `.agent/tmp/generated-goals/local-goal-generator.json`

Reports include path-safe generated goal location, SHA256 hash, validation
status, blockers, warnings and safety flags. They exclude raw prompts, raw
responses, process streams, tokens, credentials, cookies, provider auth headers,
proxy profiles and complete environment listings.

## Manual M4 Checklist

1. Run fixture preview.
2. Run fixture generate-one with the exact confirmation.
3. Inspect the generated markdown path.
4. Validate metadata and safety sections.
5. Confirm `human_review_required=true`.
6. Confirm `import_allowed=false`.
7. Confirm `execution_allowed=false`.
8. Optionally run local Codex preview.
9. Optionally run local Codex generate-one after explicit confirmation.
10. Verify no import, append, approval, task creation, task claim, execution or
    worker loop occurred.
11. Verify `token_printed=false`.

## Failure Modes

The generator blocks instead of generating when:

- exact confirmation is missing for generate-one;
- provider inventory is unavailable;
- direct provider is unavailable;
- Codex is requested but not detected;
- goal id, title or objective fails safety checks;
- output path is outside the allowed generated-goal root;
- generated markdown fails metadata or safety validation.

It does not retry Codex generation unboundedly.

## Next Milestone

MG355 adds Goal Append Review and Import. That milestone may review generated
markdown, record reason-gated approval state, preview a campaign append and
append exactly one non-executed metadata step. MG354 never self-approves,
self-imports, self-appends or self-executes a generated goal. See
[GOAL_APPEND_REVIEW_IMPORT.md](GOAL_APPEND_REVIEW_IMPORT.md).

`token_printed=false`
