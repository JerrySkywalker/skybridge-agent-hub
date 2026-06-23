[CmdletBinding()]
param(
  [ValidateSet("draft", "sample-matlab", "sample-docs", "status", "safe-summary")]
  [string]$Command = "draft",
  [string]$InputText = "",
  [string]$ProjectId = "skybridge-agent-hub",
  [switch]$Json
)

$ErrorActionPreference = "Stop"

$PlannerId = "deterministic-local-chat-to-task.v1"
$MatlabSample = "帮我用 MATLAB 跑第四章参数扫描实验，eta=2..10，h=500/700km，P=6/8/10，输出 summary 和报告。"
$DocsSample = "Draft a software docs report for Bootstrap Alpha worker setup and summarize the current disabled execution boundary."

function Get-Sha256Hex {
  param([string]$Text)
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
    $hash = $sha.ComputeHash($bytes)
    -join ($hash | ForEach-Object { $_.ToString("x2") })
  } finally {
    $sha.Dispose()
  }
}

function Get-SafeInputPreview {
  param([string]$Text)
  $preview = ($Text -replace "\s+", " ").Trim()
  $preview = $preview -replace "(?i)authorization\s*[:=]\s*bearer\s+\S+", "authorization=[redacted]"
  $preview = $preview -replace "(?i)bearer\s+[A-Za-z0-9_.-]{12,}", "bearer [redacted]"
  $preview = $preview -replace "sk-[A-Za-z0-9_-]{12,}", "[redacted-api-key]"
  $preview = $preview -replace "gh[pousr]_[A-Za-z0-9_]{12,}", "[redacted-github-token]"
  $preview = $preview -replace "-----BEGIN [A-Z ]*PRIVATE KEY-----", "[redacted-private-key]"
  if ($preview.Length -gt 200) {
    return $preview.Substring(0, 197) + "..."
  }
  if ([string]::IsNullOrWhiteSpace($preview)) {
    return "empty_input"
  }
  $preview
}

function Test-CommandText {
  param([string]$Text)
  $pattern = "(?i)(^|\s)(pwsh|powershell|cmd(\.exe)?\s*/c|bash|sh\s+-c|rm\s+-rf|curl\s+|Invoke-RestMethod|Invoke-WebRequest|docker\s+|git\s+(push|reset|checkout)|npm\s+|pnpm\s+|python\s+)"
  return [bool]($Text -match $pattern)
}

function Get-UnsafeReasons {
  param([string]$Text)
  $checks = [ordered]@{
    production_deploy = "(?i)\bproduction\s+deploy\b|\bprod\s+deploy\b"
    dns_change = "(?i)\bdns\b"
    cloudflare_change = "(?i)\bcloudflare\b"
    openresty_change = "(?i)\bopenresty\b"
    authelia_change = "(?i)\bauthelia\b"
    github_settings_change = "(?i)github\s+settings|branch\s+protection"
    secret_request = "(?i)\bsecret(s)?\b|credential|token|cookie|private\s+key"
    arbitrary_shell_request = "(?i)arbitrary\s+shell|run\s+this\s+command|execute\s+shell"
    unbounded_run = "(?i)unbounded\s+run|run\s+forever|daemon\s+auto"
    worker_loop_start = "(?i)start\s+worker\s+loop|worker\s+loop\s+start"
  }
  $reasons = @()
  foreach ($entry in $checks.GetEnumerator()) {
    if ($Text -match $entry.Value) { $reasons += $entry.Key }
  }
  $reasons
}

function New-SafetyFields {
  [ordered]@{
    raw_prompt_persisted = $false
    raw_response_persisted = $false
    task_created = $false
    campaign_created = $false
    claim_created = $false
    execution_started = $false
    codex_run_called = $false
    matlab_run_called = $false
    arbitrary_shell_enabled = $false
    token_printed = $false
  }
}

function New-Session {
  param(
    [string]$Hash,
    [string]$Preview
  )
  $safety = New-SafetyFields
  [pscustomobject]([ordered]@{
    schema = "skybridge.chat_to_task_session.v1"
    session_id = "chat_draft_$($Hash.Substring(0, 12))"
    project_id = $ProjectId
    planner_id = $PlannerId
    input_preview = $Preview
    input_hash = $Hash
  } + $safety)
}

function New-DraftCommon {
  param(
    [string]$Hash,
    [string]$Preview,
    [string]$DraftType,
    [string]$TemplateId,
    [string]$Title,
    [string]$Summary,
    [string]$Risk,
    [string[]]$RequiredCapabilities,
    [string[]]$AllowedPaths,
    [string[]]$BlockedPaths,
    [string[]]$Validation,
    [string]$RunnerId,
    [string[]]$EvidenceSchema
  )
  $safety = New-SafetyFields
  [ordered]@{
    draft_id = "draft_$($DraftType)_$($Hash.Substring(0, 12))"
    draft_type = $DraftType
    template_id = $TemplateId
    project_id = $ProjectId
    title = $Title
    summary = $Summary
    risk = $Risk
    required_capabilities = @($RequiredCapabilities)
    allowed_paths = @($AllowedPaths)
    blocked_paths = @($BlockedPaths)
    validation = @($Validation)
    runner_id = $RunnerId
    evidence_schema = @($EvidenceSchema)
    planner_id = $PlannerId
    input_preview = $Preview
    input_hash = $Hash
  } + $safety
}

function New-MatlabDraft {
  param([string]$Text, [string]$Hash, [string]$Preview)
  $needsReport = [bool]($Text -match "(?i)report|summary|报告|总结")
  $capabilities = @("windows", "powershell", "matlab")
  if ($needsReport) { $capabilities += "codex" }
  $common = New-DraftCommon `
    -Hash $Hash `
    -Preview $Preview `
    -DraftType "campaign" `
    -TemplateId "matlab-parameter-sweep.v1" `
    -Title "Chapter 4 MATLAB parameter sweep" `
    -Summary "Preview a bounded MATLAB parameter sweep for eta, h, and P values with safe summary/report outputs." `
    -Risk "local_experiment" `
    -RequiredCapabilities $capabilities `
    -AllowedPaths @("results/skybridge/**", "docs/experiments/**") `
    -BlockedPaths @(".env", "secrets/**", "deploy/**", ".git/**") `
    -Validation @(
      "Confirm MATLAB is available locally.",
      "Confirm experiment entrypoint before future execution.",
      "Validate eta range, h values, and P values before future execution.",
      "Write outputs only under results/skybridge/** and docs/experiments/**.",
      "Do not execute arbitrary shell commands."
    ) `
    -RunnerId "matlab-parameter-sweep-runner.v1" `
    -EvidenceSchema @("run_manifest", "parameter_matrix", "result_summary", "report_path", "audit_summary")
  $common.schema = "skybridge.campaign_draft.v1"
  $common.inputs = [ordered]@{
    eta_range = @(2, 10)
    h_km = @(500, 700)
    p_values = @(6, 8, 10)
    outputs = if ($needsReport) { @("summary", "report") } else { @("summary") }
  }
  [pscustomobject]$common
}

function New-DocsDraft {
  param([string]$Hash, [string]$Preview, [bool]$CommandTextDetected)
  $validation = @(
    "Keep changes under docs/** or reports/skybridge/**.",
    "Do not mutate deployment, server root, GitHub settings, or secrets.",
    "Return a safe report path, source references, and validation status only."
  )
  if ($CommandTextDetected) {
    $validation += "Command-looking text is advisory only and must not be executed."
  }
  $common = New-DraftCommon `
    -Hash $Hash `
    -Preview $Preview `
    -DraftType "task" `
    -TemplateId "software-docs-task.v1" `
    -Title "Software documentation/report draft" `
    -Summary "Preview a documentation or analysis report task with safe evidence and no execution." `
    -Risk "docs_only" `
    -RequiredCapabilities @("windows", "powershell", "git", "codex") `
    -AllowedPaths @("docs/**", "reports/skybridge/**") `
    -BlockedPaths @(".env", "secrets/**", "deploy/**", ".git/**") `
    -Validation $validation `
    -RunnerId "codex-analysis-report-runner.v1" `
    -EvidenceSchema @("report_path", "source_references", "validation_status", "audit_summary")
  $common.schema = "skybridge.task_draft.v1"
  $common.inputs = [ordered]@{
    output_kind = "summary_report"
    docs_only = $true
    command_text_detected = $CommandTextDetected
  }
  [pscustomobject]$common
}

function New-ClarifyingDraft {
  param([string]$Hash, [string]$Preview, [bool]$CommandTextDetected)
  $common = New-DraftCommon `
    -Hash $Hash `
    -Preview $Preview `
    -DraftType "clarifying_question" `
    -TemplateId "needs-clarification.v1" `
    -Title "Clarify task draft request" `
    -Summary "The deterministic planner needs more bounded task details before emitting a task or campaign draft." `
    -Risk "needs_clarification" `
    -RequiredCapabilities @() `
    -AllowedPaths @() `
    -BlockedPaths @(".env", "secrets/**", "deploy/**", ".git/**") `
    -Validation @("Provide template intent, project scope, allowed paths, and expected evidence before submission review.") `
    -RunnerId "not-selected-preview-only" `
    -EvidenceSchema @("clarifying_answer")
  $common.schema = "skybridge.task_draft_clarifying_question.v1"
  $common.questions = @(
    "Which template should this become: MATLAB parameter sweep, software docs/report, or another future template?",
    "What project scope and allowed output paths should be used?",
    "What evidence should the operator review after future execution?"
  )
  if ($CommandTextDetected) {
    $common.questions += "The input contains command-looking text. Should it be converted into template parameters instead of executable text?"
  }
  $common.blocked = $false
  [pscustomobject]$common
}

function New-BlockedDraft {
  param(
    [string]$Hash,
    [string]$Preview,
    [string[]]$Reasons
  )
  $common = New-DraftCommon `
    -Hash $Hash `
    -Preview $Preview `
    -DraftType "task" `
    -TemplateId "blocked-request.v1" `
    -Title "Blocked request preview" `
    -Summary "The request crosses Bootstrap Alpha safety boundaries and cannot become a task draft in MG326." `
    -Risk "blocked" `
    -RequiredCapabilities @() `
    -AllowedPaths @() `
    -BlockedPaths @(".env", "secrets/**", "deploy/**", ".git/**", "cloudflare/**", "openresty/**", "authelia/**") `
    -Validation @("Reject or rewrite the request as a bounded preview-only task.", "Do not create tasks, claims, campaigns, or execution.") `
    -RunnerId "blocked-preview-only" `
    -EvidenceSchema @("blocked_reason", "safe_rewrite_hint")
  $common.schema = "skybridge.task_draft.v1"
  $common.inputs = [ordered]@{
    blocked_reasons = @($Reasons)
  }
  [pscustomobject]$common
}

function New-Preview {
  param(
    [object]$Draft,
    [object]$Session,
    [string]$Status,
    [bool]$CommandTextDetected,
    [bool]$UnsafeRequestDetected,
    [string[]]$Blockers,
    [string[]]$Warnings,
    [string]$NextSafeAction
  )
  $safety = New-SafetyFields
  [pscustomobject]([ordered]@{
    schema = "skybridge.task_draft_preview.v1"
    ok = $true
    status = $Status
    draft_id = $Draft.draft_id
    draft_type = $Draft.draft_type
    template_id = $Draft.template_id
    project_id = $Draft.project_id
    planner_id = $PlannerId
    session = $Session
    draft = $Draft
    command_text_detected = $CommandTextDetected
    unsafe_request_detected = $UnsafeRequestDetected
    blockers = @($Blockers)
    warnings = @($Warnings)
    next_safe_action = $NextSafeAction
    input_preview = $Session.input_preview
    input_hash = $Session.input_hash
  } + $safety)
}

function New-DraftPreview {
  param([string]$Text)
  $hash = Get-Sha256Hex $Text
  $preview = Get-SafeInputPreview $Text
  $session = New-Session -Hash $hash -Preview $preview
  $commandTextDetected = Test-CommandText $Text
  $unsafeReasons = @(Get-UnsafeReasons $Text)
  $warnings = @("preview_only_no_task_creation_no_claim_no_execution")
  if ($commandTextDetected) { $warnings += "command_text_detected_not_executed" }

  if ($unsafeReasons.Count -gt 0) {
    $draft = New-BlockedDraft -Hash $hash -Preview $preview -Reasons $unsafeReasons
    return New-Preview `
      -Draft $draft `
      -Session $session `
      -Status "blocked" `
      -CommandTextDetected $commandTextDetected `
      -UnsafeRequestDetected $true `
      -Blockers $unsafeReasons `
      -Warnings $warnings `
      -NextSafeAction "reject_or_rewrite_as_preview_only_template"
  }

  if ($Text -match "(?i)matlab|参数扫描|sweep|eta\s*=|h\s*=|p\s*=") {
    $draft = New-MatlabDraft -Text $Text -Hash $hash -Preview $preview
    return New-Preview `
      -Draft $draft `
      -Session $session `
      -Status "preview" `
      -CommandTextDetected $commandTextDetected `
      -UnsafeRequestDetected $false `
      -Blockers @() `
      -Warnings $warnings `
      -NextSafeAction "review_preview_only"
  }

  if ($Text -match "(?i)report|summary|docs|documentation|readme|文档|报告|总结") {
    $draft = New-DocsDraft -Hash $hash -Preview $preview -CommandTextDetected $commandTextDetected
    return New-Preview `
      -Draft $draft `
      -Session $session `
      -Status "preview" `
      -CommandTextDetected $commandTextDetected `
      -UnsafeRequestDetected $false `
      -Blockers @() `
      -Warnings $warnings `
      -NextSafeAction "review_preview_only"
  }

  $draft = New-ClarifyingDraft -Hash $hash -Preview $preview -CommandTextDetected $commandTextDetected
  New-Preview `
    -Draft $draft `
    -Session $session `
    -Status "needs_clarification" `
    -CommandTextDetected $commandTextDetected `
    -UnsafeRequestDetected $false `
    -Blockers @("required_fields_missing") `
    -Warnings $warnings `
    -NextSafeAction "answer_clarifying_question"
}

if ($Command -eq "status") {
  $result = [pscustomobject]@{
    schema = "skybridge.chat_to_task_planner_status.v1"
    ok = $true
    planner_id = $PlannerId
    deterministic = $true
    preview_only = $true
    live_hermes_required = $false
    supported_templates = @("matlab-parameter-sweep.v1", "software-docs-task.v1", "blocked-request.v1", "needs-clarification.v1")
    task_created = $false
    campaign_created = $false
    claim_created = $false
    execution_started = $false
    codex_run_called = $false
    matlab_run_called = $false
    arbitrary_shell_enabled = $false
    token_printed = $false
  }
} else {
  $text = switch ($Command) {
    "sample-matlab" { if ([string]::IsNullOrWhiteSpace($InputText)) { $MatlabSample } else { $InputText } }
    "sample-docs" { if ([string]::IsNullOrWhiteSpace($InputText)) { $DocsSample } else { $InputText } }
    "safe-summary" { if ([string]::IsNullOrWhiteSpace($InputText)) { $DocsSample } else { $InputText } }
    default { $InputText }
  }
  $result = New-DraftPreview -Text $text
  if ($Command -eq "safe-summary") {
    $result = [pscustomobject]@{
      schema = "skybridge.chat_to_task_safe_summary.v1"
      ok = $true
      draft_id = $result.draft_id
      draft_type = $result.draft_type
      template_id = $result.template_id
      status = $result.status
      input_preview = $result.input_preview
      input_hash = $result.input_hash
      blockers = $result.blockers
      warnings = $result.warnings
      next_safe_action = $result.next_safe_action
      raw_prompt_persisted = $false
      raw_response_persisted = $false
      task_created = $false
      campaign_created = $false
      claim_created = $false
      execution_started = $false
      codex_run_called = $false
      matlab_run_called = $false
      arbitrary_shell_enabled = $false
      token_printed = $false
    }
  }
}

if ($Json) {
  $result | ConvertTo-Json -Depth 12
} else {
  $result | Format-List
}
