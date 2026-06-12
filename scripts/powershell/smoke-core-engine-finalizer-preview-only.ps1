$ErrorActionPreference = "Stop"
Import-Module (Join-Path $PSScriptRoot "lib/Skybridge.Finalizer.psm1") -Force
$preview = New-SkybridgeFinalizerPreview -RunId "managed-mode-run-211"
if ($preview.apply_enabled -ne $false) { throw "finalizer preview must not apply" }
[pscustomobject]@{ ok = $true; scenario = "core-engine-finalizer-preview-only"; token_printed = $false } | ConvertTo-Json -Compress
