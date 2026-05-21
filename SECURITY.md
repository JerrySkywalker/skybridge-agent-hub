# Security Policy

## Secrets

Never commit:

- `.env`
- API keys
- GitHub tokens
- ntfy passwords
- SSH keys
- production server credentials
- cloud provider credentials

## Agent Safety

The default agent mode is autonomous but bounded:

- allowed: repository edits, tests, docs, local Docker dev/test;
- denied: production secrets, destructive cleanup, force-push main, server root config.

## Reporting

For a personal project, open a private issue or contact the maintainer directly.
