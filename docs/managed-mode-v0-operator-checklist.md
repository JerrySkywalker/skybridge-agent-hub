# Managed-Mode v0 Operator Checklist

- Managed-mode v0 processes workunits one at a time.
- The resource gate must pass before run apply.
- Each task PR waits for human review before merge.
- General bounded queue apply remains disabled.
- Confirm `token_printed=false` before proceeding.
