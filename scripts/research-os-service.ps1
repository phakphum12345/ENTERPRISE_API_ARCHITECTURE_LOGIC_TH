param(
  [ValidateSet('install','uninstall','start','stop','restart','status')]
  [string]$Action = 'status',
  [string]$DataDir = "$env:USERPROFILE\ResearchOSData",
  [string]$ServiceName = 'ResearchOSService'
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $PSScriptRoot
$Project = Join-Path $RepoRoot 'tools\research_os_service\ResearchOS.ServiceHost.csproj'
$PublishDir = Join-Path $RepoRoot 'tools\research_os_service\publish'
$PackagedServiceDir = Join-Path $RepoRoot 'service_host'
$PackagedServiceExe = Join-Path $PackagedServiceDir 'ResearchOS.ServiceHost.exe'
$ServiceExe = Join-Path $PublishDir 'ResearchOS.ServiceHost.exe'
$BundledPython = Join-Path $RepoRoot 'runtime\python\python.exe'
$ApiPort = 0
$RegistryDir = Join-Path $DataDir 'run\services'
$ApiEndpointFile = Join-Path $RegistryDir 'research-os-api.json'

function Test-Admin {
  $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = New-Object Security.Principal.WindowsPrincipal($identity)
  return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Require-Admin {
  if (-not (Test-Admin)) {
    throw 'Administrator permission is required for this Service action.'
  }
}

function Get-ServiceSafe {
  return Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
}

function Wait-ServiceState([string]$Desired, [int]$Seconds = 20) {
  $deadline = (Get-Date).AddSeconds($Seconds)
  do {
    $svc = Get-ServiceSafe
    if ($svc -and $svc.Status.ToString() -eq $Desired) { return $svc }
    Start-Sleep -Milliseconds 350
  } while ((Get-Date) -lt $deadline)
  throw "Service did not reach state $Desired within $Seconds seconds."
}

function Get-CurrentApiPort {
  if (-not (Test-Path $ApiEndpointFile)) { return 0 }
  try {
    $endpoint = Get-Content -Path $ApiEndpointFile -Raw | ConvertFrom-Json
    if ($endpoint.schema_version -eq 1 -and
        $endpoint.service -eq 'research-os-api' -and
        $endpoint.host -in @('127.0.0.1', '::1', 'localhost') -and
        [int]$endpoint.port -ge 1 -and
        [int]$endpoint.port -le 65535) {
      return [int]$endpoint.port
    }
  } catch { }
  return 0
}

function Get-PortListeners([int]$Port = 0) {
  if ($Port -le 0) { $Port = Get-CurrentApiPort }
  if ($Port -le 0) { return @() }
  return @(Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue)
}

function Wait-ResearchOsApiReady([int]$Seconds = 40) {
  $deadline = (Get-Date).AddSeconds($Seconds)
  do {
    if (Test-Path $ApiEndpointFile) {
      try {
        $endpoint = Get-Content -Path $ApiEndpointFile -Raw | ConvertFrom-Json
        if ($endpoint.schema_version -eq 1 -and
            $endpoint.service -eq 'research-os-api' -and
            $endpoint.host -in @('127.0.0.1', '::1', 'localhost') -and
            [int]$endpoint.port -ge 1 -and
            [int]$endpoint.port -le 65535) {
          $owner = Get-Process -Id ([int]$endpoint.pid) -ErrorAction SilentlyContinue
          if ($owner) {
            $health = Invoke-RestMethod -Uri "$($endpoint.base_url)/health" -TimeoutSec 2
            if ($health.status -eq 'ok') { return $endpoint }
          }
        }
      } catch { }
    }
    Start-Sleep -Milliseconds 500
  } while ((Get-Date) -lt $deadline)
  throw "Research OS API did not publish a healthy dynamic endpoint within $Seconds seconds."
}

function Test-ResearchOsApiProcess([int]$ProcessId) {
  $process = Get-CimInstance Win32_Process -Filter "ProcessId=$ProcessId" -ErrorAction SilentlyContinue
  if (-not $process) { return $false }

  $commandLine = [string]$process.CommandLine
  $executablePath = [string]$process.ExecutablePath
  $normalizedRoot = [IO.Path]::GetFullPath($RepoRoot).TrimEnd('\')
  $normalizedBundledRoot = [IO.Path]::GetFullPath((Join-Path $RepoRoot 'runtime\python')).TrimEnd('\')

  $isBundledPython = $false
  if ($executablePath) {
    try {
      $normalizedExe = [IO.Path]::GetFullPath($executablePath)
      $isBundledPython = $normalizedExe.StartsWith(
        $normalizedBundledRoot + '\',
        [StringComparison]::OrdinalIgnoreCase
      )
    }
    catch {
      $isBundledPython = $false
    }
  }

  $isRepoRenderServer = $false
  if ($commandLine -and $commandLine -match '(?i)render_server\.py') {
    $isRepoRenderServer = $commandLine.IndexOf(
      $normalizedRoot,
      [StringComparison]::OrdinalIgnoreCase
    ) -ge 0
  }

  if ($isBundledPython -or $isRepoRenderServer) {
    Write-Host "Research OS API listener PID $ProcessId identified."
    Write-Host "Executable : $executablePath"
    Write-Host "CommandLine: $commandLine"
    return $true
  }

  Write-Warning "PID $ProcessId is listening on the discovered Research OS endpoint but does not look like a Research OS API process. It will not be terminated."
  Write-Warning "Executable : $executablePath"
  Write-Warning "CommandLine: $commandLine"
  return $false
}

function Stop-ResearchOsApiListener([int]$Seconds = 15) {
  $listeners = Get-PortListeners
  if (-not $listeners) { return }

  foreach ($listener in $listeners) {
    $pidToStop = [int]$listener.OwningProcess
    if ($pidToStop -le 0) { continue }

    if (Test-ResearchOsApiProcess -ProcessId $pidToStop) {
      Write-Host "Stopping orphan Research OS API process tree PID $pidToStop..."
      & taskkill.exe /PID $pidToStop /T /F | Out-Host
      if ($LASTEXITCODE -ne 0) {
        Stop-Process -Id $pidToStop -Force -ErrorAction SilentlyContinue
      }
    }
  }

  $deadline = (Get-Date).AddSeconds($Seconds)
  do {
    $remaining = Get-PortListeners
    if (-not $remaining) {
      Write-Host "Research OS API listener is free on its discovered endpoint."
      return
    }
    Start-Sleep -Milliseconds 500
  } while ((Get-Date) -lt $deadline)

  $remaining = Get-PortListeners
  foreach ($listener in $remaining) {
    $pidRemaining = [int]$listener.OwningProcess
    $process = Get-CimInstance Win32_Process -Filter "ProcessId=$pidRemaining" -ErrorAction SilentlyContinue
    Write-Warning "Discovered API listener remains: PID=$pidRemaining Executable=$($process.ExecutablePath) CommandLine=$($process.CommandLine)"
  }
  throw "Discovered Research OS API listener remains after service shutdown."
}

function Stop-ResearchOsServiceAndApi {
  $svc = Get-ServiceSafe
  if ($svc -and $svc.Status -ne 'Stopped') {
    Stop-Service -Name $ServiceName -Force
    Wait-ServiceState 'Stopped' | Out-Null
  }

  # A service can report Stopped before a spawned Python process has fully exited.
  # Only terminate listeners that can be positively identified as Research OS.
  Stop-ResearchOsApiListener
}

function Set-ServiceEnvironment([string]$PythonPath) {
  $serviceKey = "HKLM:\SYSTEM\CurrentControlSet\Services\$ServiceName"
  if (-not (Test-Path $serviceKey)) {
    throw "Windows Service registry key was not created: $serviceKey"
  }

  $values = @(
    "RESEARCH_OS_REPO_ROOT=$RepoRoot",
    "RESEARCH_OS_DATA_DIR=$DataDir",
    "RESEARCH_OS_PYTHON_EXE=$PythonPath",
    'RESEARCH_OS_API_HOST=127.0.0.1',
    "RESEARCH_OS_API_PORT=$ApiPort"
  )

  New-ItemProperty -Path $serviceKey -Name Environment -PropertyType MultiString -Value $values -Force | Out-Null
}

switch ($Action) {
  'status' {
    $svc = Get-ServiceSafe
    if (-not $svc) {
      Write-Host 'Research OS Service: NOT INSTALLED'
      exit 2
    }
    $startMode = (Get-CimInstance Win32_Service -Filter "Name='$ServiceName'").StartMode
    Write-Host "Research OS Service: $($svc.Status)"
    Write-Host "Service name       : $ServiceName"
    Write-Host "Startup            : $startMode"
    $currentPort = Get-CurrentApiPort
    if ($currentPort -le 0) {
      Write-Host "Local API          : UNAVAILABLE (registry not published)"
      exit 1
    }
    try {
      $health = Invoke-RestMethod -Uri "http://127.0.0.1:$currentPort/health" -TimeoutSec 3
      if ($health.status -ne 'ok') { throw "Health check failed." }
      Write-Host "Local API          : READY http://127.0.0.1:$currentPort"
    } catch {
      Write-Host "Local API          : UNAVAILABLE ($($_.Exception.Message))"
      exit 1
    }
    exit 0
  }

  'install' {
    Require-Admin

    if (Test-Path $PackagedServiceExe) {
      # Canonical installer layout: the self-contained ServiceHost is staged in
      # service_host. Never require the source .csproj or a developer SDK.
      $ServiceExe = $PackagedServiceExe
      Write-Host "Using packaged Research OS ServiceHost: $ServiceExe"
    }
    elseif (-not (Test-Path $ServiceExe)) {
      if (-not (Test-Path $Project)) {
        throw "ServiceHost binary/project not found under: $RepoRoot"
      }
      $dotnet = Get-Command dotnet.exe -ErrorAction SilentlyContinue
      if (-not $dotnet) {
        throw 'ServiceHost binary is missing and .NET SDK is not installed. Use the packaged Research OS installer.'
      }
      New-Item -ItemType Directory -Force -Path $PublishDir | Out-Null
      & $dotnet.Source publish $Project -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -p:PublishTrimmed=false -o $PublishDir
      if ($LASTEXITCODE -ne 0 -or -not (Test-Path $ServiceExe)) {
        throw 'Research OS ServiceHost publish failed.'
      }
    }

    if (Test-Path $BundledPython) {
      $python = $BundledPython
      Write-Host "Using bundled Python runtime: $python"
    }
    else {
      $pythonCommand = Get-Command python.exe -ErrorAction SilentlyContinue
      if (-not $pythonCommand) {
        throw 'Python runtime was not found. Install using the packaged Research OS installer or install Python for development mode.'
      }
      $python = $pythonCommand.Source
      Write-Host "Using system Python runtime: $python"
    }

    New-Item -ItemType Directory -Force -Path $DataDir | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $DataDir 'logs') | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $DataDir 'sessions') | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $DataDir 'database') | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $DataDir 'artifacts') | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $DataDir 'backups') | Out-Null
    New-Item -ItemType Directory -Force -Path $RegistryDir | Out-Null

    [Environment]::SetEnvironmentVariable('RESEARCH_OS_REPO_ROOT', $RepoRoot, 'Machine')
    [Environment]::SetEnvironmentVariable('RESEARCH_OS_DATA_DIR', $DataDir, 'Machine')
    [Environment]::SetEnvironmentVariable('RESEARCH_OS_PYTHON_EXE', $python, 'Machine')
    [Environment]::SetEnvironmentVariable('RESEARCH_OS_API_HOST', '127.0.0.1', 'Machine')
    [Environment]::SetEnvironmentVariable('RESEARCH_OS_API_PORT', "$ApiPort", 'Machine')

    $existing = Get-ServiceSafe
    if ($existing) {
      Stop-ResearchOsServiceAndApi
      sc.exe delete $ServiceName | Out-Null
      Start-Sleep -Seconds 1
    }

    $quotedExe = '"' + $ServiceExe + '"'
    sc.exe create $ServiceName binPath= $quotedExe start= auto DisplayName= 'Research OS API Service' | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Failed to create Research OS Windows Service.' }

    sc.exe description $ServiceName 'Research OS Local API, Memory, Google Workspace and AI backend service.' | Out-Null
    sc.exe config $ServiceName start= delayed-auto | Out-Null
    sc.exe failure $ServiceName reset= 86400 actions= restart/5000/restart/10000/restart/30000 | Out-Null
    sc.exe failureflag $ServiceName 1 | Out-Null
    Set-ServiceEnvironment -PythonPath $python

    try {
      Start-Service -Name $ServiceName
      Wait-ServiceState 'Running' | Out-Null
      $readyEndpoint = Wait-ResearchOsApiReady
    }
    catch {
      $svc = Get-ServiceSafe
      Write-Error "Research OS Service failed to start. Status=$($svc.Status) StartType=$((Get-CimInstance Win32_Service -Filter \"Name='$ServiceName'\").StartMode)"
      Write-Error "Service executable: $ServiceExe"
      Write-Error "Repo root: $RepoRoot"
      Write-Error "Data dir: $DataDir"
      throw
    }

    Write-Host 'Research OS Service installed and started.'
    Write-Host "Service : $ServiceName"
    Write-Host "API     : OS-assigned endpoint published to $ApiEndpointFile"
    Write-Host "Data    : $DataDir"
    Write-Host "Runtime : $python"
    Write-Host 'Recovery: restart after 5s, 10s, then 30s'
  }

  'uninstall' {
    Require-Admin
    $svc = Get-ServiceSafe
    if (-not $svc) {
      # The service may already be gone while a child process from a previous
      # shutdown is still alive. Clean only positively identified Research OS listeners.
      Stop-ResearchOsApiListener
      Write-Host 'Research OS Service is not installed.'
      exit 0
    }

    Stop-ResearchOsServiceAndApi
    sc.exe delete $ServiceName | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Failed to delete Research OS Service.' }

    $deadline = (Get-Date).AddSeconds(15)
    do {
      if (-not (Get-ServiceSafe)) { break }
      Start-Sleep -Milliseconds 500
    } while ((Get-Date) -lt $deadline)

    if (Get-ServiceSafe) {
      throw 'Research OS Service is still registered after delete.'
    }

    Stop-ResearchOsApiListener
    Write-Host 'Research OS Service uninstalled. Local data was preserved.'
  }

  'start' {
    Require-Admin
    if (-not (Get-ServiceSafe)) { throw 'Research OS Service is not installed.' }
    Start-Service -Name $ServiceName
    Wait-ServiceState 'Running' | Out-Null
    $readyEndpoint = Wait-ResearchOsApiReady
    Write-Host "Research OS Service started at $($readyEndpoint.base_url)."
  }

  'stop' {
    Require-Admin
    if (-not (Get-ServiceSafe)) { throw 'Research OS Service is not installed.' }
    Stop-ResearchOsServiceAndApi
    Write-Host 'Research OS Service stopped and API listener released.'
  }

  'restart' {
    Require-Admin
    if (-not (Get-ServiceSafe)) { throw 'Research OS Service is not installed.' }
    Stop-ResearchOsServiceAndApi
    Start-Service -Name $ServiceName
    Wait-ServiceState 'Running' | Out-Null
    $readyEndpoint = Wait-ResearchOsApiReady
    Write-Host "Research OS Service restarted at $($readyEndpoint.base_url)."
  }
}
