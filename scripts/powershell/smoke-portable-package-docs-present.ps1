. "$PSScriptRoot\smoke-productization-common.ps1"
foreach ($path in @(
  "docs/dev/PORTABLE_PACKAGE_BUILDER.md",
  "docs/dev/PORTABLE_PACKAGE_EXCLUSION_POLICY.md",
  "docs/dev/PORTABLE_PACKAGE_MANIFEST.md",
  "docs/dev/PORTABLE_CONFIG_PROFILE.md",
  "docs/dev/PORTABLE_CONFIG_VALIDATION.md",
  "docs/dev/MANUAL_INSTALL_PREVIEW.md",
  "docs/dev/MANUAL_INSTALL_SAFETY_BOUNDARY.md",
  "docs/dev/MANUAL_UNINSTALL_PREVIEW.md",
  "docs/dev/PORTABLE_PACKAGE_RC.md",
  "docs/dev/PORTABLE_PACKAGE_RC_RELEASE_NOTES.md",
  "docs/dev/PORTABLE_PACKAGE_NEXT_ROADMAP.md"
)) { Assert-FileExists $path }
Complete-Smoke "portable-package-docs-present"
