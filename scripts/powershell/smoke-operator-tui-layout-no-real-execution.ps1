. "$PSScriptRoot\operator-tui-smoke-common.ps1"

$result = Invoke-OperatorTuiLayoutSmoke `
  -Name "operator-tui-layout-no-real-execution" `
  -Scenario "no-real-execution" `
  -Reset

Assert-OperatorTuiLayoutNoRealExecution -Report $result.report
if ($result.report.active_tab -ne "Safety") { throw "Expected Safety tab for no-real-execution layout smoke." }
foreach ($needle in @(
  "real_task_execution_enabled=false",
  "real_branch_creation_enabled=false",
  "real_pr_creation_enabled=false",
  "worker_loop_started=false",
  "queue_runner_started=false",
  "run_forever_started=false",
  "token_printed=false"
)) {
  if ($result.compact_snapshot -notmatch [regex]::Escape($needle)) { throw "Safety snapshot missing: $needle" }
}

Complete-Smoke "operator-tui-layout-no-real-execution"
