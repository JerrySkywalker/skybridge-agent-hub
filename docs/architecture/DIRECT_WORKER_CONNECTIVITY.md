# Direct Worker Connectivity

SkyBridge workers should connect directly to the SkyBridge Server API. SSH tunnels are useful during development, but they are not the normal worker path for a cloud control plane.

## Connectivity Modes

Local development:

```text
http://127.0.0.1:8787
```

Cloud control plane:

```text
https://skybridge.example.invalid
```

Remote workers authenticate to SkyBridge with a worker bearer token. The token is local-only worker configuration, read from an environment variable or a local token file. It must never be committed or printed.

## Worker Request Flow

```text
worker profile
  -> register worker
  -> heartbeat
  -> poll queued tasks
  -> claim one task
  -> execute locally through an ExecutorAdapter
  -> complete/fail/requeue task
  -> attach EvidenceSummary
```

SkyBridge Server remains the authoritative state source. The worker machine is an execution cache: repository checkout, Codex logs, validation output and local runtime state stay local unless a safe summary is explicitly reported.

## Adapter Boundaries

Hermes remains a private `PlannerAdapter`. It may create goals or tasks through SkyBridge APIs, but the Hermes API itself must not be exposed publicly.

Codex remains a local `ExecutorAdapter`. The worker invokes Codex locally and reports only safe task summaries, PR links and evidence metadata.

GitHub remains an `SCM/CI Provider`, and public PR safety is controlled by the existing lifecycle and merge policy. Direct worker connectivity does not enable unattended parent PR auto-merge.

ntfy remains a `NotificationProvider`. Notification credentials are separate from worker auth and must not be sent to SkyBridge as task data.

## Why SSH Tunnels Are Development-Only

SSH tunnels are convenient for private local experiments, especially around Hermes supervision. They are brittle as a worker transport because they hide worker identity, complicate audit, and couple normal worker operation to a developer session.

The durable path is:

```text
local worker -> HTTPS SkyBridge API -> server-side task and goal state
```

## Threat Model

Stolen worker token:

- attacker may register or heartbeat as a worker and attempt task mutations;
- mitigation is short-lived/scoped tokens in future, rotation, HTTPS, no token logging and fast disable.

Rogue worker:

- worker may claim tasks it should not run;
- mitigation is project allow-listing in profiles, server-side worker route auth, task risk policy and no production-deploy profile capability.

Replay:

- a captured bearer token can be reused until rotated;
- current foundation relies on HTTPS and rotation. Request signing/nonces are deferred.

Degraded or offline worker:

- worker must not claim new tasks when SkyBridge, GitHub auth, Codex, repo state or token configuration is degraded;
- loop state should pause safely and report a bounded reason.

Public PR safety:

- direct connectivity does not bypass PR lifecycle policy;
- high-risk PRs remain manual;
- parent PRs remain manual unless a future explicit policy changes that boundary.

## Current Auth Boundary

The first implementation supports a single token via `SKYBRIDGE_WORKER_TOKEN` or one-token-per-line files through `SKYBRIDGE_WORKER_TOKENS_FILE`. It protects worker-sensitive API routes when tokens are configured. Local development without configured tokens remains no-auth to preserve fixture smokes.

Future work should add issued worker identities, token rotation APIs, token revocation, per-worker/project scopes and replay-resistant request signing.
