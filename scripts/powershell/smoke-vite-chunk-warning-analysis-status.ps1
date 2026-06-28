. "$PSScriptRoot\smoke-productization-common.ps1"

$result = Invoke-JsonScript "skybridge-vite-chunk-warning-analysis.ps1" @(
  "-Command", "safe-summary"
)

if ($result.schema -ne "skybridge.vite_chunk_warning_analysis.v1") { throw "Unexpected Vite chunk warning analysis schema." }
Assert-False $result.warning_suppressed "warning_suppressed"
Assert-False $result.chunk_size_limit_changed "chunk_size_limit_changed"
Assert-True $result.remediation_deferred "remediation_deferred"
Assert-TokenPrintedFalse $result

Complete-Smoke "vite-chunk-warning-analysis-status"
