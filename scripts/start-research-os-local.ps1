param(
  [string]$DataDir = "$env:USERPROFILE\ResearchOSData",
  [string]$HostAddress = "127.0.0.1",
  [int]$Port = 0,
  [int]$FriendPort = 0,
  [ValidateSet("gemini", "mock", "local", "openai-compatible", "anthropic")]
  [string]$Provider = "gemini",
  [switch]$Background
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
# Establish the repository import boundary for every child Python process. The local
# launcher intentionally starts render_server.py from tools/research_os_api, while
# Platform modules remain canonical under the repository-level tools package.
$repoPythonPath = $RepoRoot
if ([string]::IsNullOrWhiteSpace($env:PYTHONPATH)) {
  $env:PYTHONPATH = $repoPythonPath
} elseif (($env:PYTHONPATH -split [IO.Path]::PathSeparator) -notcontains $repoPythonPath) {
  $env:PYTHONPATH = "$repoPythonPath$([IO.Path]::PathSeparator)$env:PYTHONPATH"
}
$ApiDir = Join-Path $RepoRoot "tools\research_os_api"
$FriendScript = Join-Path $RepoRoot "owner_special\scripts\run_friend_service.py"
$RunDir = Join-Path $DataDir "run"
$LogDir = Join-Path $DataDir "logs"
$PidFile = Join-Path $RunDir "research-os-api.pid"
$FriendPidFile = Join-Path $RunDir "research-os-friend.pid"
$OutLog = Join-Path $LogDir "research-os-api.out.log"
$ErrLog = Join-Path $LogDir "research-os-api.err.log"
$FriendOutLog = Join-Path $LogDir "research-os-friend.out.log"
$FriendErrLog = Join-Path $LogDir "research-os-friend.err.log"
$FriendDataDir = Join-Path $DataDir "owner-friend"
$FriendAuditPath = Join-Path $LogDir "research-os-friend.audit.jsonl"
$RegistryDir = Join-Path $RunDir "services"
$FriendEndpointFile = Join-Path $RegistryDir "owner-friend.json"
$FriendUrl = $null

if (-not (Test-Path $ApiDir)) {
  throw "Research OS API directory not found: $ApiDir"
}
if (-not (Test-Path $FriendScript)) {
  throw "Research OS Friend service entrypoint not found: $FriendScript"
}

@(
  $DataDir,
  (Join-Path $DataDir "sessions"),
  (Join-Path $DataDir "database"),
  (Join-Path $DataDir "artifacts"),
  (Join-Path $DataDir "backups"),
  $FriendDataDir,
  $RunDir,
  $LogDir
) | ForEach-Object { New-Item -ItemType Directory -Force -Path $_ | Out-Null }

$env:RESEARCH_OS_DATA_DIR = $DataDir
$env:RESEARCH_OS_SERVICE_REGISTRY_DIR = $RegistryDir
New-Item -ItemType Directory -Force -Path $RegistryDir | Out-Null
$env:RESEARCH_OS_CONVERSATION_STORE = Join-Path $DataDir "sessions\conversations.json"
$env:RESEARCH_OS_PROVIDER = $Provider
$env:RESEARCH_OS_API_HOST = $HostAddress
$env:RESEARCH_OS_API_PORT = "$Port"
$env:RESEARCH_OS_FRIEND_OWNER = "owner"
$env:RESEARCH_OS_AI_ROUTE = "friend"
$env:HOST = $HostAddress
$env:PORT = "$Port"

function Get-FriendEndpoint {
  if (-not (Test-Path $FriendEndpointFile)) { return $null }
  try {
    $endpoint = Get-Content -Path $FriendEndpointFile -Raw | ConvertFrom-Json
    if ($endpoint.schema_version -ne 1 -or
        $endpoint.service -ne "owner-friend" -or
        $endpoint.host -ne "127.0.0.1" -or
        [int]$endpoint.port -lt 1 -or
        [int]$endpoint.port -gt 65535 -or
        [string]::IsNullOrWhiteSpace([string]$endpoint.base_url)) {
      return $null
    }
    $owner = Get-Process -Id ([int]$endpoint.pid) -ErrorAction SilentlyContinue
    if (-not $owner) { return $null }
    return $endpoint
  } catch {
    return $null
  }
}

function Test-FriendHealth {
  $endpoint = Get-FriendEndpoint
  if (-not $endpoint) { return $false }
  try {
    $health = Invoke-RestMethod "$($endpoint.base_url)/owner/health" -TimeoutSec 2
    if ($health.status -eq "ok") {
      $script:FriendUrl = [string]$endpoint.base_url
      return $true
    }
    return $false
  } catch {
    return $false
  }
}

function Start-FriendService {
  if (Test-FriendHealth) {
    Write-Host "Friend Service already running at $FriendUrl."
    return $null
  }

  $startArgs = @{
    FilePath = "python"
    ArgumentList = @(
      $FriendScript,
      "--owner-id", "owner",
      "--host", "127.0.0.1",
      "--port", "$FriendPort",
      "--registry-dir", $RegistryDir,
      "--data-root", $FriendDataDir,
      "--audit-path", $FriendAuditPath,
      "--repository-root", $RepoRoot
    )
    WorkingDirectory = $RepoRoot
    WindowStyle = "Hidden"
    RedirectStandardOutput = $FriendOutLog
    RedirectStandardError = $FriendErrLog
    PassThru = $true
  }
  $process = Start-Process @startArgs
  Set-Content -Path $FriendPidFile -Value $process.Id -NoNewline

  for ($i = 0; $i -lt 40; $i++) {
    if (Test-FriendHealth) {
      Write-Host "Friend Service ready at $FriendUrl (PID $($process.Id))."
      return $process
    }
    if ($process.HasExited) {
      $detail = if (Test-Path $FriendErrLog) { Get-Content $FriendErrLog -Tail 20 | Out-String } else { "no stderr log" }
      throw "Friend Service exited before becoming ready. $detail"
    }
    Start-Sleep -Milliseconds 250
  }

  if (-not $process.HasExited) {
    Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
  }
  throw "Friend Service did not become ready at $FriendUrl. See $FriendErrLog"
}

function Stop-ProcessFromPidFile([string]$Path) {
  if (-not (Test-Path $Path)) { return }
  $pidText = (Get-Content $Path -Raw).Trim()
  $pidValue = 0
  if ([int]::TryParse($pidText, [ref]$pidValue)) {
    Stop-Process -Id $pidValue -Force -ErrorAction SilentlyContinue
  }
  Remove-Item $Path -Force -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host "Research OS Local API + Friend Service"
Write-Host "Data directory : $DataDir"
Write-Host "Provider       : $Provider"
Write-Host "Friend URL     : resolved dynamically after service startup"
Write-Host "Local API      : OS-assigned TCP port (registry discovery)"
Write-Host ""
Write-Host "Friend Service is a required local dependency for RESEARCH_OS_AI_ROUTE=friend."
Write-Host "Secrets are NOT stored by this script."
Write-Host "Set GEMINI_API_KEY / RESEARCH_OS_GEMINI_API_KEY in your Windows environment when ready."
Write-Host ""

$friendProcess = Start-FriendService
if (-not (Test-FriendHealth)) {
  throw "Friend Service did not publish a healthy dynamic endpoint. See $FriendErrLog"
}
$env:RESEARCH_OS_FRIEND_URL = $FriendUrl
Write-Host "Friend Service URL: $FriendUrl"

if ($Background) {
  if (Test-Path $PidFile) {
    $existingPidText = (Get-Content $PidFile -Raw).Trim()
    $existingPid = 0
    if ([int]::TryParse($existingPidText, [ref]$existingPid)) {
      $existing = Get-Process -Id $existingPid -ErrorAction SilentlyContinue
      if ($existing) {
        if (-not $friendProcess) {
          Write-Host "Research OS Local API is already running (PID $existingPid) and its Friend dependency is healthy."
          exit 0
        }
        $existingInfo = Get-CimInstance Win32_Process -Filter "ProcessId=$existingPid" -ErrorAction SilentlyContinue
        if (-not $existingInfo -or ([string]$existingInfo.CommandLine) -notmatch 'render_server\.py') {
          throw "Refusing to restart PID $existingPid because it is not a verified Research OS render_server.py process."
        }
        Stop-Process -Id $existingPid -Force -ErrorAction SilentlyContinue
        Wait-Process -Id $existingPid -Timeout 10 -ErrorAction SilentlyContinue
        if (Test-Path $PidFile) { Remove-Item $PidFile -Force -ErrorAction SilentlyContinue }
        if (Test-Path (Join-Path $RegistryDir "research-os-api.json")) {
          try {
            $oldEndpoint = Get-Content (Join-Path $RegistryDir "research-os-api.json") -Raw | ConvertFrom-Json
            if ([int]$oldEndpoint.pid -eq $existingPid) {
              Remove-Item (Join-Path $RegistryDir "research-os-api.json") -Force -ErrorAction SilentlyContinue
            }
          } catch { }
        }
        Write-Host "Restarting Research OS API so it adopts the newly discovered Friend endpoint."
      }
    }
    Remove-Item $PidFile -Force -ErrorAction SilentlyContinue
  }

  $startArgs = @{
    FilePath = "python"
    ArgumentList = "render_server.py"
    WorkingDirectory = $ApiDir
    WindowStyle = "Hidden"
    RedirectStandardOutput = $OutLog
    RedirectStandardError = $ErrLog
    PassThru = $true
  }
  $process = Start-Process @startArgs
  Set-Content -Path $PidFile -Value $process.Id -NoNewline
  Write-Host "Research OS Local API started in background (PID $($process.Id))."
  Write-Host "Friend Service PID : $($friendProcess.Id)"
  Write-Host "PID files : $PidFile / $FriendPidFile"
  Write-Host "Logs     : $LogDir"
  exit 0
}

try {
  Push-Location $ApiDir
  python render_server.py
}
finally {
  Pop-Location
  if ($friendProcess -and -not $friendProcess.HasExited) {
    Stop-Process -Id $friendProcess.Id -Force -ErrorAction SilentlyContinue
  }
  Remove-Item $FriendPidFile -Force -ErrorAction SilentlyContinue
}
