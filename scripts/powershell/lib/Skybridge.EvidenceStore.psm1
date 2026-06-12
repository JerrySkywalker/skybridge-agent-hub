Import-Module (Join-Path $PSScriptRoot "Skybridge.Core.psm1") -Force
Import-Module (Join-Path $PSScriptRoot "Skybridge.SafetyScanner.psm1") -Force

function Resolve-SkybridgeEvidencePath {
  param([Parameter(Mandatory = $true)][string]$RelativePath)
  $normalized = $RelativePath.Replace("\", "/")
  if ($normalized -notlike ".agent/tmp/*") { throw "Evidence path must be under .agent/tmp." }
  Resolve-SkybridgePath $normalized
}

function Get-SkybridgeEvidenceHash {
  param([Parameter(Mandatory = $true)][string]$Path)
  $full = Resolve-SkybridgePath $Path
  if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { throw "Evidence file missing: $(ConvertTo-SkybridgeShortPath $full)" }
  (Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Test-SkybridgeEvidenceSafe {
  param([Parameter(Mandatory = $true)][string]$Path)
  $full = Resolve-SkybridgePath $Path
  if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { return $false }
  $text = Get-Content -Raw -LiteralPath $full
  return -not (Test-SkybridgeUnsafeText $text)
}

function Find-SkybridgeFinalizerEvidence {
  param([Parameter(Mandatory = $true)][string]$RunId)
  $path = ".agent/tmp/$RunId/finalizer-evidence.json"
  [pscustomobject]@{
    run_id = $RunId
    path = $path
    exists = (Test-Path -LiteralPath (Resolve-SkybridgePath $path) -PathType Leaf)
    safe = (Test-SkybridgeEvidenceSafe $path)
    sha256 = if (Test-Path -LiteralPath (Resolve-SkybridgePath $path) -PathType Leaf) { Get-SkybridgeEvidenceHash $path } else { $null }
    retention_class = "local_ignored_safe_summary"
    archive_compression_enabled = $false
    token_printed = $false
  }
}

Export-ModuleMember -Function Resolve-SkybridgeEvidencePath, Get-SkybridgeEvidenceHash, Test-SkybridgeEvidenceSafe, Find-SkybridgeFinalizerEvidence
