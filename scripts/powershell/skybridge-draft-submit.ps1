param(
  [ValidateSet("preview", "submit", "sample-matlab-preview", "sample-matlab-submit-preview", "sample-docs-preview", "safe-summary", "status")]
  [string]$Command = "preview",
  [string]$InputJsonFile = "",
  [string]$ApiBase = "http://127.0.0.1:8787",
  [string]$TokenFile = "",
  [string]$ProjectId = "skybridge-agent-hub",
  [switch]$Confirm,
  [string]$ConfirmationText = "",
  [switch]$Json
)

$ErrorActionPreference = "Stop"

$ConfirmationPhrase = "I_UNDERSTAND_CREATE_QUEUED_DRAFT_RECORDS_ONLY_NO_EXECUTION"

function ConvertTo-SafeJson {
  param($Value)
  $Value | ConvertTo-Json -Depth 20
}

function Read-InputObject {
  if (-not [string]::IsNullOrWhiteSpace($InputJsonFile)) {
    if (-not (Test-Path -LiteralPath $InputJsonFile -PathType Leaf)) {
      throw "InputJsonFile not found."
    }
    return (Get-Content -Raw -LiteralPath $InputJsonFile | ConvertFrom-Json)
  }

  $planner = Join-Path $PSScriptRoot "skybridge-chat-to-task-draft.ps1"
  $plannerCommand = if ($Command -like "*matlab*") { "sample-matlab" } else { "sample-docs" }
  $raw = & pwsh -NoProfile -ExecutionPolicy Bypass -File $planner -Command $plannerCommand -ProjectId $ProjectId -Json
  ($raw | Out-String).Trim() | ConvertFrom-Json
}

function Get-AuthHeaders {
  $headers = @{}
  if (-not [string]::IsNullOrWhiteSpace($TokenFile)) {
    if (-not (Test-Path -LiteralPath $TokenFile -PathType Leaf)) {
      throw "TokenFile not found."
    }
    $token = (Get-Content -Raw -LiteralPath $TokenFile).Trim()
    if (-not [string]::IsNullOrWhiteSpace($token)) {
      $headers["Authorization"] = "Bearer $token"
    }
  }
  $headers
}

function Invoke-DraftEndpoint {
  param(
    [string]$Path,
    $Body
  )
  $base = $ApiBase.TrimEnd("/")
  $headers = Get-AuthHeaders
  $jsonBody = ConvertTo-SafeJson $Body
  $response = Invoke-WebRequest `
    -Method POST `
    -Uri "$base$Path" `
    -ContentType "application/json" `
    -Headers $headers `
    -Body $jsonBody `
    -SkipHttpErrorCheck
  $content = ($response.Content | Out-String).Trim()
  $parsed = if ([string]::IsNullOrWhiteSpace($content)) {
    [pscustomobject]@{ ok = $false; error = "empty_response"; token_printed = $false }
  } else {
    $content | ConvertFrom-Json
  }
  [pscustomobject]@{
    status_code = [int]$response.StatusCode
    body = $parsed
  }
}

function New-Status {
  [pscustomobject]@{
    schema = "skybridge.draft_submit_status.v1"
    ok = $true
    api_base_configured = -not [string]::IsNullOrWhiteSpace($ApiBase)
    submit_preview_endpoint = "/v1/drafts/submit-preview"
    submit_endpoint = "/v1/drafts/submit"
    confirmation_required = $true
    confirmation_text_required = $ConfirmationPhrase
    preview_default = $true
    task_created = $false
    campaign_created = $false
    claim_created = $false
    execution_started = $false
    codex_run_called = $false
    matlab_run_called = $false
    worker_loop_started = $false
    arbitrary_shell_enabled = $false
    raw_prompt_persisted = $false
    raw_response_persisted = $false
    token_printed = $false
  }
}

function New-SafeSummary {
  $inputObject = Read-InputObject
  $draft = if ($inputObject.draft) { $inputObject.draft } else { $inputObject }
  [pscustomobject]@{
    schema = "skybridge.draft_submit_safe_summary.v1"
    ok = $true
    draft_id = $draft.draft_id
    draft_type = $draft.draft_type
    template_id = $draft.template_id
    project_id = $draft.project_id
    title = $draft.title
    risk = $draft.risk
    runner_id = $draft.runner_id
    evidence_schema = @($draft.evidence_schema)
    next_safe_action = "submit_preview_then_exact_confirm_or_hold"
    task_created = $false
    campaign_created = $false
    claim_created = $false
    execution_started = $false
    codex_run_called = $false
    matlab_run_called = $false
    worker_loop_started = $false
    arbitrary_shell_enabled = $false
    raw_prompt_persisted = $false
    raw_response_persisted = $false
    token_printed = $false
  }
}

if ($Command -eq "status") {
  $result = New-Status
} elseif ($Command -eq "safe-summary") {
  $result = New-SafeSummary
} else {
  $inputObject = Read-InputObject
  $draft = if ($inputObject.draft) { $inputObject.draft } else { $inputObject }
  if ($Command -eq "submit") {
    if (-not $Confirm -or $ConfirmationText -ne $ConfirmationPhrase) {
      $result = [pscustomobject]@{
        schema = "skybridge.draft_submit_result.v1"
        ok = $false
        draft_id = $draft.draft_id
        draft_type = $draft.draft_type
        template_id = $draft.template_id
        project_id = $draft.project_id
        title = $draft.title
        risk = $draft.risk
        required_capabilities = @($draft.required_capabilities)
        allowed_paths = @($draft.allowed_paths)
        blocked_paths = @($draft.blocked_paths)
        runner_id = $draft.runner_id
        evidence_schema = @($draft.evidence_schema)
        review_status = "blocked"
        review_reason = "missing_exact_confirmation"
        submitted_by = "local-operator"
        task_created = $false
        campaign_created = $false
        claim_created = $false
        execution_started = $false
        codex_run_called = $false
        matlab_run_called = $false
        worker_loop_started = $false
        arbitrary_shell_enabled = $false
        project_control_unpause = $false
        raw_prompt_persisted = $false
        raw_response_persisted = $false
        token_printed = $false
        next_safe_action = "enter_exact_confirmation_text_before_submit"
      }
    } else {
      $body = @{
        draft = $draft
        submitted_by = "local-operator"
        confirm_submit = $true
        confirmation_text = $ConfirmationPhrase
      }
      $response = Invoke-DraftEndpoint -Path "/v1/drafts/submit" -Body $body
      $result = $response.body
    }
  } else {
    $body = @{
      draft = $draft
      submitted_by = "local-operator"
    }
    $response = Invoke-DraftEndpoint -Path "/v1/drafts/submit-preview" -Body $body
    $result = $response.body
  }
}

if ($Json) {
  $result | ConvertTo-Json -Depth 20
} else {
  $result | Format-List
}
