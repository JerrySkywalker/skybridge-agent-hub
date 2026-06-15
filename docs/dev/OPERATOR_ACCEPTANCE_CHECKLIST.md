# Operator Acceptance Checklist

Use this checklist before treating the portable package candidate as locally acceptable.

- Clean-room extraction is under `.agent/tmp/portable-package/clean-room/`.
- Extracted launcher `status` and `start-preview` pass.
- Extracted doctor and demo paths pass with fixture-safe data.
- Smoke fast is metadata-only and bounded.
- Artifact integrity report has package and manifest checksums.
- Fixture soak and restart cleanup rehearsal leave no background process.
- Manual install and uninstall remain preview-only.
- UI panels are read-only and expose no worker execute, apply, start, claim, install, or upload controls.
- `token_printed=false`.

