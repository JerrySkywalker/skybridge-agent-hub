. "$PSScriptRoot\smoke-productization-common.ps1"

$outputDir = ".agent/tmp/hermes-planner-provider/smoke-preview-$([guid]::NewGuid().ToString('N'))"
$result = Invoke-JsonScript "skybridge-hermes-planner-provider.ps1" @(
  "-Command", "preview",
  "-OutputDir", $outputDir,
  "-Objective", "Draft an unapproved MG367A Vite chunk remediation candidate goal."
)

if ($result.schema -ne "skybridge.hermes_planner_provider.v1") { throw "Unexpected Hermes planner provider schema." }
if ($result.mode -ne "preview") { throw "Unexpected mode." }
Assert-True $result.request_preview_generated "request_preview_generated"
Assert-False $result.live_call_attempted "live_call_attempted"
Assert-False $result.candidate_goal_generated "candidate_goal_generated"
Assert-False $result.candidate_approved "candidate_approved"
Assert-False $result.candidate_appended "candidate_appended"
Assert-False $result.task_created "task_created"
Assert-False $result.execution_started "execution_started"
Assert-TokenPrintedFalse $result

Complete-Smoke "hermes-planner-provider-preview"
