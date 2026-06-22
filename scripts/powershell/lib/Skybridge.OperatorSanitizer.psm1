function ConvertTo-SkybridgeOperatorSafeText {
  param(
    [AllowNull()][string]$Text,
    [int]$MaxLength = 360
  )
  if ([string]::IsNullOrWhiteSpace($Text)) { return "" }
  $safe = [string]$Text
  $safe = $safe -replace "(?i)authorization\s*[:=]\s*bearer\s+\S+", "authorization=[redacted]"
  $safe = $safe -replace "(?i)bearer\s+[A-Za-z0-9._-]{12,}", "bearer [redacted]"
  $safe = $safe -replace "(?i)sk-[A-Za-z0-9_-]{12,}", "sk-[redacted]"
  $safe = $safe -replace "(?i)gh[pousr]_[A-Za-z0-9_]{20,}", "gh_[redacted]"
  $safe = $safe -replace "(?i)(token|secret|password|cookie|credential|api[_-]?key|provider[_-]?token)\s*[:=]\s*\S+", "[redacted-credential]"
  $safe = $safe -replace "(?i)(https?://)[^/\s:@]+:[^@\s/]+@", '$1[redacted]@'
  $safe = $safe -replace "(?i)(webhook|proxy[_-]?profile)\s*[:=]\s*\S+", '$1=[redacted]'
  $safe = $safe -replace '(?is)```(?:raw[_ -]?)?prompt.*?```', "[redacted-prompt-block]"
  $safe = $safe -replace '(?is)```(?:raw[_ -]?)?(log|stdout|stderr).*?```', "[redacted-log-block]"
  $safe = $safe -replace "(?is)-----BEGIN [A-Z ]*PRIVATE KEY-----.*?-----END [A-Z ]*PRIVATE KEY-----", "[redacted-private-key]"
  $safe = $safe.Trim()
  if ($safe.Length -gt $MaxLength) { return ($safe.Substring(0, $MaxLength) + "...[truncated]") }
  return $safe
}

function Test-SkybridgeOperatorUnsafeText {
  param([AllowNull()][string]$Text)
  if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
  return $Text -match '(?i)authorization\s*[:=]\s*bearer|bearer\s+[A-Za-z0-9_.-]{12,}|sk-[A-Za-z0-9_-]{12,}|gh[pousr]_[A-Za-z0-9_]{20,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|raw_stdout|raw_stderr|raw_prompt|raw_worker_log|raw_codex_transcript|raw_ci_log|environment dump|env_dump|cookie\s*[:=]|password\s*[:=]|api[_-]?key\s*[:=]|token_printed"\s*:\s*true'
}

function Get-SkybridgeOperatorProp {
  param($Object, [string]$Name, $Default = $null)
  if ($null -eq $Object) { return $Default }
  $prop = $Object.PSObject.Properties[$Name]
  if ($null -eq $prop) { return $Default }
  return $prop.Value
}

function Get-SkybridgeOperatorBool {
  param($Object, [string]$Name, [bool]$Default = $false)
  $value = Get-SkybridgeOperatorProp -Object $Object -Name $Name -Default $Default
  if ($null -eq $value) { return $Default }
  return [bool]$value
}

function Get-SkybridgeOperatorInt {
  param($Object, [string]$Name, [int]$Default = 0)
  $value = Get-SkybridgeOperatorProp -Object $Object -Name $Name -Default $Default
  if ($null -eq $value -or [string]::IsNullOrWhiteSpace([string]$value)) { return $Default }
  return [int]$value
}

function Read-SkybridgeOperatorJsonFile {
  param([Parameter(Mandatory = $true)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "JSON file not found: $Path" }
  $text = Get-Content -Raw -LiteralPath $Path
  if (Test-SkybridgeOperatorUnsafeText -Text $text) { throw "Unsafe fixture/report JSON content detected." }
  $text | ConvertFrom-Json
}

function Invoke-SkybridgeOperatorChildJson {
  param(
    [Parameter(Mandatory = $true)][string[]]$Arguments,
    [switch]$AllowNonZero
  )
  $output = @(& pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass @Arguments 2>&1)
  $exitCode = $LASTEXITCODE
  $text = (($output | Out-String).Trim())
  if (Test-SkybridgeOperatorUnsafeText -Text $text) { throw "Unsafe child command output detected." }
  $parsed = $null
  if (-not [string]::IsNullOrWhiteSpace($text)) {
    try { $parsed = $text | ConvertFrom-Json } catch {}
  }
  if ($exitCode -eq 0 -and $null -ne $parsed) { return $parsed }
  if ($AllowNonZero -and $null -ne $parsed) { return $parsed }
  $safe = ConvertTo-SkybridgeOperatorSafeText -Text $text
  throw "Command failed: pwsh $($Arguments -join ' '): $safe"
}

function ConvertTo-SkybridgeOperatorSafeJson {
  param([Parameter(Mandatory = $true)]$Value, [int]$Depth = 30)
  $json = $Value | ConvertTo-Json -Depth $Depth
  if (Test-SkybridgeOperatorUnsafeText -Text $json) { throw "Unsafe operator report JSON detected." }
  return $json
}

Export-ModuleMember -Function ConvertTo-SkybridgeOperatorSafeText, Test-SkybridgeOperatorUnsafeText, Get-SkybridgeOperatorProp, Get-SkybridgeOperatorBool, Get-SkybridgeOperatorInt, Read-SkybridgeOperatorJsonFile, Invoke-SkybridgeOperatorChildJson, ConvertTo-SkybridgeOperatorSafeJson
