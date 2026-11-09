param(
  [string]$DataDir = "$env:USERPROFILE\ResearchOSData"
)

$ErrorActionPreference = "Stop"
$RegistryFile = Join-Path $DataDir "run\services\research-os-api.json"

if (-not (Test-Path $RegistryFile)) {
  Write-Host "Research OS API: NOT DISCOVERED"
  Write-Host "Registry       : $RegistryFile"
  exit 1
}

try {
  $endpoint = Get-Content -Path $RegistryFile -Raw | ConvertFrom-Json
  if ($endpoint.schema_version -ne 1 -or
      $endpoint.service -ne "research-os-api" -or
      $endpoint.host -notin @("127.0.0.1", "::1", "localhost") -or
      [int]$endpoint.port -lt 1 -or
      [int]$endpoint.port -gt 65535) {
    throw "Invalid endpoint registry record."
  }
  $owner = Get-Process -Id ([int]$endpoint.pid) -ErrorAction SilentlyContinue
  if (-not $owner) { throw "Endpoint owner process is no longer running." }
  $health = Invoke-RestMethod -Uri "$($endpoint.base_url)/health" -TimeoutSec 3
  if ($health.status -ne "ok") { throw "Health endpoint did not report status=ok." }
  Write-Host "Service  : Research OS API"
  Write-Host "State    : READY"
  Write-Host "Endpoint : $($endpoint.base_url)"
  Write-Host "PID      : $($endpoint.pid)"
  Write-Host "Version  : $($health.version)"
  exit 0
} catch {
  Write-Host "Service  : Research OS API"
  Write-Host "State    : UNAVAILABLE"
  Write-Host "Details  : $($_.Exception.Message)"
  exit 1
}
