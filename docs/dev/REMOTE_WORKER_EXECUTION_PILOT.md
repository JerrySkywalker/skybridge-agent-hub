# Remote Worker Execution Pilot

Date: 2026-05-26

## remote-docs-exec-pilot-001

- Title: Remote docs execution pilot
- Risk: low
- Source: manual
- Target worker: `laptop-zenbookduo`
- Scope: docs-only; this task may modify only `docs/dev/REMOTE_WORKER_EXECUTION_PILOT.md`.

This pilot records the first low-risk proof that the cloud SkyBridge control plane can queue a documentation task for `laptop-zenbookduo`, the local edge worker can claim it through direct bearer-token authentication, and Codex can perform a bounded repository change under the worker's execution policy.

Expected worker-owned follow-up after Codex completes:

- validate the docs-only change;
- package the result as a child PR;
- run CI Guardian with the configured non-merge policy;
- report safe task evidence back to SkyBridge.

Evidence reported to SkyBridge should stay concise and redacted. It must not include raw command output, secrets, `.env` contents, production configuration, deployment credentials, GitHub settings, server root configuration, raw Codex logs or full patches.

Completion criteria for this pilot:

- only this file changed;
- validation result is attached by the edge worker;
- child PR and CI Guardian status are reported by the edge worker;
- no commit, push or PR creation is performed by the nested Codex run.
