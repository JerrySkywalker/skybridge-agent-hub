. "$PSScriptRoot\smoke-productization-common.ps1"
foreach ($doc in @(
  "docs/dev/REPO_LOCAL_LAUNCHER.md",
  "docs/dev/LOCAL_LAUNCHER_COMMAND_ROUTER.md",
  "docs/dev/LOCAL_LAUNCHER_SAFETY_MODEL.md",
  "docs/dev/LOCAL_DEMO_BUNDLE.md",
  "docs/dev/OPERATOR_WALKTHROUGH_DEMO.md",
  "docs/dev/LOCAL_DOCTOR_ACTION_GUIDE.md",
  "docs/dev/LOCAL_SESSION_RECOVERY_GUIDE.md",
  "docs/dev/LOCAL_LAUNCHER_RC.md",
  "docs/dev/LOCAL_LAUNCHER_RC_RELEASE_NOTES.md",
  "docs/dev/LOCAL_LAUNCHER_NEXT_ROADMAP.md"
)) { Assert-FileExists $doc }
Complete-Smoke "local-launcher-docs-present"
