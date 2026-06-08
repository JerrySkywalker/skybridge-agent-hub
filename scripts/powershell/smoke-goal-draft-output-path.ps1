[CmdletBinding()]
param([switch]$Json)
$ErrorActionPreference = "Stop"
$result = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\skybridge-goal-draft.ps1" -Command goal-draft-generate-fixture -Fixture safe -Json | ConvertFrom-Json
if ([string]$result.proposed_markdown_path -notlike "goals/proposed/*") { throw "Preview output path is not under goals/proposed." }
& pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\skybridge-goal-draft.ps1" -Command goal-draft-generate-fixture -Fixture safe -DraftPath "goals/ready/bad.md" -Json *> $null
if ($LASTEXITCODE -eq 0) { throw "Expected output path escape to fail." }
$summary = [pscustomobject]@{ ok = $true; scenario = "goal-draft-output-path"; token_printed = $false }
if ($Json) { $summary | ConvertTo-Json -Compress } else { $summary | Format-List }
