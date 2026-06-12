# BOINC v1 Alpha Workunit A Human Review

After Goal 215 creates the Workunit A task PR, the repository must stop for human review.

## Review Checklist

- Confirm the PR changes only `docs/boinc-v1-alpha-workunit-a.md`.
- Confirm the document says it is BOINC-like v1 alpha Workunit A.
- Confirm it states Workunit B is blocked until Workunit A is human-reviewed and finalized.
- Confirm it states the resource gate passed.
- Confirm it states general bounded queue apply remains disabled.
- Confirm it includes `token_printed=false`.

## Next Step

After the Workunit A task PR is manually merged, run Goal 216. Goal 216 is responsible for finalizing Workunit A and deciding whether Workunit B can execute.

Do not auto-merge the task PR. Do not run Workunit B from Goal 215.
