. "$PSScriptRoot\smoke-productization-common.ps1"

$fixtureDir = Join-Path $RepoRoot ".agent/tmp/vite-chunk-warning-analysis/fixture"
New-Item -ItemType Directory -Force -Path $fixtureDir | Out-Null
$fixtureLog = Join-Path $fixtureDir "vite-build-summary.txt"
@(
  "dist/assets/index-fixture-web.js   611.53 kB | gzip: 142.36 kB",
  "dist/assets/index-fixture-desktop.js   602.42 kB | gzip: 139.83 kB",
  "(!) Some chunks are larger than 500 kB after minification."
) | Set-Content -LiteralPath $fixtureLog -Encoding UTF8

$result = Invoke-JsonScript "skybridge-vite-chunk-warning-analysis.ps1" @(
  "-Command", "analyze",
  "-BuildLogPath", ".agent/tmp/vite-chunk-warning-analysis/fixture/vite-build-summary.txt",
  "-WriteReport"
)

if ($result.schema -ne "skybridge.vite_chunk_warning_analysis.v1") { throw "Unexpected Vite chunk warning analysis schema." }
Assert-True $result.vite_warning_detected "vite_warning_detected"
if (@($result.oversized_chunks).Count -lt 1) { throw "Expected at least one oversized chunk." }
if ($null -eq $result.largest_chunk) { throw "Expected largest_chunk." }
if ([double]$result.threshold_observed -lt 500) { throw "Unexpected threshold_observed." }
Assert-True $result.remediation_deferred "remediation_deferred"
Assert-False $result.warning_suppressed "warning_suppressed"
Assert-False $result.chunk_size_limit_changed "chunk_size_limit_changed"
Assert-TokenPrintedFalse $result

Complete-Smoke "vite-chunk-warning-analysis-report"
