[CmdletBinding()]
param(
  [ValidateSet("status", "safe-summary", "report", "v2-report", "v3-report")]
  [string]$Command = "status",
  [switch]$Json
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
$ReportDir = Join-Path $RepoRoot ".agent\tmp\operator-acceptance"

function Write-SafeJson([string]$Path, $Value) {
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
  $Value | Add-Member -NotePropertyName token_printed -NotePropertyValue $false -Force
  $Value | ConvertTo-Json -Depth 50 | Set-Content -LiteralPath $Path -Encoding utf8
}

function Invoke-JsonScript([string]$Script, [string[]]$ScriptArgs) {
  $raw = & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot $Script) @ScriptArgs -Json
  if ($LASTEXITCODE -ne 0) { throw "$Script failed." }
  ($raw | Out-String).Trim() | ConvertFrom-Json
}

function New-AcceptanceReport {
  $cleanRoom = Invoke-JsonScript "skybridge-portable-package.ps1" @("-Command", "clean-room-rehearsal")
  $integrity = Invoke-JsonScript "skybridge-artifact-integrity.ps1" @("-Command", "report")
  $soak = Invoke-JsonScript "skybridge-local-soak.ps1" @("-Command", "report")
  $restartPath = Join-Path $RepoRoot ".agent\tmp\local-session\restart-cleanup-rehearsal-report.json"
  $restart = if (Test-Path -LiteralPath $restartPath) { Get-Content -Raw -LiteralPath $restartPath | ConvertFrom-Json } else { $null }
  $reproPath = Join-Path $RepoRoot ".agent\tmp\portable-package\package-rebuild-reproducibility-report.json"
  $repro = if (Test-Path -LiteralPath $reproPath) { Get-Content -Raw -LiteralPath $reproPath | ConvertFrom-Json } else { $null }
  $report = [pscustomobject]@{
    schema = "skybridge.operator_acceptance_report.v1"
    status = $(if ($cleanRoom.status -eq "passed" -and $integrity.clean_room_verified -eq $true -and $soak.status -eq "passed") { "passed" } else { "blocked" })
    clean_room_rehearsal_status = $cleanRoom.status
    extracted_launcher_status = $cleanRoom.validation.extracted_launcher_status
    doctor_status = $cleanRoom.validation.doctor_status
    demo_status = $cleanRoom.validation.demo_status
    smoke_fast_status = $cleanRoom.validation.smoke_fast_status
    artifact_integrity_status = $(if ($integrity.clean_room_verified -eq $true) { "passed" } else { "blocked" })
    reproducibility_status = $(if ($repro -and $repro.reproducible_manifest -eq $true -and $repro.reproducible_file_list -eq $true) { "passed" } else { "preview" })
    fixture_soak_status = $soak.status
    restart_cleanup_status = $(if ($restart -and $restart.status -eq "passed") { "passed" } else { "preview" })
    disabled_capabilities = @("codex_worker", "workunit_creation", "task_creation", "task_claim", "task_pr_creation", "generic_queue_apply", "start_all", "start_queue", "resume_apply", "remote_execution", "arbitrary_command_dispatch", "host_mutation", "upload", "install")
    known_limitations = @("repo-local clean-room rehearsal only", "archive is unsigned", "manual install remains preview-only", "no production deployment")
    next_recommended_goals = @("signed package planning", "operator visual QA", "local auth pairing implementation preview")
    token_printed = $false
  }
  Write-SafeJson (Join-Path $ReportDir "operator-acceptance-report.json") $report
  @(
    "# Operator Acceptance Report",
    "",
    "- schema: skybridge.operator_acceptance_report.v1",
    "- status: $($report.status)",
    "- clean_room_rehearsal_status: $($report.clean_room_rehearsal_status)",
    "- artifact_integrity_status: $($report.artifact_integrity_status)",
    "- fixture_soak_status: $($report.fixture_soak_status)",
    "- token_printed=false"
  ) | Set-Content -LiteralPath (Join-Path $ReportDir "operator-acceptance-report.md") -Encoding utf8
  $report
}

function New-AcceptanceV2Report {
  $install = Invoke-JsonScript "skybridge-install-sandbox.ps1" @("-Command", "report")
  $uninstall = Invoke-JsonScript "skybridge-uninstall-sandbox.ps1" @("-Command", "status")
  $upgradeRollback = Invoke-JsonScript "skybridge-upgrade-rollback-sandbox.ps1" @("-Command", "report")
  $migration = Invoke-JsonScript "skybridge-upgrade-rollback-sandbox.ps1" @("-Command", "migration-preview")
  $soak = Invoke-JsonScript "skybridge-local-soak.ps1" @("-Command", "extended-fixture-soak")
  $stability = Invoke-JsonScript "skybridge-local-soak.ps1" @("-Command", "stability-cleanup")
  $launcherValidation = Invoke-JsonScript "skybridge-install-sandbox.ps1" @("-Command", "verify")
  $report = [pscustomobject]@{
    schema = "skybridge.operator_acceptance_v2_report.v1"
    status = $(if ($install.status -eq "passed" -and $soak.status -eq "passed" -and $stability.status -eq "passed") { "passed" } else { "preview" })
    install_sandbox_status = $install.status
    uninstall_sandbox_status = $uninstall.status
    upgrade_sandbox_status = $(if ($upgradeRollback.upgrade_report) { $upgradeRollback.upgrade_report.status } else { "preview" })
    rollback_sandbox_status = $(if ($upgradeRollback.rollback_report) { $upgradeRollback.rollback_report.status } else { "preview" })
    version_channel_migration_preview_status = $migration.status
    extended_fixture_soak_status = $soak.status
    stability_cleanup_status = $stability.status
    extracted_sandbox_launcher_validation = $launcherValidation
    disabled_capabilities = @("codex_worker", "workunit_creation", "workunit_apply", "task_creation", "task_claim", "task_pr_creation", "generic_queue_apply", "start_all", "start_queue", "resume_apply", "remote_execution", "arbitrary_command_dispatch", "host_install", "host_uninstall", "upload", "github_release")
    known_limitations = @("sandbox-only install model", "local channel migration preview only", "unsigned archive", "no network update", "no GitHub release")
    next_safe_action = "Review sandbox reports and keep execution/apply controls disabled before Goal 265 planning."
    web_status = "read_only_sandbox_install_upgrade_soak_panels"
    desktop_status = "read_only_sandbox_install_upgrade_soak_panels"
    token_printed = $false
  }
  Write-SafeJson (Join-Path $ReportDir "operator-acceptance-v2-report.json") $report
  @(
    "# Operator Acceptance v2 Report",
    "",
    "- schema: skybridge.operator_acceptance_v2_report.v1",
    "- status: $($report.status)",
    "- install_sandbox_status: $($report.install_sandbox_status)",
    "- uninstall_sandbox_status: $($report.uninstall_sandbox_status)",
    "- upgrade_sandbox_status: $($report.upgrade_sandbox_status)",
    "- rollback_sandbox_status: $($report.rollback_sandbox_status)",
    "- version_channel_migration_preview_status: $($report.version_channel_migration_preview_status)",
    "- extended_fixture_soak_status: $($report.extended_fixture_soak_status)",
    "- stability_cleanup_status: $($report.stability_cleanup_status)",
    "- web_status: $($report.web_status)",
    "- desktop_status: $($report.desktop_status)",
    "- token_printed=false"
  ) | Set-Content -LiteralPath (Join-Path $ReportDir "operator-acceptance-v2-report.md") -Encoding utf8
  $report
}

function Invoke-JsonScriptOptional([string]$Script, [string[]]$ScriptArgs) {
  try {
    Invoke-JsonScript $Script $ScriptArgs
  } catch {
    [pscustomobject]@{ status = "blocked"; error = "safe_summary_unavailable"; token_printed = $false }
  }
}

function New-AcceptanceV3Report {
  $releaseGuard = Invoke-JsonScriptOptional "skybridge-release-workflow-guard.ps1" @("-Command", "report")
  $installer = Invoke-JsonScriptOptional "skybridge-installer-candidate.ps1" @("-Command", "report")
  $runtime = Invoke-JsonScriptOptional "skybridge-sandbox-installed-runtime.ps1" @("-Command", "report")
  $soak = Invoke-JsonScriptOptional "skybridge-install-soak.ps1" @("-Command", "report")
  $recovery = Invoke-JsonScriptOptional "skybridge-recovery-sandbox.ps1" @("-Command", "report")
  $releaseStatus = if ($releaseGuard.gate) { $releaseGuard.gate.gate } else { $releaseGuard.status }
  $installerStatus = $installer.status
  $runtimeStatus = $runtime.status
  $soakStatus = $soak.status
  $recoveryStatus = $recovery.status
  $report = [pscustomobject]@{
    schema = "skybridge.operator_acceptance_v3_report.v1"
    status = $(if ($releaseStatus -eq "passed" -and $installerStatus -eq "passed" -and $runtimeStatus -eq "passed" -and $soakStatus -eq "passed" -and $recoveryStatus -eq "passed") { "passed" } else { "preview" })
    release_workflow_side_effect_guard_status = $releaseStatus
    installer_candidate_status = $installerStatus
    sandbox_installed_runtime_status = $runtimeStatus
    extended_install_upgrade_rollback_soak_status = $soakStatus
    crash_recovery_sandbox_status = $recoveryStatus
    cleanup_hardening_status = $(if ($recovery.cleanup_hardening) { "passed" } else { "preview" })
    web_status = "read_only_installer_acceptance_panels"
    desktop_status = "read_only_installer_acceptance_cards"
    disabled_capabilities = @("codex_worker", "workunit_creation", "workunit_apply", "task_creation", "task_claim", "task_pr_creation", "generic_queue_apply", "start_all", "start_queue", "resume_apply", "remote_execution", "arbitrary_command_dispatch", "host_install", "host_uninstall", "registry", "startup", "scheduled_task", "service", "powercfg", "PATH", "manual_upload", "manual_github_release")
    known_limitations = @("sandboxed installer candidate only", "unsigned package", "no host install", "no network update", "existing tag workflows may publish images/artifacts after tag")
    next_safe_action = "Open PR, wait for CI, merge, run post-merge smokes, then run tag safety gate before tagging."
    token_printed = $false
  }
  Write-SafeJson (Join-Path $ReportDir "operator-acceptance-v3-report.json") $report
  @(
    "# Operator Acceptance v3 Report",
    "",
    "- schema: skybridge.operator_acceptance_v3_report.v1",
    "- status: $($report.status)",
    "- release_workflow_side_effect_guard_status: $($report.release_workflow_side_effect_guard_status)",
    "- installer_candidate_status: $($report.installer_candidate_status)",
    "- sandbox_installed_runtime_status: $($report.sandbox_installed_runtime_status)",
    "- extended_install_upgrade_rollback_soak_status: $($report.extended_install_upgrade_rollback_soak_status)",
    "- crash_recovery_sandbox_status: $($report.crash_recovery_sandbox_status)",
    "- cleanup_hardening_status: $($report.cleanup_hardening_status)",
    "- web_status: $($report.web_status)",
    "- desktop_status: $($report.desktop_status)",
    "- token_printed=false"
  ) | Set-Content -LiteralPath (Join-Path $ReportDir "operator-acceptance-v3-report.md") -Encoding utf8
  $report
}

$Result = switch ($Command) {
  "status" { [pscustomobject]@{ schema = "skybridge.operator_acceptance_report.v1"; status = "ready"; token_printed = $false } }
  "safe-summary" { [pscustomobject]@{ ok = $true; execution_enabled = $false; queue_apply_enabled = $false; remote_execution_enabled = $false; arbitrary_command_enabled = $false; token_printed = $false } }
  "report" { New-AcceptanceReport }
  "v2-report" { New-AcceptanceV2Report }
  "v3-report" { New-AcceptanceV3Report }
}

if ($Json) { $Result | ConvertTo-Json -Depth 50 } else { $Result | Format-List | Out-String }
