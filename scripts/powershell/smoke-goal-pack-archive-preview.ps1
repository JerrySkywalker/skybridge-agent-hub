[CmdletBinding()]
param([switch]$Json)

. "$PSScriptRoot\goal-pack-smoke-fixtures.ps1"
$fixture = New-GoalPackSmokeFixture -Name "archive-preview"
$archiveRoot = Join-Path (Get-GoalPackSmokeRepoRoot) ".agent\tmp\goal-pack-smokes\archive-target"
if (Test-Path -LiteralPath $archiveRoot) { Remove-Item -LiteralPath $archiveRoot -Recurse -Force }
$result = Invoke-GoalPackHelper -Arguments @("-Command", "archive-preview", "-GoalPackDir", $fixture, "-ArchiveRoot", $archiveRoot)
if ($result.mode -ne "dry-run" -or $result.would_archive -ne $true) { throw "Archive preview must be dry-run and would_archive=true." }
if (Test-Path -LiteralPath (Join-Path $archiveRoot "dev-queue-189-200")) { throw "Archive preview created target directory." }
if (@($result.excludes) -notcontains "raw worker logs") { throw "Archive preview must exclude raw logs." }
Assert-NoExecutionResult $result

$summary = [pscustomobject]@{ ok = $true; archive_target = $result.archive_target; token_printed = $false }
if ($Json) { $summary | ConvertTo-Json -Compress } else { $summary | Format-List }
