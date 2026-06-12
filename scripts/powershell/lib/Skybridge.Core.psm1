$script:SkybridgeFixedTimestamp = $null

function Get-SkybridgeRepoRoot {
  $candidate = $PSScriptRoot
  while ($candidate -and -not (Test-Path -LiteralPath (Join-Path $candidate "pnpm-workspace.yaml") -PathType Leaf)) {
    $parent = Split-Path -Parent $candidate
    if ($parent -eq $candidate) { break }
    $candidate = $parent
  }
  if (-not $candidate) { throw "Unable to locate SkyBridge repository root." }
  (Resolve-Path -LiteralPath $candidate).Path
}

function Resolve-SkybridgePath {
  param([Parameter(Mandatory = $true)][string]$Path)
  if ([System.IO.Path]::IsPathRooted($Path)) { return [System.IO.Path]::GetFullPath($Path) }
  [System.IO.Path]::GetFullPath((Join-Path (Get-SkybridgeRepoRoot) $Path))
}

function ConvertTo-SkybridgeShortPath {
  param([Parameter(Mandatory = $true)][string]$Path)
  $root = [System.IO.Path]::GetFullPath((Get-SkybridgeRepoRoot)).TrimEnd("\", "/")
  $full = [System.IO.Path]::GetFullPath($Path)
  if ($full.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase)) {
    return $full.Substring($root.Length).TrimStart("\", "/").Replace("\", "/")
  }
  $Path.Replace("\", "/")
}

function Set-SkybridgeDeterministicTimestamp {
  param([string]$Timestamp)
  $script:SkybridgeFixedTimestamp = $Timestamp
}

function Get-SkybridgeTimestamp {
  if (-not [string]::IsNullOrWhiteSpace($script:SkybridgeFixedTimestamp)) { return $script:SkybridgeFixedTimestamp }
  (Get-Date).ToUniversalTime().ToString("o")
}

function Test-SkybridgeTokenPrintedFalse {
  param([Parameter(Mandatory = $true)]$Value)
  if ($Value.PSObject.Properties.Name -notcontains "token_printed") { return $false }
  return ($Value.token_printed -eq $false)
}

function Add-SkybridgeTokenPrintedFalse {
  param([Parameter(Mandatory = $true)]$Value)
  if ($Value -is [hashtable]) {
    $Value["token_printed"] = $false
    return [pscustomobject]$Value
  }
  $Value | Add-Member -NotePropertyName token_printed -NotePropertyValue $false -Force
  $Value
}

function Test-SkybridgeUnsafeText {
  param([string]$Text)
  if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
  return $Text -match '(?i)authorization\s*[:=]\s*bearer|bearer\s+[A-Za-z0-9_.-]{12,}|sk-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|raw_stdout|raw_stderr|raw_prompt|raw_worker_log|raw_codex_transcript|raw_ci_log|token_printed"\s*:\s*true'
}

function Read-SkybridgeSafeJson {
  param([Parameter(Mandatory = $true)][string]$Path)
  $full = Resolve-SkybridgePath $Path
  if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { return $null }
  $text = Get-Content -Raw -LiteralPath $full
  if (Test-SkybridgeUnsafeText $text) { throw "Unsafe JSON content detected: $(ConvertTo-SkybridgeShortPath $full)" }
  $value = $text | ConvertFrom-Json
  if ($value.PSObject.Properties.Name -contains "token_printed" -and $value.token_printed -ne $false) {
    throw "token_printed must be false: $(ConvertTo-SkybridgeShortPath $full)"
  }
  $value
}

function Write-SkybridgeSafeJson {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)]$Value,
    [int]$Depth = 12
  )
  $full = Resolve-SkybridgePath $Path
  $dir = Split-Path -Parent $full
  if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  $safe = Add-SkybridgeTokenPrintedFalse $Value
  $json = $safe | ConvertTo-Json -Depth $Depth
  if (Test-SkybridgeUnsafeText $json) { throw "Refusing to write unsafe JSON: $(ConvertTo-SkybridgeShortPath $full)" }
  Set-Content -LiteralPath $full -Value $json -Encoding utf8
  [pscustomobject]@{ path = ConvertTo-SkybridgeShortPath $full; token_printed = $false }
}

Export-ModuleMember -Function Get-SkybridgeRepoRoot, Resolve-SkybridgePath, ConvertTo-SkybridgeShortPath, Set-SkybridgeDeterministicTimestamp, Get-SkybridgeTimestamp, Test-SkybridgeTokenPrintedFalse, Add-SkybridgeTokenPrintedFalse, Test-SkybridgeUnsafeText, Read-SkybridgeSafeJson, Write-SkybridgeSafeJson
