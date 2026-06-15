. "$PSScriptRoot\smoke-productization-common.ps1"
foreach ($doc in @(
  "docs/dev/MANUAL_ONE_CLICK_LOCAL_SESSION.md",
  "docs/dev/LOCAL_SESSION_OPERATOR_RUNBOOK.md",
  "docs/dev/LOCAL_SESSION_HEALTH_DOCTOR.md",
  "docs/dev/LOCAL_SESSION_TROUBLESHOOTING.md",
  "docs/dev/LOCAL_SESSION_SAFE_LIMITATIONS.md",
  "docs/dev/OPERATOR_DEMO_MODE.md",
  "docs/dev/LOCAL_SESSION_DEMO_RUNBOOK.md",
  "docs/dev/MANUAL_SESSION_RC.md",
  "docs/dev/MANUAL_SESSION_RC_RELEASE_NOTES.md",
  "docs/dev/MANUAL_SESSION_NEXT_ROADMAP.md"
)) {
  Assert-FileExists $doc
}
Complete-Smoke "local-session-docs-present"
