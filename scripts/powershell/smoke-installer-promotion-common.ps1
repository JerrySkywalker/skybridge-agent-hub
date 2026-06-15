function Test-UnsafeText([string]$Text) {
  if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
  $tokenTrue = 'token_printed"\s*:\s*tr' + 'ue'
  return $Text -match "(?i)authorization\s*[:=]\s*bearer|bearer\s+[A-Za-z0-9_.-]{12,}|sk-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|raw_stdout|raw_stderr|raw_prompt|raw_worker_log|raw_codex_transcript|raw_ci_log|environment dump|env_dump|cookie\s*[:=]|$tokenTrue"
}

function Invoke-SmokeJson {
  param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Script,
    [Parameter(ValueFromRemainingArguments = $true)]
    [object[]]$ScriptArgs
  )
  $flatArgs = @()
  foreach ($arg in $ScriptArgs) {
    if ($arg -is [array]) {
      foreach ($nested in $arg) { $flatArgs += [string]$nested }
    } else {
      $flatArgs += [string]$arg
    }
  }
  $raw = & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot $Script) @flatArgs -Json
  if ($LASTEXITCODE -ne 0) { throw "$Script failed." }
  $text = ($raw | Out-String).Trim()
  if (Test-UnsafeText $text) { throw "$Script emitted unsafe text." }
  $value = $text | ConvertFrom-Json
  if ($value.PSObject.Properties["token_printed"] -and $value.token_printed -ne $false) { throw "$Script reported token_printed true." }
  $value
}

function Assert-False($Value, [string]$Name) {
  if ($Value -ne $false) { throw "$Name expected false." }
}

function Assert-Truthy($Value, [string]$Name) {
  if (-not $Value) { throw "$Name expected truthy." }
}
