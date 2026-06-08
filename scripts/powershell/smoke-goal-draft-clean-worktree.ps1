[CmdletBinding()]
param([switch]$Json)
$ErrorActionPreference = "Stop"
$before = (git status --short) -join "`n"
& pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\skybridge-goal-draft.ps1" -Command goal-draft-generate-preview -Json | Out-Null
& pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\skybridge-goal-draft.ps1" -Command goal-draft-safe-summary -Json | Out-Null
$after = (git status --short) -join "`n"
if ($before -ne $after) { throw "Dry-run goal draft smokes changed git status." }
$summary = [pscustomobject]@{ ok = $true; scenario = "goal-draft-clean-worktree"; token_printed = $false }
if ($Json) { $summary | ConvertTo-Json -Compress } else { $summary | Format-List }
