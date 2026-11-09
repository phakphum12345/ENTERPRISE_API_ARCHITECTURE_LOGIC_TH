param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('install', 'uninstall')]
    [string]$Action,

    [string]$ServiceName = 'ResearchOSV3Service',
    [int]$Port = 0
)

$ErrorActionPreference = 'Stop'

$appRoot = Split-Path -Parent $PSScriptRoot
$serviceExe = Join-Path $appRoot 'service\ResearchOS.V3.ServiceHost.exe'
$v3Root = Join-Path $appRoot 'v3'
$pythonExe = Join-Path $v3Root 'runtime\python\python.exe'
$dataDir = Join-Path $env:ProgramData 'ResearchOSV3'
$registryDir = Join-Path $dataDir 'run\services'
$endpointFile = Join-Path $registryDir 'research-os-v3.json'

function Remove-V3Service {
    $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if ($service -and $service.Status -ne 'Stopped') {
        Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue
        try {
            $service.WaitForStatus('Stopped', [TimeSpan]::FromSeconds(20))
        }
        catch { }
    }

    if (Get-Service -Name $ServiceName -ErrorAction SilentlyContinue) {
        sc.exe delete $ServiceName | Out-Null
        for ($attempt = 0; $attempt -lt 40; $attempt++) {
            if (-not (Get-Service -Name $ServiceName -ErrorAction SilentlyContinue)) {
                break
            }
            Start-Sleep -Milliseconds 250
        }
    }

    # ServiceHost owns the child process tree. Do not kill arbitrary port listeners.
}

if ($Action -eq 'uninstall') {
    Remove-V3Service
    Write-Host "Research OS V3 service removed. Data preserved at $dataDir"
    exit 0
}

if (-not (Test-Path $serviceExe -PathType Leaf)) {
    throw "V3 ServiceHost executable not found: $serviceExe"
}
if (-not (Test-Path $pythonExe -PathType Leaf)) {
    throw "Bundled Python executable not found: $pythonExe"
}
if (-not (Test-Path (Join-Path $v3Root 'scripts\run_service.py') -PathType Leaf)) {
    throw "V3 service entrypoint not found under $v3Root"
}

New-Item -ItemType Directory -Path $dataDir -Force | Out-Null
Remove-V3Service

$binaryPath = "`"$serviceExe`" --root `"$v3Root`" --python `"$pythonExe`" --port $Port --data-dir `"$dataDir`" --service-name `"$ServiceName`""
New-Service -Name $ServiceName -BinaryPathName $binaryPath -StartupType Automatic -DisplayName 'Research OS V3 Local Service' | Out-Null
Start-Service -Name $ServiceName

New-Item -ItemType Directory -Path $registryDir -Force | Out-Null
$readyEndpoint = $null
for ($attempt = 0; $attempt -lt 60; $attempt++) {
    try {
        if (Test-Path $endpointFile) {
            $candidate = Get-Content -Path $endpointFile -Raw | ConvertFrom-Json
            if ($candidate.schema_version -eq 1 -and
                $candidate.service -eq 'research-os-v3' -and
                $candidate.host -eq '127.0.0.1' -and
                [int]$candidate.port -ge 1 -and
                [int]$candidate.port -le 65535) {
                $owner = Get-Process -Id ([int]$candidate.pid) -ErrorAction SilentlyContinue
                if ($owner) {
                    $health = Invoke-RestMethod -Uri "$($candidate.base_url)/health" -TimeoutSec 2
                    if ($health.status -eq 'ok') {
                        $readyEndpoint = $candidate
                        break
                    }
                }
            }
        }
    }
    catch { }
    Start-Sleep -Milliseconds 500
}

if (-not $readyEndpoint) {
    throw 'Research OS V3 service did not publish a healthy dynamic endpoint after installation'
}

$listeners = @(Get-NetTCPConnection -LocalPort ([int]$readyEndpoint.port) -State Listen -ErrorAction Stop)
if ($listeners.Count -lt 1) {
    throw 'Research OS V3 service has no listening socket after installation'
}
if ($listeners | Where-Object { $_.LocalAddress -ne '127.0.0.1' }) {
    throw 'Research OS V3 service is not loopback-only'
}

Write-Host "Research OS V3 service installed and ready at $($readyEndpoint.base_url)"
