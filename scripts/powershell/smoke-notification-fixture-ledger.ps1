$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$result = & pwsh -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\skybridge-attention-fixture.ps1" -Command dispatch-fixture -Json | ConvertFrom-Json
if (-not $result.ok -or $result.external_notification_sent -ne $false) { throw "Fixture dispatch must write locally without external send." }
if ($result.token_printed -ne $false) { throw "Expected token_printed=false." }
$ledgerPath = Join-Path $repoRoot $result.fixture_ledger_file
if (-not (Test-Path -LiteralPath $ledgerPath -PathType Leaf)) { throw "Fixture ledger was not written." }
$ledgerText = Get-Content -Raw -LiteralPath $ledgerPath
if ($ledgerText -match '(?i)authorization\s*[:=]\s*bearer|bearer\s+[A-Za-z0-9_.-]{12,}|sk-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|raw_stdout|raw_stderr|raw_prompt|raw_worker_log') {
  throw "Fixture ledger contains secret-looking or raw-log text."
}
$ignored = git -C $repoRoot check-ignore $result.fixture_ledger_file
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($ignored)) { throw "Fixture ledger path is not gitignored." }

[pscustomobject]@{
  ok = $true
  scenario = "notification-fixture-ledger"
  fixture_ledger_file = $result.fixture_ledger_file
  external_notification_sent = $false
  token_printed = $false
} | ConvertTo-Json -Compress
