[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\smoke-productization-common.ps1"

function Invoke-Draft {
  param(
    [string]$DraftCommand,
    [string]$InputText = ""
  )
  $scriptPath = Join-Path $PSScriptRoot "skybridge-chat-to-task-draft.ps1"
  if ([string]::IsNullOrWhiteSpace($InputText)) {
    $raw = & $scriptPath -Command $DraftCommand -Json
  } else {
    $raw = & $scriptPath -Command $DraftCommand -InputText $InputText -Json
  }
  $text = ($raw | Out-String).Trim()
  Assert-NoUnsafeText $text
  $text | ConvertFrom-Json
}

function Assert-DraftSafety {
  param($Preview, [string]$Name)
  Assert-False $Preview.raw_prompt_persisted "$Name raw_prompt_persisted"
  Assert-False $Preview.raw_response_persisted "$Name raw_response_persisted"
  Assert-False $Preview.task_created "$Name task_created"
  Assert-False $Preview.campaign_created "$Name campaign_created"
  Assert-False $Preview.claim_created "$Name claim_created"
  Assert-False $Preview.execution_started "$Name execution_started"
  Assert-False $Preview.codex_run_called "$Name codex_run_called"
  Assert-False $Preview.matlab_run_called "$Name matlab_run_called"
  Assert-False $Preview.arbitrary_shell_enabled "$Name arbitrary_shell_enabled"
  Assert-TokenPrintedFalse $Preview

  Assert-False $Preview.session.raw_prompt_persisted "$Name session raw_prompt_persisted"
  Assert-False $Preview.session.raw_response_persisted "$Name session raw_response_persisted"
  Assert-False $Preview.draft.raw_prompt_persisted "$Name draft raw_prompt_persisted"
  Assert-False $Preview.draft.raw_response_persisted "$Name draft raw_response_persisted"
  Assert-False $Preview.draft.task_created "$Name draft task_created"
  Assert-False $Preview.draft.campaign_created "$Name draft campaign_created"
  Assert-False $Preview.draft.claim_created "$Name draft claim_created"
  Assert-False $Preview.draft.execution_started "$Name draft execution_started"
  Assert-False $Preview.draft.codex_run_called "$Name draft codex_run_called"
  Assert-False $Preview.draft.matlab_run_called "$Name draft matlab_run_called"
  Assert-False $Preview.draft.arbitrary_shell_enabled "$Name draft arbitrary_shell_enabled"
  Assert-TokenPrintedFalse $Preview.draft
}

$docs = Invoke-Draft -DraftCommand "sample-docs"
if ([string]$docs.schema -ne "skybridge.task_draft_preview.v1") { throw "Unexpected docs preview schema." }
if ([string]$docs.draft.schema -ne "skybridge.task_draft.v1") { throw "Unexpected docs draft schema." }
if ([string]$docs.draft_type -ne "task") { throw "Docs sample should produce a task draft." }
if ([string]$docs.template_id -ne "software-docs-task.v1") { throw "Docs sample template mismatch." }
if (@($docs.draft.required_capabilities) -notcontains "codex") { throw "Docs sample should include Codex as a future/report capability." }
Assert-DraftSafety $docs "docs"

$clarify = Invoke-Draft -DraftCommand "draft" -InputText "please help me with this"
if ([string]$clarify.status -ne "needs_clarification") { throw "Missing fields should produce a clarifying question." }
if ([string]$clarify.draft.schema -ne "skybridge.task_draft_clarifying_question.v1") { throw "Clarifying schema mismatch." }
if (@($clarify.blockers) -notcontains "required_fields_missing") { throw "Clarifying preview missing required_fields_missing blocker." }
Assert-DraftSafety $clarify "clarify"

$blocked = Invoke-Draft -DraftCommand "draft" -InputText "production deploy DNS Cloudflare OpenResty Authelia GitHub settings secrets"
if ([string]$blocked.status -ne "blocked") { throw "Unsafe request should be blocked." }
if (-not [bool]$blocked.unsafe_request_detected) { throw "Unsafe request flag missing." }
foreach ($reason in @("production_deploy", "dns_change", "cloudflare_change", "openresty_change", "authelia_change", "github_settings_change", "secret_request")) {
  if (@($blocked.blockers) -notcontains $reason) { throw "Blocked request missing reason: $reason" }
}
Assert-DraftSafety $blocked "blocked"

$commandText = Invoke-Draft -DraftCommand "draft" -InputText "pwsh -File ./scripts/do-work.ps1"
if (-not [bool]$commandText.command_text_detected) { throw "Command-looking text was not detected." }
if ([string]$commandText.status -ne "needs_clarification") { throw "Command-looking text without safe template should ask clarification." }
if (@($commandText.warnings) -notcontains "command_text_detected_not_executed") { throw "Command-looking warning missing." }
Assert-DraftSafety $commandText "commandText"

$safeSummary = Invoke-Draft -DraftCommand "safe-summary" -InputText "write docs report"
if ([string]$safeSummary.schema -ne "skybridge.chat_to_task_safe_summary.v1") { throw "Safe summary schema mismatch." }
Assert-False $safeSummary.task_created "safe summary task_created"
Assert-False $safeSummary.execution_started "safe summary execution_started"
Assert-TokenPrintedFalse $safeSummary

[pscustomobject]@{
  ok = $true
  smoke = "chat-to-task-draft"
  docs_template = $docs.template_id
  clarifying_status = $clarify.status
  blocked_status = $blocked.status
  command_text_detected = $commandText.command_text_detected
  token_printed = $false
} | ConvertTo-Json -Depth 8 -Compress
