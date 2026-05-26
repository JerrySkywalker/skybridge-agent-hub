# PR Lifecycle Policy

SkyBridge treats GitHub pull requests as execution artifacts owned by the agent control plane. PR lifecycle metadata lets Hermes, workers, CI Guardian and merge automation distinguish safe child-task work from parent coordination work and from risky or stale branches.

## PR Types

- **Child task PR**: A PR produced by an executor worker for one queued SkyBridge task. These usually use `ai/edge-worker/<task-id>-...` branches, include a task ID in the title/body, and should be small enough for automatic CI and merge policy.
- **Parent or super-goal PR**: A PR that records or coordinates a larger operator goal, such as `ai/super-161-...`. Parent PRs may include design, code and progress-log changes. They are not merged automatically by default.
- **Tracking or progress PR**: A docs-only PR that records run status, progress logs or coordination notes without completing a child task. These are low risk but should not be confused with executable task results.
- **Duplicate PR**: A PR whose dedupe key or changed-file set substantially overlaps another open or already merged PR for the same project/task intent.
- **Stale PR**: A PR whose head branch is behind its base, has old pending checks, or has not changed within the policy window.
- **Conflicting PR**: A PR GitHub reports as not mergeable, dirty or blocked by conflicts. A stale PR can become conflicting after another PR merges.
- **High-risk PR**: A PR touching secrets, workflow files, deployment paths, production config, auth boundaries, broad code surfaces or other blocked paths.
- **Blocked PR**: A PR that cannot proceed safely because checks failed, mergeability is blocked, risk is high, required metadata is missing or a human decision is required.
- **Auto-merge candidate**: A low-risk PR with allowed changed paths, required checks present and green, mergeable state, no duplicate conflicts and an eligible lifecycle type.
- **Human-review-required PR**: Any parent/super-goal, high-risk, conflicting, ambiguous, duplicate-sensitive or policy-exception PR that should not auto-merge.

## Default Policy

- Child task PRs default to auto PR plus auto-merge when eligible.
- Parent/super-goal PRs default to auto PR plus manual merge.
- High-risk PRs may be opened for review, but auto-merge is disabled and a human notification should be sent.
- Duplicate or conflicting PRs should be blocked, closed or superseded according to policy. Closing requires an explanatory comment and explicit coordinator policy.
- Merge coordination starts in per-project serial mode so only one eligible child PR per project is advanced at a time.

## Planner Feedback

Planner prompts must receive compact PR/task state so Hermes can avoid repeating completed work. The compact state should include task IDs, PR URLs, changed files, dedupe keys, CI status, merge status, open file locks and a `do_not_repeat` list.
