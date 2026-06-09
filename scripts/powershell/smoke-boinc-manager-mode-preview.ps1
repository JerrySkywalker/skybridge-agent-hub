. "$PSScriptRoot/smoke-boinc-manager-common.ps1"
$preview = Invoke-BoincManagerJson "mode-preview"
$required = @("standby", "armed_preview", "start_one_review", "bounded_queue_preview", "bounded_queue_apply_disabled", "managed_mode_disabled", "emergency_stop", "completed_bootstrap_trial")
$modeIds = @($preview.modes | ForEach-Object { $_.mode_id })
foreach ($mode in $required) {
  if ($modeIds -notcontains $mode) { throw "Missing BOINC mode: $mode" }
}
foreach ($mode in @($preview.modes)) {
  foreach ($field in @("mode_id", "display_name", "description", "enabled", "reason_disabled", "required_human_action", "allowed_actions", "blocked_actions", "next_safe_action", "token_printed")) {
    if (-not ($mode.PSObject.Properties.Name -contains $field)) { throw "Missing mode field $field on $($mode.mode_id)" }
  }
}
Write-SmokeResult "boinc-manager-mode-preview"
