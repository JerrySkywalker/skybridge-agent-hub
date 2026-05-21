# ADR 0001: Thesis YOLO Mode

## Status

Accepted for initial development.

## Context

The maintainer is busy with thesis defense and wants AI agents to continue development with minimal interruptions.

## Decision

Use a high-autonomy local Codex workflow with hard safety boundaries:

- Codex can edit repository files and run tests.
- Codex can auto-repair failures.
- Codex can create branches and PRs.
- Production deployment remains image-based and rollback-capable.
- Secrets and production configs are hard-denied.

## Consequences

Positive:

- Minimal human attention required.
- Work continues during thesis defense.
- Failures are surfaced by notification.

Negative:

- Code quality may vary.
- Some PRs may require later cleanup.
- Strong test coverage becomes more important.
