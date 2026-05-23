[CmdletBinding()]
param(
  [string]$HermesApiBase,
  [string]$HermesApiKey,
  [string]$Model,
  [switch]$DryRun,
  [switch]$Json,
  [int]$TimeoutSeconds = 30
)

$ErrorActionPreference = "Stop"

$loader = Join-Path $PSScriptRoot "load-hermes-env.ps1"
if (Test-Path -LiteralPath $loader -PathType Leaf) {
  . $loader
}

if ([string]::IsNullOrWhiteSpace($HermesApiBase)) {
  $HermesApiBase = $env:HERMES_API_BASE
}
if ([string]::IsNullOrWhiteSpace($HermesApiKey)) {
  $HermesApiKey = $env:HERMES_API_KEY
}
if ([string]::IsNullOrWhiteSpace($Model)) {
  $Model = $env:HERMES_MODEL
}

$safePrompt = "Return exactly one sentence: SkyBridge Hermes supervisor connectivity is healthy. Do not call tools. Do not access files."
$expectedText = "SkyBridge Hermes supervisor connectivity is healthy."

function New-HermesHeaders {
  param([string]$ApiKey)

  $headers = @{
    "Accept" = "application/json"
    "Content-Type" = "application/json"
  }
  if (-not [string]::IsNullOrWhiteSpace($ApiKey)) {
    $headers["Authorization"] = "Bearer $ApiKey"
  }
  return $headers
}

function Invoke-HermesGetOptional {
  param(
    [string]$ApiBase,
    [string]$Path,
    [hashtable]$Headers,
    [int]$TimeoutSeconds
  )

  try {
    return Invoke-RestMethod -Method Get -Uri "$($ApiBase.TrimEnd('/'))$Path" -Headers $Headers -TimeoutSec $TimeoutSeconds
  } catch {
    return $null
  }
}

function Resolve-HermesModel {
  param(
    [string]$CurrentModel,
    [object]$ModelsResponse
  )

  if (-not [string]::IsNullOrWhiteSpace($CurrentModel)) {
    return $CurrentModel
  }

  if ($ModelsResponse -and $ModelsResponse.data) {
    $first = @($ModelsResponse.data | Select-Object -First 1)
    if ($first.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($first[0].id)) {
      return [string]$first[0].id
    }
  }

  return $null
}

function Get-ResponseText {
  param([object]$Response)

  if ($null -eq $Response) { return $null }
  if (-not [string]::IsNullOrWhiteSpace($Response.output_text)) { return [string]$Response.output_text }
  if ($Response.choices -and $Response.choices.Count -gt 0) {
    $message = $Response.choices[0].message
    if ($message -and -not [string]::IsNullOrWhiteSpace($message.content)) {
      return [string]$message.content
    }
  }
  if ($Response.output) {
    $texts = @()
    foreach ($item in @($Response.output)) {
      if ($item.content) {
        foreach ($content in @($item.content)) {
          if (-not [string]::IsNullOrWhiteSpace($content.text)) {
            $texts += [string]$content.text
          }
        }
      }
    }
    if ($texts.Count -gt 0) {
      return ($texts -join "`n")
    }
  }
  return $null
}

function Invoke-HermesPost {
  param(
    [string]$ApiBase,
    [string]$Path,
    [hashtable]$Headers,
    [hashtable]$Body,
    [int]$TimeoutSeconds
  )

  try {
    $response = Invoke-RestMethod -Method Post -Uri "$($ApiBase.TrimEnd('/'))$Path" -Headers $Headers -Body ($Body | ConvertTo-Json -Depth 20) -TimeoutSec $TimeoutSeconds
    $text = Get-ResponseText -Response $response
    return @{
      path = $Path
      ok = $true
      status = "ok"
      response_text_present = -not [string]::IsNullOrWhiteSpace($text)
      expected_phrase_matched = if ([string]::IsNullOrWhiteSpace($text)) { $false } else { $text.Contains($expectedText) }
      response_text_included = $false
      body_included = $false
      error = $null
    }
  } catch {
    $statusCode = $null
    if ($_.Exception.Response -and $_.Exception.Response.StatusCode) {
      $statusCode = [int]$_.Exception.Response.StatusCode
    }
    return @{
      path = $Path
      ok = $false
      status = "failed"
      http_status = $statusCode
      response_text_included = $false
      body_included = $false
      error = $_.Exception.Message
    }
  }
}

$summary = @{
  ok = $true
  dry_run = [bool]$DryRun
  status = "unknown"
  hermes_api_base_configured = -not [string]::IsNullOrWhiteSpace($HermesApiBase)
  hermes_api_base = if ([string]::IsNullOrWhiteSpace($HermesApiBase)) { $null } else { $HermesApiBase }
  hermes_api_key_present = -not [string]::IsNullOrWhiteSpace($HermesApiKey)
  hermes_api_key_value_included = $false
  ssh_tunnel_likely = if ([string]::IsNullOrWhiteSpace($HermesApiBase)) { $false } else { $HermesApiBase -match "127\.0\.0\.1|localhost|\[::1\]" }
  model_configured = -not [string]::IsNullOrWhiteSpace($Model)
  model_value_included = $false
  prompt_included = $false
  tools_disabled_requested = $true
  attempts = @()
  raw_response_included = $false
}

if ([string]::IsNullOrWhiteSpace($HermesApiBase)) {
  $summary.ok = $false
  $summary.status = "missing_base"
} elseif ([string]::IsNullOrWhiteSpace($HermesApiKey)) {
  $summary.ok = $false
  $summary.status = "missing_key"
} elseif ($DryRun) {
  $summary.status = "dry_run"
  $summary.attempts = @(
    @{ path = "/v1/responses"; status = "dry_run"; body_included = $false; response_text_included = $false },
    @{ path = "/v1/chat/completions"; status = "dry_run_fallback"; body_included = $false; response_text_included = $false }
  )
} else {
  $headers = New-HermesHeaders -ApiKey $HermesApiKey
  $modelsResponse = Invoke-HermesGetOptional -ApiBase $HermesApiBase -Path "/v1/models" -Headers $headers -TimeoutSeconds $TimeoutSeconds
  $resolvedModel = Resolve-HermesModel -CurrentModel $Model -ModelsResponse $modelsResponse
  $summary.model_configured = -not [string]::IsNullOrWhiteSpace($resolvedModel)

  $responsesBody = @{
    input = $safePrompt
    tools = @()
    tool_choice = "none"
  }
  if (-not [string]::IsNullOrWhiteSpace($resolvedModel)) {
    $responsesBody["model"] = $resolvedModel
  }
  $responsesAttempt = Invoke-HermesPost -ApiBase $HermesApiBase -Path "/v1/responses" -Headers $headers -Body $responsesBody -TimeoutSeconds $TimeoutSeconds
  $summary.attempts += $responsesAttempt

  if ($responsesAttempt.ok) {
    $summary.status = "responses_ok"
    $summary.ok = [bool]$responsesAttempt.expected_phrase_matched
  } else {
    $chatBody = @{
      messages = @(
        @{ role = "user"; content = $safePrompt }
      )
      tools = @()
      tool_choice = "none"
    }
    if (-not [string]::IsNullOrWhiteSpace($resolvedModel)) {
      $chatBody["model"] = $resolvedModel
    }
    $chatAttempt = Invoke-HermesPost -ApiBase $HermesApiBase -Path "/v1/chat/completions" -Headers $headers -Body $chatBody -TimeoutSeconds $TimeoutSeconds
    $summary.attempts += $chatAttempt
    if ($chatAttempt.ok) {
      $summary.status = "chat_completions_ok"
      $summary.ok = [bool]$chatAttempt.expected_phrase_matched
    } else {
      $summary.status = "degraded"
      $summary.ok = $false
    }
  }
}

if ($Json) {
  $summary | ConvertTo-Json -Depth 12
} else {
  Write-Host "[hermes-cloud-run] status=$($summary.status) base_configured=$($summary.hermes_api_base_configured) key_present=$($summary.hermes_api_key_present) dry_run=$($summary.dry_run)"
  foreach ($attempt in $summary.attempts) {
    Write-Host "[hermes-cloud-run] $($attempt.path) $($attempt.status) expected=$($attempt.expected_phrase_matched)"
  }
}

if (-not $summary.ok -and $summary.status -notin @("missing_key", "missing_base", "degraded")) {
  exit 1
}
