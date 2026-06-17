# Manual Task Next Roadmap

The next goal can build on the local mock MVP without crossing the execution boundary.

Recommended sequence:

1. Add richer local queue history and filtering.
2. Add import/export of sanitized manual task reports.
3. Add an explicit provider abstraction for future Hermes preview mode.
4. Add a dry-run-only Hermes request builder that emits safe metadata without sending a live request.
5. Add a separate reviewed goal for any live provider call.
6. Keep worker execution and workunit/task/claim/task PR creation out of the manual task chat path.

Do not enable Hermes live calls, worker execution, queue apply, remote execution or arbitrary command dispatch without a future explicit goal.
