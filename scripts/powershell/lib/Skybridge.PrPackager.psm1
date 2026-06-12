Import-Module (Join-Path $PSScriptRoot "Skybridge.Core.psm1") -Force

function Test-SkybridgeAllowedPrPath {
  param([string]$Path)
  $normalized = ([string]$Path).Replace("\", "/")
  return ($normalized -eq "README.md" -or $normalized -like "docs/*")
}

function Get-SkybridgeChangedFiles {
  $files = @()
  $files += @(git diff --name-only)
  $files += @(git diff --cached --name-only)
  $files += @(git ls-files --others --exclude-standard)
  @($files | ForEach-Object { ([string]$_).Replace("\", "/") } | Where-Object { $_ -and $_ -notlike ".agent/tmp/*" } | Select-Object -Unique)
}

function Assert-SkybridgeAllowedPrPaths {
  param([string[]]$Paths)
  $bad = @($Paths | Where-Object { -not (Test-SkybridgeAllowedPrPath $_) })
  if ($bad.Count -gt 0) { throw "Disallowed changed paths: $($bad -join ', ')" }
  [pscustomobject]@{ ok = $true; changed_files = @($Paths); token_printed = $false }
}

function New-SkybridgeBranchName {
  param([Parameter(Mandatory = $true)][string]$Slug)
  "ai/$($Slug.Trim().ToLowerInvariant() -replace '[^a-z0-9/-]+','-' -replace '-+','-')"
}

function New-SkybridgeSafePrSummary {
  param([string]$Title, [string[]]$ChangedFiles = @(), [string[]]$Checks = @())
  $body = @(
    "## Summary"
    "- $Title"
    ""
    "## Changed files"
    ($ChangedFiles | ForEach-Object { "- $_" })
    ""
    "## Safety"
    "- no auto-merge"
    "- token_printed=false"
  ) -join "`n"
  if (Test-SkybridgeUnsafeText $body) { throw "Unsafe PR body." }
  $body
}

Export-ModuleMember -Function Test-SkybridgeAllowedPrPath, Get-SkybridgeChangedFiles, Assert-SkybridgeAllowedPrPaths, New-SkybridgeBranchName, New-SkybridgeSafePrSummary
