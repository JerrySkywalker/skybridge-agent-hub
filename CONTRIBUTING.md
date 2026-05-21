# Contributing

This repository is open source and AI-agent friendly.

## Branch naming

```text
ai/<goal-id>-<slug>
feat/<topic>
fix/<topic>
docs/<topic>
```

## Pull request requirements

Every PR should include:

- Summary
- Tests
- Risk level
- Rollback notes
- Related goal file or issue

## Risk labels

```text
risk:low
risk:medium
risk:high
needs-human-after-defense
ai-generated
yolo
```

## Public repository safety

Do not run untrusted public PR code on self-hosted runners.

External PRs should use GitHub-hosted runners without secrets.

PR-triggered workflows must not use production deploy keys, self-hosted runners or privileged Docker operations.
