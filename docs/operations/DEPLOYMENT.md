# Deployment Notes

## Staging

Staging may be fully automatic after `main` passes CI.

## Production

Production should be tag/release based.

Recommended flow:

```text
tag pushed
build images
push GHCR
cloud server pulls image
backup
compose up
healthcheck
rollback on failure
notify
```

## Server path

Recommended path:

```text
/opt/skybridge
```

Do not store secrets in the public repository.
