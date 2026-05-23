# Controller Dry-Run Validation

Validate the SkyBridge Autonomous Iteration Controller dry-run path only.

Tasks:

- do not edit production configuration;
- do not use real secrets;
- do not deploy;
- verify branch name, Codex command shape, local metadata path, SkyBridge offline fail-open behavior and bootstrap notification no-send behavior.

Completion:

- `scripts/powershell/smoke-iteration-controller.ps1 -DryRun` passes.
