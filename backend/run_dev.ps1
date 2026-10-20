param([switch]$CheckOnly)

$ErrorActionPreference = 'Stop'

$python = Join-Path $PSScriptRoot '.venv\Scripts\python.exe'

if (-not (Test-Path -LiteralPath $python)) {
    throw 'No encuentro backend\.venv. Crea el entorno e instala requirements.txt primero.'
}

. (Join-Path $PSScriptRoot 'docker_database.ps1')
$env:DJANGO_DEBUG = 'true'
$env:CORS_ALLOW_ALL_ORIGINS = 'true'

$lanAddresses = @(
    Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' } |
        ForEach-Object { $_.IPAddress }
)
$allowedHosts = @('localhost', '127.0.0.1', '0.0.0.0', '10.0.2.2') + $lanAddresses
$env:ALLOWED_HOSTS = ($allowedHosts | Sort-Object -Unique) -join ','

Push-Location $PSScriptRoot
try {
    & $python manage.py migrate
    if ($LASTEXITCODE -ne 0) {
        throw 'No se pudieron aplicar/verificar las migraciones.'
    }

    & $python manage.py check_database
    if ($LASTEXITCODE -ne 0) {
        throw 'La base de datos no tiene el esquema que necesita la API.'
    }
    if ($CheckOnly) { return }

    & $python manage.py runserver 0.0.0.0:8000
    exit $LASTEXITCODE
}
finally {
    Pop-Location
}
