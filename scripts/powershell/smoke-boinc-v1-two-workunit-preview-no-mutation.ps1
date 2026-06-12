. "$PSScriptRoot/smoke-boinc-v1-common.ps1"
$preview = Invoke-BoincV1PreviewJson -Command "two-workunit-preview"
Assert-True ([bool]$preview.no_mutation) "Preview must report no_mutation=true."
Assert-False ([bool]$preview.task_created) "Preview must not create tasks."
Assert-False ([bool]$preview.task_claimed) "Preview must not claim tasks."
Assert-False ([bool]$preview.codex_executed) "Preview must not execute Codex."
Assert-False ([bool]$preview.pr_created) "Preview must not create PRs."
foreach ($workunit in $preview.workunits) {
  Assert-Equal $workunit.state "preview_only_not_created" "Workunit must remain preview-only."
  Assert-False ([bool]$workunit.task_created) "Workunit must not create task."
  Assert-False ([bool]$workunit.task_claimed) "Workunit must not claim task."
  Assert-False ([bool]$workunit.codex_executed) "Workunit must not execute Codex."
}
Write-SmokeResult "boinc-v1-two-workunit-preview-no-mutation"
