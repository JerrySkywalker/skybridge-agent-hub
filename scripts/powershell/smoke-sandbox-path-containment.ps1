$ErrorActionPreference = "Stop"
$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
$sandbox = [System.IO.Path]::GetFullPath((Join-Path $root ".agent\tmp\install-sandbox"))
& pwsh -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\skybridge-install-sandbox.ps1" -Command apply-sandbox -Json | Out-Null
$paths = @(Get-ChildItem -LiteralPath $sandbox -Recurse -Force | Select-Object -ExpandProperty FullName)
foreach ($path in $paths) {
  $full = [System.IO.Path]::GetFullPath($path)
  if (-not $full.StartsWith($sandbox, [System.StringComparison]::OrdinalIgnoreCase)) { throw "Path escaped sandbox: $path" }
}
[pscustomobject]@{ ok = $true; scenario = "sandbox-path-containment"; checked_paths = $paths.Count; token_printed = $false } | ConvertTo-Json -Compress
