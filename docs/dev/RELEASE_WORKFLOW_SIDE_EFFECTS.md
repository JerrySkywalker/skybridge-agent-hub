# Release Workflow Side Effects

SkyBridge release tagging is guarded by `scripts/powershell/skybridge-release-workflow-guard.ps1`.

The guard scans `.github/workflows/**` and classifies tag-triggered side effects before an RC tag is created. It records workflow names, trigger type, permissions, secret references by name only, and safe side-effect classes.

Current classified tag side effects:

- `release.yml`: release validation, release-note artifact upload, release-validation artifact upload, GHCR image publish.
- `build-image.yml`: Docker image build and GHCR publish on `v*` tags.

The goal does not manually create GitHub Release objects and does not manually upload artifacts. Existing workflows may upload workflow artifacts or publish images when a tag is pushed.

Reports:

- `.agent/tmp/release-guard/workflow-side-effects.json`
- `.agent/tmp/release-guard/workflow-side-effects.md`
- `.agent/tmp/release-guard/tag-safety-gate.json`

`token_printed=false`
