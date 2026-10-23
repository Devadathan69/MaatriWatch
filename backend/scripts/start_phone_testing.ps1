# Start phone-test services using the configured local or cloud database.
[CmdletBinding()]
param([switch]$Restart)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$backendRoot = Join-Path $projectRoot 'backend'
$pythonPath = Join-Path $projectRoot '.venv/Scripts/python.exe'
$outputRoot = Join-Path $projectRoot 'output'
$statePath = Join-Path $outputRoot 'phone-services.json'

if (-not (Test-Path -LiteralPath $pythonPath)) { throw 'Create the project Python environment first.' }
$pythonPath = (Get-Item -LiteralPath $pythonPath).FullName
$allowedPythonPaths = @($pythonPath, (& $pythonPath -c 'import sys; print(sys._base_executable)'))
if (-not (Test-Path -LiteralPath (Join-Path $backendRoot '.env'))) { throw 'Configure backend/.env first.' }
New-Item -ItemType Directory -Path $outputRoot -Force | Out-Null

$modeCheck = @'
import sys
from dotenv import dotenv_values
from psycopg.conninfo import conninfo_to_dict
try:
    config = conninfo_to_dict(dotenv_values(sys.argv[1]).get('DATABASE_URL') or '')
    if not config.get('host') or not config.get('dbname'):
        raise ValueError()
    print('local-container' if config['host'] in ('127.0.0.1', 'localhost') and config.get('port', '5432') == '5433' else 'external')
except Exception:
    print('Configure a valid DATABASE_URL in backend/.env.', file=sys.stderr)
    sys.exit(1)
'@
$databaseMode = & $pythonPath -c $modeCheck (Join-Path $backendRoot '.env')
if ($LASTEXITCODE -ne 0) { throw 'The database configuration could not be read.' }
if ($databaseMode -eq 'local-container') {
    & docker info --format '{{.ServerVersion}}' 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Start Docker Desktop, then run this script again.' }
    & docker start maatriwatch-phone-db | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'The local phone-test database container is unavailable.' }
} else {
    Write-Output 'Using the configured external PostgreSQL database; Docker is not required.'
}

$prior = @{}
if (Test-Path -LiteralPath $statePath) {
    $prior = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json -AsHashtable
}
$services = @{}
$expectedCommands = @{
    'phone-api' = 'app:create_app()'
    'phone-reminders' = 'app.companion_worker'
    'phone-realtime' = 'app.realtime_worker'
}
if ($Restart) {
    foreach ($name in $expectedCommands.Keys) {
        if (-not $prior.ContainsKey($name)) { continue }
        $previous = Get-CimInstance Win32_Process -Filter "ProcessId = $($prior[$name])" -ErrorAction SilentlyContinue
        if ($previous -and $previous.CommandLine -and $previous.CommandLine.Contains($expectedCommands[$name]) -and
            $previous.ExecutablePath -in $allowedPythonPaths) {
            # Windows virtualenv launchers have a separate interpreter child.
            $children = @(Get-CimInstance Win32_Process -Filter "ParentProcessId = $($previous.ProcessId)" -ErrorAction SilentlyContinue)
            foreach ($child in $children) {
                if ($child.ExecutablePath -in $allowedPythonPaths -and $child.CommandLine -and
                    $child.CommandLine.Contains($expectedCommands[$name])) {
                    Stop-Process -Id $child.ProcessId -Force -ErrorAction SilentlyContinue
                }
            }
            Stop-Process -Id $previous.ProcessId -Force -ErrorAction SilentlyContinue
            Wait-Process -Id $previous.ProcessId -Timeout 10 -ErrorAction SilentlyContinue
            Write-Output "$name stopped for configuration reload."
        }
    }
}

function Start-PhoneService {
    param([string]$Name, [string[]]$PythonArguments, [string]$ExpectedCommand)
    if ($prior.ContainsKey($Name)) {
        $previous = Get-CimInstance Win32_Process -Filter "ProcessId = $($prior[$Name])" -ErrorAction SilentlyContinue
        if ($previous -and $previous.CommandLine -and $previous.CommandLine.Contains($ExpectedCommand) -and
            $previous.ExecutablePath -in $allowedPythonPaths) {
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
    if ($Restart) { throw 'Port 8000 is still occupied; the recorded API could not be restarted safely.' }
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

$devices = @()
if (Get-Command adb -ErrorAction SilentlyContinue) {
    $devices = @(& adb devices | Select-String '^\S+\s+device$' | ForEach-Object { ($_.Line -split '\s+')[0] })
}
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
Write-Output 'Data survives service restarts. Keep the laptop and API/workers running while testing.'
if ($databaseMode -eq 'local-container') { Write-Output 'Keep Docker Desktop running for the local database.' }
