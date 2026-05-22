[CmdletBinding()]
param()

function Get-SkyBridgeRepositoryRoot {
  $current = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
  while ($true) {
    if (Test-Path (Join-Path $current "pnpm-workspace.yaml")) { return $current }
    $parent = Split-Path -Parent $current
    if ($parent -eq $current) { return (Get-Location).Path }
    $current = $parent
  }
}

function Get-SkyBridgeSharedRedactionRules {
  $fallback = @{
    replacement = "[REDACTED]"
    maxStringLength = 2000
    secretKeyPatterns = @("token", "password", "passwd", "authorization", "cookie", "secret", "api[_-]?key", "private[_-]?key")
    secretValuePatterns = @("Bearer\s+[A-Za-z0-9._-]+", "sk-[A-Za-z0-9_-]{12,}", "-----BEGIN [A-Z ]*PRIVATE KEY-----", "-----BEGIN OPENSSH PRIVATE KEY-----")
    omitKeyPatterns = @("prompt", "patch", "stdout", "stderr", "command_output", "raw_output", "tool_result")
    source = "fallback"
  }

  try {
    $rulesPath = Join-Path (Get-SkyBridgeRepositoryRoot) "packages\event-schema\src\redaction-rules.json"
    if (-not (Test-Path -LiteralPath $rulesPath)) { return $fallback }
    $rules = Get-Content -Raw -Path $rulesPath | ConvertFrom-Json -AsHashtable
    $rules["source"] = "packages/event-schema/src/redaction-rules.json"
    return $rules
  } catch {
    return $fallback
  }
}

function Test-SkyBridgeRedactionPattern {
  param([AllowNull()][string]$Value, [AllowNull()]$Patterns)
  if ([string]::IsNullOrWhiteSpace($Value) -or $null -eq $Patterns) { return $false }
  foreach ($pattern in @($Patterns)) {
    if ($Value -match "(?i)$pattern") { return $true }
  }
  return $false
}

function Redact-SkyBridgeString {
  param(
    [AllowNull()][string]$Value,
    [AllowNull()]$Rules,
    [int]$MaxLength = 160
  )

  if ($null -eq $Value) { return $null }
  if ($null -eq $Rules) { $Rules = Get-SkyBridgeSharedRedactionRules }

  $text = $Value
  foreach ($pattern in @($Rules.secretValuePatterns)) {
    $text = [regex]::Replace($text, $pattern, [string]$Rules.replacement, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
  }
  $text = $text -replace '(?i)\b([A-Za-z0-9_.-]*(token|password|passwd|secret|api[_-]?key)[A-Za-z0-9_.-]*)\s*[:=]\s*([^\s;&|]+)', "`$1=$($Rules.replacement)"
  if ($text.Length -gt $MaxLength) { return "$($text.Substring(0, $MaxLength))...[truncated $($text.Length - $MaxLength) chars]" }
  return $text
}

function ConvertTo-SkyBridgeSafeValue {
  param(
    $Value,
    [AllowNull()]$Rules,
    [int]$Depth = 0
  )

  if ($null -eq $Rules) { $Rules = Get-SkyBridgeSharedRedactionRules }
  if ($null -eq $Value) { return $null }
  if ($Value -is [string]) { return (Redact-SkyBridgeString -Value $Value -Rules $Rules) }
  if ($Value -is [bool] -or $Value -is [int] -or $Value -is [long] -or $Value -is [double]) { return $Value }
  if ($Value -is [System.Collections.IDictionary]) {
    if ($Depth -ge 4) { return @{ bounded = $true; type = "object"; keys = @($Value.Keys | Select-Object -First 24) } }
    $result = @{}
    foreach ($key in @($Value.Keys | Select-Object -First 24)) {
      if (Test-SkyBridgeRedactionPattern -Value ([string]$key) -Patterns $Rules.secretKeyPatterns) {
        $result[$key] = $Rules.replacement
      } elseif ((Test-SkyBridgeRedactionPattern -Value ([string]$key) -Patterns $Rules.omitKeyPatterns) -or [string]$key -match '(?i)command|output|content') {
        $item = $Value[$key]
        $result[$key] = @{
          bounded = $true
          type = if ($null -eq $item) { "null" } else { $item.GetType().Name }
          length = if ($item -is [string]) { $item.Length } else { $null }
        }
      } else {
        $result[$key] = ConvertTo-SkyBridgeSafeValue -Value $Value[$key] -Rules $Rules -Depth ($Depth + 1)
      }
    }
    if ($Value.Keys.Count -gt 24) { $result["__truncated_keys"] = $Value.Keys.Count - 24 }
    return $result
  }
  if ($Value -is [pscustomobject]) {
    $objectAsMap = @{}
    foreach ($property in @($Value.PSObject.Properties | Select-Object -First 24)) {
      $objectAsMap[$property.Name] = $property.Value
    }
    if ($Value.PSObject.Properties.Count -gt 24) { $objectAsMap["__truncated_keys"] = $Value.PSObject.Properties.Count - 24 }
    return ConvertTo-SkyBridgeSafeValue -Value $objectAsMap -Rules $Rules -Depth $Depth
  }
  if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [hashtable] -and $Value -isnot [string]) {
    if ($Depth -ge 4) { return @{ bounded = $true; type = "array" } }
    return @($Value | Select-Object -First 24 | ForEach-Object { ConvertTo-SkyBridgeSafeValue -Value $_ -Rules $Rules -Depth ($Depth + 1) })
  }
  return (Redact-SkyBridgeString -Value ([string]$Value) -Rules $Rules)
}
