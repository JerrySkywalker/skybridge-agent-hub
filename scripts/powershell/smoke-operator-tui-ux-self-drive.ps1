. "$PSScriptRoot\operator-tui-smoke-common.ps1"

Invoke-OperatorTuiCargoCheck
$rejectOutputDir = ".agent/tmp/operator-tui/ux-yolo-self-drive-reject"
& cargo run --quiet --manifest-path apps/operator-tui/Cargo.toml -- `
  --self-drive-dry-run `
  --output-dir $rejectOutputDir 2>$null | Out-Null
if ($LASTEXITCODE -eq 0) {
  throw "Self-drive must reject runs without --yolo-fixture-only."
}

$result = Invoke-OperatorTuiUxYoloSmoke `
  -Name "operator-tui-ux-self-drive" `
  -Scenario "self-drive" `
  -Reset

Assert-True $result.report.self_drive_available "self_drive_available"
Assert-True $result.report.self_drive_requires_fixture_only "self_drive_requires_fixture_only"
Assert-True $result.report.self_drive_completed_full_fixture_flow "self_drive_completed_full_fixture_flow"
Assert-True $result.self_drive.self_drive_completed_full_fixture_flow "self_drive_report completed"
Assert-True $result.self_drive.confirmation_dialog_yolo_bypass_recorded "confirmation_dialog_yolo_bypass_recorded"
if (@($result.self_drive.step_history).Count -lt 8) { throw "Self-drive step history incomplete." }
Assert-False $result.report.token_printed "token_printed"

Complete-Smoke "operator-tui-ux-self-drive"
