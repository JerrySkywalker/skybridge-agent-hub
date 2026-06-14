. "$PSScriptRoot\smoke-productization-common.ps1"
$plan = Invoke-JsonScript "skybridge-local-runtime.ps1" @("-Command", "plan")
foreach ($component in $plan.components) {
  Assert-False $component.starts_codex_worker "starts_codex_worker"
  if ([string]$component.command_preview -match "codex\s+exec|invoke-codex-task") { throw "Codex worker command found." }
}
Complete-Smoke "local-runtime-no-codex-worker"
