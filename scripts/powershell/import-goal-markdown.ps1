[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$GoalFile,
  [string]$ApiBase = $(if ($env:SKYBRIDGE_API_BASE) { $env:SKYBRIDGE_API_BASE } else { "http://127.0.0.1:8787" }),
  [string]$ProjectId = "skybridge-agent-hub",
  [switch]$Json
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "skybridge-worker-api.ps1")

function Get-GoalSection {
  param([string]$Text, [string]$Name)
  $pattern = "(?ms)^##\s+$([regex]::Escape($Name))\s*\r?\n(?<body>.*?)(?=^##\s+|\z)"
  $match = [regex]::Match($Text, $pattern)
  if (-not $match.Success) { return $null }
  return $match.Groups["body"].Value.Trim()
}

function Convert-BulletSectionToArray {
  param([string]$Text)
  if ([string]::IsNullOrWhiteSpace($Text)) { return @() }
  return @($Text -split "\r?\n" | ForEach-Object {
    ($_ -replace "^\s*[-*]\s*", "").Trim()
  } | Where-Object { $_ })
}

function Get-MetadataValue {
  param([string]$Text, [string]$Name)
  $match = [regex]::Match($Text, "(?m)^$([regex]::Escape($Name)):\s*(?<value>.+?)\s*$")
  if ($match.Success) { return $match.Groups["value"].Value.Trim() }
  return $null
}

$content = Get-Content -Raw -LiteralPath $GoalFile
$titleMatch = [regex]::Match($content, "(?m)^#\s+(?<title>.+?)\s*$")
if (-not $titleMatch.Success) { throw "Goal Markdown must start with a level-1 title." }

$goalId = Get-MetadataValue -Text $content -Name "goal_id"
$body = @{
  title = $titleMatch.Groups["title"].Value.Trim()
  summary = Get-GoalSection -Text $content -Name "Summary"
  status = $(if (Get-MetadataValue -Text $content -Name "status") { Get-MetadataValue -Text $content -Name "status" } else { "draft" })
  source = $(if (Get-MetadataValue -Text $content -Name "source") { Get-MetadataValue -Text $content -Name "source" } else { "markdown-import" })
  priority = $(if (Get-MetadataValue -Text $content -Name "priority") { Get-MetadataValue -Text $content -Name "priority" } else { "normal" })
  risk = $(if (Get-MetadataValue -Text $content -Name "risk") { Get-MetadataValue -Text $content -Name "risk" } else { "low" })
  acceptance_criteria = @(Convert-BulletSectionToArray (Get-GoalSection -Text $content -Name "Acceptance Criteria"))
  evidence_requirements = @(Convert-BulletSectionToArray (Get-GoalSection -Text $content -Name "Evidence Requirements"))
  dedupe_key = Get-MetadataValue -Text $content -Name "dedupe_key"
}
if ($goalId) { $body.goal_id = $goalId }

$result = Invoke-SkyBridgeApi -Method POST -Path "/v1/projects/$([uri]::EscapeDataString($ProjectId))/goals" -ApiBase $ApiBase -Body $body
if ($Json) { $result | ConvertTo-Json -Depth 20 -Compress }
else { $result | Format-List }
