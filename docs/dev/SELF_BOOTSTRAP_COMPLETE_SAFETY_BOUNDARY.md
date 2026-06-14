# Self-bootstrap Complete Safety Boundary

Bootstrap complete is a controlled-mode milestone. It does not authorize new workunits, task creation, claims, task PRs, worker execution or production mutation.

## Disabled Capabilities

- remote execution
- arbitrary command dispatch
- global execution
- queue apply
- generic bounded queue apply
- start-all
- start-queue
- resume apply
- global trusted-docs auto-merge

## Allowed Release Operations

- read safe evidence reports
- run bounded smoke scripts
- write metadata-only release reports
- update docs and read-only UI surfaces
- create a release tag after the gate passes on clean main

## Trusted-docs Scope

Scoped trusted-docs merge is only for explicit exact PR approval and safe docs-only PRs. It must not merge code, config, server, production, GitHub settings or secret-related paths.

`token_printed=false`

