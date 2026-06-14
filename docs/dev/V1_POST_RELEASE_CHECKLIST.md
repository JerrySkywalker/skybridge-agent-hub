# V1 Post-release Checklist

After merging the release PR:

1. Switch to `main`.
2. Pull latest `main`.
3. Verify clean working tree.
4. Run release gate and post-release smokes.
5. Verify no open task PRs, active tasks, stale leases, or runner lock.
6. Create tag `v0.99.0-boinc-like-v1-controlled-release` only if it does not already exist.
7. Push tag.
8. Write safe release reports under `.agent/tmp/release/`.
9. Do not execute a new workunit.

Required invariant: `token_printed=false`.
