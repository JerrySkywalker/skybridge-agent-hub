# Release Tagging Runbook

1. Start on clean `main`.
2. Pull with `git pull --ff-only`.
3. Verify no active tasks, stale leases, runner lock, or open PRs.
4. Run release workflow guard report and tag safety gate.
5. Merge the release PR only after CI passes.
6. Return to `main`, pull, and run post-merge smokes.
7. Re-run tag safety gate.
8. Create the RC tag only if the gate passes.
9. Push the tag and report that existing workflows may run.

Do not create GitHub Release objects manually. Do not upload artifacts manually.

`token_printed=false`
