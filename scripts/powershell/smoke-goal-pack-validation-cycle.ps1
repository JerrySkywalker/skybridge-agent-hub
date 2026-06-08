[CmdletBinding()]
param([switch]$Json)

. "$PSScriptRoot\goal-pack-smoke-fixtures.ps1"
$fixture = New-GoalPackSmokeFixture -Name "cycle"
$file = Join-Path $fixture "super-189-ci-guardian-pr-finalizer-hardening.md"
$text = Get-Content -Raw -LiteralPath $file
$text = $text -replace '"requires":\[\]', '"requires":["super-190-campaign-run-report-evidence-ledger"]'
Set-Content -LiteralPath $file -Value $text -Encoding UTF8
$result = Invoke-GoalPackHelper -Arguments @("-Command", "validate", "-GoalPackDir", $fixture)
if ($result.ok -ne $false) { throw "Cycle validation should fail." }
$errors = @($result.errors) -join "`n"
if ($errors -notmatch "dependency cycle" -or $errors -notmatch "goal order/dependency mismatch") { throw "Cycle/order mismatch errors not reported." }
Assert-NoExecutionResult $result

$summary = [pscustomobject]@{ ok = $true; cycle_errors = @($result.errors).Count; token_printed = $false }
if ($Json) { $summary | ConvertTo-Json -Compress } else { $summary | Format-List }
