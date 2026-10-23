# Restart the configured local phone-test services. Secrets stay in backend/.env.
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$backendRoot = Join-Path $projectRoot 'backend'
$pythonPath = Join-Path $projectRoot '.venv/Scripts/python.exe'
$outputRoot = Join-Path $projectRoot 'output'
$statePath = Join-Path $outputRoot 'phone-services.json'

if (-not (Test-Path -LiteralPath $pythonPath)) { throw 'Create the project Python environment first.' }
if (-not (Test-Path -LiteralPath (Join-Path $backendRoot '.env'))) { throw 'Configure backend/.env first.' }
New-Item -ItemType Directory -Path $outputRoot -Force | Out-Null

& docker info --format '{{.ServerVersion}}' 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Start Docker Desktop, then run this script again.' }
& docker start maatriwatch-phone-db | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'The local phone-test database container is unavailable.' }

$prior = @{}
if (Test-Path -LiteralPath $statePath) {
    $prior = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json -AsHashtable
}
$services = @{}

function Start-PhoneService {
    param([string]$Name, [string[]]$PythonArguments, [string]$ExpectedCommand)
    if ($prior.ContainsKey($Name)) {
        $previous = Get-CimInstance Win32_Process -Filter "ProcessId = $($prior[$Name])" -ErrorAction SilentlyContinue
        if ($previous -and $previous.CommandLine.Contains($ExpectedCommand)) {
            $services[$Name] = $previous.ProcessId
            Write-Output "$Name is already running."
            return
        }
    }
    $process = Start-Process -FilePath $pythonPath -ArgumentList $PythonArguments -WorkingDirectory $backendRoot `
        -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $outputRoot "$Name.log") `
        -RedirectStandardError (Join-Path $outputRoot "$Name.err.log")
    $services[$Name] = $process.Id
    Write-Output "$Name started."
}

$listener = Get-NetTCPConnection -State Listen -LocalPort 8000 -ErrorAction SilentlyContinue
if ($listener) {
    $health = Invoke-RestMethod -Uri 'http://127.0.0.1:8000/healthz' -TimeoutSec 5
    if ($health.service -ne 'maatriwatch-api') { throw 'Port 8000 belongs to a different service.' }
    $services['phone-api'] = $listener.OwningProcess
    Write-Output 'phone-api is already running.'
} else {
    Start-PhoneService 'phone-api' @('-u', '-m', 'flask', '--app', 'app:create_app()', 'run', '--host', '127.0.0.1', '--port', '8000', '--no-reload') 'app:create_app()'
}
Start-PhoneService 'phone-reminders' @('-u', '-m', 'app.companion_worker') 'app.companion_worker'
Start-PhoneService 'phone-realtime' @('-u', '-m', 'app.realtime_worker') 'app.realtime_worker'
$services | ConvertTo-Json | Set-Content -LiteralPath $statePath

$devices = @(& adb devices | Select-String '^\S+\s+device$' | ForEach-Object { ($_.Line -split '\s+')[0] })
foreach ($deviceId in $devices) { & adb -s $deviceId reverse tcp:8000 tcp:8000 | Out-Null }
if ($devices.Count -eq 0) { Write-Output 'Reconnect the Android phone, then run this script again to restore its USB connection.' }
$ready = $false
for ($attempt = 0; $attempt -lt 6; $attempt++) {
    try {
        $status = Invoke-RestMethod -Uri 'http://127.0.0.1:8000/readyz' -TimeoutSec 4
        if ($status.status -eq 'ready') { $ready = $true; break }
    } catch { }
    Start-Sleep -Seconds 1
}
if (-not $ready) { throw 'The API is not ready. Check the local service logs in output/; do not share credentials.' }
Write-Output 'API ready: PostgreSQL and Firebase Auth.'
Write-Output 'Local data survives service restarts. Keep Docker Desktop and the laptop running while testing.'
