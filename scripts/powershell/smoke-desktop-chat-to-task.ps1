[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\smoke-productization-common.ps1"

$desktopSource = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "apps\desktop\src\main.tsx")
$desktopBridge = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "apps\desktop\src-tauri\src\lib.rs")
$clientSource = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "packages\client\src\index.ts")
$plannerSource = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "scripts\powershell\skybridge-chat-to-task-draft.ps1")

foreach ($needle in @(
  "Bootstrap Alpha Chat-to-Task",
  "Natural-language request",
  "Generate draft preview",
  "MATLAB sample",
  "Docs sample",
  "Review and Submit (MG328 future work)",
  "task_created=false",
  "campaign_created=false; claim_created=false",
  "execution_started=false; codex_run_called=false; matlab_run_called=false; token_printed=false",
  "raw_prompt_persisted",
  "raw_response_persisted",
  "arbitrary_shell_enabled",
  "skybridge.task_draft_preview.v1",
  "fixtureChatToTaskDraftPreview",
  "TaskDraftPreview"
)) {
  if ($desktopSource -notmatch [regex]::Escape($needle)) { throw "Desktop Chat-to-Task panel missing text: $needle" }
}

foreach ($needle in @(
  "chat_to_task_draft",
  "run_chat_to_task_draft",
  "skybridge-chat-to-task-draft.ps1",
  "chat-to-task deterministic draft preview requested"
)) {
  if ($desktopBridge -notmatch [regex]::Escape($needle)) { throw "Desktop bridge missing Chat-to-Task wiring: $needle" }
}

foreach ($needle in @(
  "skybridge.chat_to_task_session.v1",
  "skybridge.task_draft.v1",
  "skybridge.campaign_draft.v1",
  "skybridge.task_draft_clarifying_question.v1",
  "skybridge.task_draft_preview.v1",
  "fixtureMatlabChatToTaskDraft",
  "fixtureChatToTaskDraftPreview",
  "task_created: false",
  "campaign_created: false",
  "claim_created: false",
  "execution_started: false",
  "codex_run_called: false",
  "matlab_run_called: false",
  "arbitrary_shell_enabled: false",
  "token_printed: false"
)) {
  if ($clientSource -notmatch [regex]::Escape($needle)) { throw "Client fixture missing Chat-to-Task contract text: $needle" }
}

foreach ($needle in @(
  "deterministic-local-chat-to-task.v1",
  "matlab-parameter-sweep.v1",
  "software-docs-task.v1",
  "blocked-request.v1",
  "needs-clarification.v1"
)) {
  if ($plannerSource -notmatch [regex]::Escape($needle)) { throw "Planner source missing deterministic template text: $needle" }
}

$sample = & (Join-Path $PSScriptRoot "skybridge-chat-to-task-draft.ps1") -Command sample-matlab -Json
$sampleText = ($sample | Out-String).Trim()
Assert-NoUnsafeText $sampleText
$preview = $sampleText | ConvertFrom-Json
if ([string]$preview.schema -ne "skybridge.task_draft_preview.v1") { throw "Planner fixture contract mismatch." }
Assert-False $preview.execution_started "desktop fixture execution_started"
Assert-False $preview.codex_run_called "desktop fixture codex_run_called"
Assert-False $preview.matlab_run_called "desktop fixture matlab_run_called"
Assert-TokenPrintedFalse $preview

[pscustomobject]@{
  ok = $true
  smoke = "desktop-chat-to-task"
  panel_contract = "skybridge.task_draft_preview.v1"
  task_created = $false
  campaign_created = $false
  claim_created = $false
  execution_started = $false
  codex_run_called = $false
  matlab_run_called = $false
  arbitrary_shell_enabled = $false
  token_printed = $false
} | ConvertTo-Json -Depth 8 -Compress
