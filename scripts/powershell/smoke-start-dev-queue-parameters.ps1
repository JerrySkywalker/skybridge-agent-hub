[CmdletBinding()]
param([switch]$Json)

$ErrorActionPreference = "Stop"
$scriptPath = Join-Path $PSScriptRoot "start-dev-queue-189-200.ps1"
$tokens = $null
$errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$errors)
if ($errors.Count -gt 0) { throw "start-dev-queue-189-200.ps1 failed parse validation." }

$parameterNames = @($ast.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath })
foreach ($name in @("GoalPackDir", "CampaignId", "MaxSteps", "MaxTasks", "OutputFile", "OutputDir", "DryRun", "Apply")) {
  if ($parameterNames -notcontains $name) { throw "Missing launcher parameter -$name." }
}

$raw = Get-Content -Raw -LiteralPath $scriptPath
foreach ($pattern in @(
  '\$GoalPackDir',
  '\$CampaignId',
  '"-MaxSteps", \[string\]\$MaxSteps',
  '"-MaxTasks", \[string\]\$MaxTasks',
  'resolved_parameters',
  'Use either -Apply or -DryRun'
)) {
  if ($raw -notmatch $pattern) { throw "Launcher missing expected implementation pattern: $pattern" }
}
if ($raw -match '"-MaxSteps", "12"|"-MaxTasks", "12"') { throw "Launcher still hard-codes MaxSteps or MaxTasks in runArgs." }

$summary = [pscustomobject]@{ ok = $true; parameters = $parameterNames; token_printed = $false }
if ($Json) { $summary | ConvertTo-Json -Depth 10 -Compress } else { $summary | Format-List }
