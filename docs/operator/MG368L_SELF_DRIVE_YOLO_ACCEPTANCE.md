# MG368L Self-Drive YOLO Acceptance Policy

Baseline commit:
`15a976c24eb4ccace66350c37259921ca8b81ac7`

MG368L clarifies the operator acceptance policy after MG368K. MG368I-R3 was
repeatedly blocked because its acceptance criteria required Jerry manual TUI
verification evidence. For fixture-only/no-real-execution validation, that
manual gate is now superseded by Codex self-drive evidence.

## Reason

MG368K added a simplified guide, bilingual UI, fixture-only YOLO mode, a Codex
self-drive harness, confirmation-buffer hardening, duplicate-paste diagnostics
and no-real-execution assertions. The self-drive harness can exercise the full
fixture flow without requiring Jerry to repeatedly paste long exact
confirmation strings.

The MG368I-R3 manual proof directory was not collected:

- `manual_verification_performed=false`
- `manual_proof_waived_for_fixture_only=true`
- `does_not_claim_human_validation=true`

This is not a claim that human-operated TUI validation passed. It is a
self-drive YOLO validation pass for the fixture-only stage.

## Current Evidence

Evidence path:
`.agent/tmp/operator-tui/mg368l-self-drive/`

Command:

```powershell
cargo run --manifest-path apps/operator-tui/Cargo.toml -- `
  --local-cloud `
  --operator-guide `
  --yolo-fixture-only `
  --self-drive-dry-run `
  --lang zh-CN `
  --runtime-timeout-ms 120000 `
  --output-dir .agent/tmp/operator-tui/mg368l-self-drive
```

Evidence fields:

- `self_drive_completed_full_fixture_flow=true`
- `yolo_fixture_only=true`
- `simplified_guide_available=true`
- `bilingual_ui_available=true`
- `zh-CN available=true`
- `yolo_real_execution_blocked=true`
- `raw_input_persisted=false`
- `token_printed=false`

The self-drive history covers:

- generate candidate fixture
- validate candidate
- review fixture metadata
- append fixture metadata
- preview bounded action
- start one fixture-safe goal
- safe pause fixture
- abort preview fixture

## Accepted Fixture-Only Gate

For fixture-only/no-real-execution TUI validation, the accepted gate is:

```text
Codex self-drive full fixture flow
```

Jerry manual TUI verification is optional for this fixture-only stage. If no
manual evidence exists, docs must report
`manual_verification_performed=false`.

Long exact confirmations are not required when `--yolo-fixture-only` is active
and the action is fixture-safe/no-real-execution.

## Rejected Interpretations

- Self-drive is not production execution.
- Self-drive is not human proof.
- Fixture-only YOLO is not real execution.
- MG368L does not start MG369A.
- MG368L does not create a real docs-only managed-dev PR from the TUI.
- MG368L does not claim human-operated TUI UX is fully validated.

## Safety Boundary

All real execution and mutation flags remain false:

- `TUI-created branch=false`
- `TUI-created PR=false`
- `real_task_execution_enabled=false`
- `real_branch_creation_enabled=false`
- `real_pr_creation_enabled=false`
- `task_created=false`
- `task_claimed=false`
- `execution_started=false`
- `worker_loop_started=false`
- `queue_runner_started=false`
- `run_forever_started=false`
- `hermes_live_called=false`
- `mcp_run_called=false`
- `auto_merge_enabled=false`
- `release_created=false`
- `tag_created=false`
- `asset_uploaded=false`
- `token_printed=false`

For real execution or production mutation, explicit human authorization remains
mandatory. Fixture-only YOLO must not enable real task execution, TUI-created
branches or PRs, queue runners, worker loops, run forever, live Hermes, MCP,
auto-merge, releases, tags or asset uploads.

## Supersession

MG368I-R3 manual proof is superseded as a blocker for fixture-only acceptance.
The fixture-only stage result is:

```text
self-drive YOLO validation pass
```

It is not:

```text
human-operated manual pass
```

Recommended next milestone:

- `MG369A-YOLO Fixture Single-Step Experiment`
- or `MG369A Self-Drive Single-Step Experiment`

Any future real execution requires a separate goal with explicit human
authorization.

`token_printed=false`
