function New-SkybridgeOneAtATimePolicy {
  [pscustomobject]@{ schema = "skybridge.queue_policy.one_at_a_time.v1"; max_parallel_repo_mutations = 1; token_printed = $false }
}

function New-SkybridgeTwoWorkunitPreviewPolicy {
  [pscustomobject]@{
    schema = "skybridge.queue_policy.two_workunit_preview.v1"
    max_workunits_preview = 2
    max_apply_workunits = 0
    apply_enabled = $false
    multi_workunit_apply_enabled = $false
    no_next_execution_authorized = $true
    token_printed = $false
  }
}

function New-SkybridgeDrainPausePolicy {
  [pscustomobject]@{
    schema = "skybridge.queue_policy.drain_pause.v1"
    drain_after_current = $true
    pause_after_current = $true
    pause_new_claims = $true
    emergency_stop = "preview_only"
    apply_enabled = $false
    token_printed = $false
  }
}

Export-ModuleMember -Function New-SkybridgeOneAtATimePolicy, New-SkybridgeTwoWorkunitPreviewPolicy, New-SkybridgeDrainPausePolicy
