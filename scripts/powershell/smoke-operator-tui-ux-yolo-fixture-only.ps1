. "$PSScriptRoot\operator-tui-smoke-common.ps1"

$result = Invoke-OperatorTuiUxYoloSmoke `
  -Name "operator-tui-ux-yolo-fixture-only" `
  -Scenario "yolo-fixture-only" `
  -Reset

Assert-True $result.report.yolo_fixture_only_available "yolo_fixture_only_available"
Assert-True $result.report.yolo_fixture_only "yolo_fixture_only"
Assert-True $result.report.yolo_skips_exact_confirmations_only_in_fixture_mode "yolo_skips_exact_confirmations_only_in_fixture_mode"
Assert-True $result.report.yolo_real_execution_blocked "yolo_real_execution_blocked"
Assert-True $result.report.yolo_branch_pr_blocked "yolo_branch_pr_blocked"
Assert-True $result.report.yolo_queue_worker_blocked "yolo_queue_worker_blocked"
if ($result.snapshot -notmatch "yolo_fixture_only=true") { throw "YOLO fixture-only banner missing." }
Assert-False $result.report.token_printed "token_printed"

Complete-Smoke "operator-tui-ux-yolo-fixture-only"
