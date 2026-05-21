# Notification Providers

SkyBridge uses ntfy first, with a provider matrix prepared for Apprise, Gotify, Bark, WeCom, FCM and Xiaomi Push.

## Provider Matrix

| Provider | Required configuration | Current behavior without credentials |
| --- | --- | --- |
| ntfy | `NTFY_TOPIC_URL`, optional `NTFY_TOKEN` | Structured `skipped` result |
| Apprise | `APPRISE_URL` | Structured `skipped` result |
| Gotify | `GOTIFY_URL` | Structured `skipped` result |
| Bark | `BARK_URL` | Structured `skipped` result |
| WeCom | `WECOM_WEBHOOK_URL` | Structured `skipped` result |
| FCM | `FCM_SERVER_KEY` | Structured `skipped` result |
| Xiaomi Push | `XIAOMI_PUSH_SECRET` | Structured `skipped` result |

Provider status is exposed at `GET /v1/notifications/providers`. The endpoint reports whether a provider is configured without returning credential values.

## Job Shape

Notification attempts are stored as job-shaped records:

- `id`
- `category`
- `severity`
- `title` and `body` inside `message`
- `source_event_id`
- `target` and `provider`
- `dedupe_key`
- `status`: `pending`, `skipped`, `sent` or `failed`
- `retry_count`
- `createdAt` and `updatedAt`

Missing credentials should skip or fail a job record; they must not crash the server.
