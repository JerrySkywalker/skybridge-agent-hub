[CmdletBinding(DefaultParameterSetName = "Check")]
param(
  [Parameter(ParameterSetName = "Check")]
  [switch]$CheckOnly,

  [Parameter(ParameterSetName = "Start")]
  [switch]$Start,

  [Parameter(ParameterSetName = "Restart")]
  [switch]$Restart,

  [switch]$Json,

  [string]$HostName = "127.0.0.1",

  [int]$LocalPort = 18642,

  [string]$RemoteHost = "127.0.0.1",

  [int]$RemotePort = 8642,

  [string]$SshTarget = "<PRIVATE_DEPLOY_HOST>"
)

$ErrorActionPreference = "Stop"

function Test-TcpPort {
  param([string]$HostName, [int]$Port)

  $client = [System.Net.Sockets.TcpClient]::new()
  try {
    $task = $client.ConnectAsync($HostName, $Port)
    $connected = $task.Wait(1000)
    return ($connected -and $client.Connected)
  } catch {
    return $false
  } finally {
    $client.Dispose()
  }
}

function Get-HermesTunnelProcess {
  $needleA = "-L"
  $needleB = "$($LocalPort):$($RemoteHost):$($RemotePort)"
  $needleC = $SshTarget

  if ($IsWindows -or $env:OS -eq "Windows_NT") {
    return @(Get-CimInstance Win32_Process -Filter "Name = 'ssh.exe'" -ErrorAction SilentlyContinue | Where-Object {
      $_.CommandLine -and $_.CommandLine.Contains($needleA) -and $_.CommandLine.Contains($needleB) -and $_.CommandLine.Contains($needleC)
    } | ForEach-Object {
      [pscustomobject]@{
        id = [int]$_.ProcessId
        command_included = $false
      }
    })
  }

  return @(Get-Process ssh -ErrorAction SilentlyContinue | Where-Object {
    $commandLine = $null
    try {
      $cmdlinePath = "/proc/$($_.Id)/cmdline"
      if (Test-Path -LiteralPath $cmdlinePath -PathType Leaf) {
        $commandLine = (Get-Content -LiteralPath $cmdlinePath -Raw) -replace "`0", " "
      }
    } catch {
      $commandLine = $null
    }
    $commandLine -and $commandLine.Contains($needleA) -and $commandLine.Contains($needleB) -and $commandLine.Contains($needleC)
  } | ForEach-Object {
    [pscustomobject]@{
      id = [int]$_.Id
      command_included = $false
    }
  })
}

function Stop-HermesTunnelProcess {
  param([object[]]$Processes)

  foreach ($process in @($Processes)) {
    Stop-Process -Id $process.id -Force -ErrorAction Stop
  }
}

$mode = if ($Restart) { "restart" } elseif ($Start) { "start" } else { "check" }
$listeningBefore = Test-TcpPort -HostName $HostName -Port $LocalPort
$processesBefore = @(Get-HermesTunnelProcess)
$started = $false
$stopped = 0
$errorMessage = $null
$recovery = @()

if ($mode -eq "restart" -and $processesBefore.Count -gt 0) {
  Stop-HermesTunnelProcess -Processes $processesBefore
  $stopped = $processesBefore.Count
  Start-Sleep -Seconds 1
  $listeningBefore = Test-TcpPort -HostName $HostName -Port $LocalPort
}

if ($mode -in @("start", "restart")) {
  if ($listeningBefore) {
    $recovery += "Local port $LocalPort is already listening; no duplicate tunnel was started."
  } else {
    $ssh = Get-Command ssh -ErrorAction SilentlyContinue
    if (-not $ssh) {
      $errorMessage = "ssh_not_available"
      $recovery += "Install OpenSSH Client or put ssh on PATH, then rerun this script with -Start."
    } else {
      $arguments = @(
        "-N",
        "-L", "$($LocalPort):$($RemoteHost):$($RemotePort)",
        "-o", "ExitOnForwardFailure=yes",
        "-o", "ServerAliveInterval=30",
        "-o", "ServerAliveCountMax=3",
        $SshTarget
      )
      try {
        if ($IsWindows -or $env:OS -eq "Windows_NT") {
          Start-Process -FilePath $ssh.Source -ArgumentList $arguments -WindowStyle Hidden | Out-Null
        } else {
          Start-Process -FilePath $ssh.Source -ArgumentList $arguments | Out-Null
        }
        $started = $true
        Start-Sleep -Seconds 2
      } catch {
        $errorMessage = $_.Exception.Message
      }
    }
  }
}

$listeningAfter = Test-TcpPort -HostName $HostName -Port $LocalPort
$processesAfter = @(Get-HermesTunnelProcess)

if (-not $listeningAfter) {
  $recovery += "Hermes tunnel is not listening on $HostName`:$LocalPort."
  $recovery += "If the laptop just slept or changed networks, rerun: pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\start-hermes-tunnel.ps1 -Restart"
  $recovery += "If restart fails, verify SSH access with: ssh <PRIVATE_DEPLOY_HOST>"
  $recovery += "Keep Hermes private; do not expose the remote API port publicly."
}

$summary = [ordered]@{
  ok = ($listeningAfter -and [string]::IsNullOrWhiteSpace($errorMessage))
  mode = $mode
  local_host = $HostName
  local_port = $LocalPort
  remote_host = $RemoteHost
  remote_port = $RemotePort
  ssh_target = $SshTarget
  listening_before = $listeningBefore
  listening = $listeningAfter
  matching_processes_before = $processesBefore.Count
  matching_processes = $processesAfter.Count
  started = $started
  stopped = $stopped
  duplicate_started = $false
  hermes_api_key_value_included = $false
  error = $errorMessage
  recovery = @($recovery | Select-Object -Unique)
}

if ($Json) {
  $summary | ConvertTo-Json -Depth 8
} else {
  Write-Host "[hermes-tunnel] mode=$mode listening=$($summary.listening) started=$started processes=$($summary.matching_processes)"
  foreach ($step in $summary.recovery) {
    Write-Host "[hermes-tunnel] recovery: $step"
  }
}

if (-not $summary.ok -and $mode -ne "check") {
  exit 1
}
