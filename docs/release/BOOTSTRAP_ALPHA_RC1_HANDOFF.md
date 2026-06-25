# Bootstrap Alpha RC1 Handoff

Bootstrap Alpha RC1 is the first tagged Bootstrap Alpha release-candidate
milestone. It packages the MG324-MG341 cloud/server, local worker, MATLAB, Codex
native report, evidence, disabled-features, RC gate, and tag audit chain.

## RC1 Identity

- Tag: `v0.1.0-bootstrap-alpha-rc1`
- Tag target:
  `4473257548bd0fc26e05002d968f8525b37bac8b`
- Image:
  `ghcr.io/jerryskywalker/skybridge-agent-hub-server:sha-4473257548bd0fc26e05002d968f8525b37bac8b`
- GitHub Release: not created
- RC gate: passed before tag creation
- Post-tag audit: passed with the expected
  `tag_already_exists_on_target_commit` warning after the tag existed
- `token_printed=false`

## Live Proof Chain

- Safe template task: `live-safe-template-task-332-001`
- MATLAB golden task: `live-matlab-golden-task-336-001`
- Codex native report task: `live-codex-analysis-report-task-339-001`

These tasks prove the current Bootstrap Alpha path from cloud task metadata to
local worker evidence, fixed MATLAB runner output, native Codex report
validation, sanitized evidence, and read-only operator review.

## Audit Reports

Post-tag audit report paths:

- `.agent/tmp/bootstrap-alpha-rc/bootstrap-alpha-rc1-post-tag-audit.md`
- `.agent/tmp/bootstrap-alpha-rc/bootstrap-alpha-rc1-post-tag-audit.json`

RC1 handoff report paths when written:

- `.agent/tmp/bootstrap-alpha-rc/bootstrap-alpha-rc1-handoff.md`
- `.agent/tmp/bootstrap-alpha-rc/bootstrap-alpha-rc1-handoff.json`

These reports are local safe summaries. They must not include raw logs, raw
prompts, stdout/stderr dumps, token values, credentials, cookies, provider auth
headers, proxy profiles, or process-environment snapshots.

## Disabled Features Summary

Bootstrap Alpha RC1 still disables:

- general remote shell;
- unbounded run;
- daemon auto-expansion;
- arbitrary task execution;
- arbitrary prompt execution;
- MATLAB arbitrary command;
- Codex arbitrary prompt;
- worker-runner PR creation;
- auto-merge;
- background autonomous queue processing;
- project-control unpause through this handoff path;
- production infrastructure mutation through this handoff path.

The full disabled list is in
[BOOTSTRAP_ALPHA_DISABLED_FEATURES.md](BOOTSTRAP_ALPHA_DISABLED_FEATURES.md).

## Known Limitations

- No GitHub Release or release assets have been created.
- Desktop packaging remains future work.
- Real research workflow expansion remains future work.
- Multi-user permissions, mobile/watch client, notification center
  productization, and multi-project production support remain disabled.
- The worker may be offline during RC1 handoff checks; that is non-blocking
  because no task claim or execution is performed.

## Local Verification

Run the read-only handoff checks:

```powershell
corepack pnpm smoke:bootstrap-alpha-rc1-handoff
corepack pnpm smoke:bootstrap-alpha-rc1-handoff-local
corepack pnpm smoke:bootstrap-alpha-rc1-handoff-report
corepack pnpm smoke:codex-stop-hook-hygiene
corepack pnpm smoke:bootstrap-alpha-rc1-tag-check
```

Run the broader local release checks:

```powershell
corepack pnpm smoke:bootstrap-alpha-rc-gate-local
corepack pnpm smoke:bootstrap-alpha-tag-preview
corepack pnpm smoke:bootstrap-alpha-acceptance
corepack pnpm smoke:operator-report
corepack pnpm smoke:review-gate
corepack pnpm smoke:self-bootstrap-converge
```

The checks are read-only and must keep `github_release_created=false`,
`task_claimed=false`, `execution_started=false`, `codex_run_called=false`,
`matlab_run_called=false`, `worker_loop_started=false`,
`project_control_unpaused=false`, and `token_printed=false`.

## Cloud Deploy Verification

Verify the deployed cloud server and RC1 handoff status:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-bootstrap-alpha-rc1-handoff.ps1 -Command audit -ApiBase https://skybridge.jerryskywalker.space -Json
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-cloud-parity-check.ps1 -ApiBase https://skybridge.jerryskywalker.space -Json
```

Expected cloud facts:

- `/v1/version` commit matches
  `4473257548bd0fc26e05002d968f8525b37bac8b`.
- `/v1/version` image ref matches
  `ghcr.io/jerryskywalker/skybridge-agent-hub-server:sha-4473257548bd0fc26e05002d968f8525b37bac8b`.
- Cloud parity is ok.
- RC gate remains ok. After tag creation, a
  `tag_already_exists_on_target_commit` warning is expected.

## Later Operator Options

Future explicitly authorized goals may add:

- optional GitHub Release creation for the existing tag;
- optional Desktop packaging;
- optional real research workflow expansion with reviewed safety controls.

These are not part of RC1 handoff.

## Stop Hook Timeout Note

After MG341, Codex reported:

```text
Stop hook failed with: error: hook timed out after 30s
```

This is non-blocking for RC1 when the git state is clean, the tag is verified,
Deploy Cloud has passed, post-tag audit has passed, and required local checks
are green.

MG342 classifies the observed timeout through
`skybridge-bootstrap-alpha-rc1-handoff.ps1 -Command stop-hook-diagnose`. The
repository example Stop hook is bounded and does not explain the 30 second host
timeout; local Codex hook configuration is not read or mutated by this handoff.
