. "$PSScriptRoot\operator-tui-smoke-common.ps1"

$result = Invoke-OperatorTuiUxYoloSmoke `
  -Name "operator-tui-ux-confirmation-buffer" `
  -Scenario "confirmation-buffer" `
  -Reset

Assert-True $result.confirmation.confirmation_buffer_starts_empty "confirmation_buffer_starts_empty"
Assert-True $result.confirmation.action_hotkey_not_inserted_into_confirmation "action_hotkey_not_inserted_into_confirmation"
Assert-True $result.confirmation.ctrl_u_resets_length_zero "ctrl_u_resets_length_zero"
Assert-True $result.confirmation.esc_cancels_and_clears_buffer "esc_cancels_and_clears_buffer"
Assert-True $result.confirmation.successful_submit_clears_buffer "successful_submit_clears_buffer"
Assert-True $result.confirmation.mismatch_preserves_diagnostics "mismatch_preserves_diagnostics"
Assert-True $result.confirmation.paste_exact_once_has_expected_length "paste_exact_once_has_expected_length"
Assert-True $result.confirmation.duplicate_paste_detection_available "duplicate_paste_detection_available"
Assert-True $result.confirmation.likely_duplicate_paste "likely_duplicate_paste"
Assert-False $result.confirmation.raw_input_persisted "raw_input_persisted"
Assert-False $result.confirmation.token_printed "token_printed"

Complete-Smoke "operator-tui-ux-confirmation-buffer"
