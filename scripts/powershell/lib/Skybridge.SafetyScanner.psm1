Import-Module (Join-Path $PSScriptRoot "Skybridge.Core.psm1") -Force

function Test-SkybridgeTokenLookingText {
  param([string]$Text)
  Test-SkybridgeUnsafeText $Text
}

function Test-SkybridgeRawArtifactText {
  param([string]$Text)
  if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
  return $Text -match '(?i)\b(raw_stdout|raw_stderr|raw_prompt|raw_transcript|raw_worker_log|raw_codex_transcript|raw_ci_log|stdout_text|stderr_text)\b'
}

function Test-SkybridgeSecretLookingJson {
  param([Parameter(Mandatory = $true)]$Value)
  $json = $Value | ConvertTo-Json -Depth 20 -Compress
  Test-SkybridgeUnsafeText $json
}

function Test-SkybridgeEnvironmentDumpText {
  param([string]$Text)
  if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
  return $Text -match '(?im)^(PATH|USERPROFILE|APPDATA|LOCALAPPDATA|PROCESSOR_IDENTIFIER|COMPUTERNAME|USERNAME|OPENAI_API_KEY|GITHUB_TOKEN)\s*='
}

function Test-SkybridgeUnsafeCommandString {
  param([string]$Command)
  if ([string]::IsNullOrWhiteSpace($Command)) { return $false }
  return $Command -match '(?i)\b(start-all|start-queue|bounded queue apply|run-apply|pilot-apply|retry-apply|resume\s+-Apply|docker\s+system\s+prune|rm\s+-rf|Remove-Item\s+.*-Recurse.*-Force)\b'
}

function Assert-SkybridgeSafeText {
  param([string]$Text, [string]$Label = "text")
  if (Test-SkybridgeUnsafeText $Text -or Test-SkybridgeEnvironmentDumpText $Text) { throw "Unsafe $Label detected." }
  [pscustomobject]@{ ok = $true; label = $Label; token_printed = $false }
}

Export-ModuleMember -Function Test-SkybridgeTokenLookingText, Test-SkybridgeRawArtifactText, Test-SkybridgeSecretLookingJson, Test-SkybridgeEnvironmentDumpText, Test-SkybridgeUnsafeCommandString, Assert-SkybridgeSafeText
