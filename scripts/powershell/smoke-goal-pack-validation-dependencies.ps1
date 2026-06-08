[CmdletBinding()]
param([switch]$Json)

. "$PSScriptRoot\goal-pack-smoke-fixtures.ps1"
$fixture = New-GoalPackSmokeFixture -Name "dependencies"
$file = Join-Path $fixture "super-189-ci-guardian-pr-finalizer-hardening.md"
$text = Get-Content -Raw -LiteralPath $file
$text = $text -replace '"requires":\[\]', '"requires":["missing-goal-fixture"]'
Set-Content -LiteralPath $file -Value $text -Encoding UTF8
$result = Invoke-GoalPackHelper -Arguments @("-Command", "validate", "-GoalPackDir", $fixture)
if ($result.ok -ne $false) { throw "Missing dependency validation should fail." }
if ((@($result.errors) -join "`n") -notmatch "missing dependency") { throw "Missing dependency error not reported." }
Assert-NoExecutionResult $result

$summary = [pscustomobject]@{ ok = $true; dependency_errors = @($result.errors).Count; token_printed = $false }
if ($Json) { $summary | ConvertTo-Json -Compress } else { $summary | Format-List }
