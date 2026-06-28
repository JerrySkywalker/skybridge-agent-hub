. "$PSScriptRoot\smoke-productization-common.ps1"

$result = Invoke-JsonScript "skybridge-vite-chunk-warning-analysis.ps1" @(
  "-Command", "analyze"
)

Assert-False $result.chunk_size_limit_changed "chunk_size_limit_changed"
Assert-False $result.vite_config_changed "vite_config_changed"
Assert-False $result.build_config_changed "build_config_changed"

$viteConfigText = @(Get-ChildItem -Path (Join-Path $RepoRoot "apps") -Recurse -File -Filter "vite.config.*" | ForEach-Object {
  Get-Content -Raw -LiteralPath $_.FullName
}) -join "`n"
if ($viteConfigText -match "chunkSizeWarningLimit") { throw "Vite chunk-size limit override detected." }

Assert-TokenPrintedFalse $result

Complete-Smoke "vite-chunk-warning-analysis-no-threshold-change"
