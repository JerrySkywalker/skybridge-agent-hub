. "$PSScriptRoot\smoke-productization-common.ps1"
$report = Invoke-JsonScript "skybridge-product-profile.ps1" @("-Command", "report")
Assert-True $report.ok "profile report ok"
foreach ($profile in $report.profiles) {
  Assert-False $profile.execution_enabled "execution_enabled"
  Assert-False $profile.queue_apply_enabled "queue_apply_enabled"
  Assert-False $profile.remote_execution_enabled "remote_execution_enabled"
  Assert-False $profile.arbitrary_command_enabled "arbitrary_command_enabled"
  Assert-False $profile.trusted_docs_auto_merge_enabled "trusted_docs_auto_merge_enabled"
  Assert-TokenPrintedFalse $profile
}
Complete-Smoke "product-profile-contract"
