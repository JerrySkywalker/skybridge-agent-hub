$ErrorActionPreference = "Stop"
Import-Module (Join-Path $PSScriptRoot "lib/Skybridge.EvidenceStore.psm1") -Force
$evidence = Find-SkybridgeFinalizerEvidence -RunId "managed-mode-run-211"
if (-not $evidence.exists -or -not $evidence.safe -or [string]::IsNullOrWhiteSpace($evidence.sha256)) { throw "evidence hash failed" }
[pscustomobject]@{ ok = $true; scenario = "core-engine-evidence-store-hashes"; sha256 = $evidence.sha256; token_printed = $false } | ConvertTo-Json -Compress
