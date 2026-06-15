. "$PSScriptRoot\smoke-productization-common.ps1"
foreach ($path in @(
  "docs/dev/PORTABLE_LOCAL_BUNDLE_LAYOUT.md",
  "docs/dev/PORTABLE_LOCAL_BUNDLE_POLICY.md",
  "docs/dev/LAUNCHER_ERROR_MODEL.md",
  "docs/dev/LAUNCHER_SAFE_EXIT_CODES.md",
  "docs/dev/STOP_HOOK_DIAGNOSTICS.md",
  "docs/dev/STOP_HOOK_TIMEOUT_RUNBOOK.md",
  "docs/dev/PORTABLE_LOCAL_BUNDLE_RC.md",
  "docs/dev/PORTABLE_LOCAL_BUNDLE_RC_RELEASE_NOTES.md",
  "docs/dev/PORTABLE_LOCAL_BUNDLE_NEXT_ROADMAP.md"
)) { Assert-FileExists $path }
Complete-Smoke "portable-bundle-docs-present"
