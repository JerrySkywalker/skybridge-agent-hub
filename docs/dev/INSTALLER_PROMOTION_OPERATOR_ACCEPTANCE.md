# Installer Promotion Operator Acceptance

The operator acceptance flow gives reviewers a single read-only checkpoint for the installer promotion RC.

It confirms that real install, network update, manual upload, manual GitHub Release creation, worker execution, task claim, and queue apply remain disabled.

Reports are written under `.agent/tmp/operator-acceptance/`.
