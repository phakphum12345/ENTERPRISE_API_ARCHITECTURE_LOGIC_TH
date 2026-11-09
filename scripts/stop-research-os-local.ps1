param(
  [string]$DataDir = "$env:USERPROFILE\ResearchOSData"
)

$ErrorActionPreference = "Stop"
$RunDir = Join-Path $DataDir "run"
$RegistryDir = Join-Path $RunDir "services"

function Stop-VerifiedProcess([string]$PidFile, [string]$ExpectedCommand) {
  if (-not (Test-Path $PidFile)) { return }
  $raw = (Get-Content -Path $PidFile -Raw).Trim()
  $processId = 0
  if (-not [int]::TryParse($raw, [ref]$processId)) {
    Remove-Item $PidFile -Force -ErrorAction SilentlyContinue
    return
  }
  $processInfo = Get-CimInstance Win32_Process -Filter "ProcessId=$processId" -ErrorAction SilentlyContinue
  if ($processInfo -and ([string]$processInfo.CommandLine).Contains($ExpectedCommand)) {
    Stop-Process -Id $processId -Force -ErrorAction SilentlyContinue
    Write-Host "Stopped $ExpectedCommand (PID $processId)."
    foreach ($service in @("research-os-api", "owner-friend")) {
      $recordPath = Join-Path $RegistryDir "$service.json"
      if (Test-Path $recordPath) {
        try {
          $record = Get-Content -Path $recordPath -Raw | ConvertFrom-Json
          if ([int]$record.pid -eq $processId) {
            Remove-Item $recordPath -Force -ErrorAction SilentlyContinue
          }
        } catch { }
      }
    }
  } elseif (-not $processInfo) {
    Write-Host "Process $processId is already stopped."
  } else {
    Write-Warning "Refusing to stop PID $processId because its command line does not match $ExpectedCommand."
  }
  Remove-Item $PidFile -Force -ErrorAction SilentlyContinue
}

Stop-VerifiedProcess (Join-Path $RunDir "research-os-api.pid") "render_server.py"
Stop-VerifiedProcess (Join-Path $RunDir "research-os-friend.pid") "run_friend_service.py"

Write-Host "Research OS Local stop request completed. No unrelated port listener was terminated."
