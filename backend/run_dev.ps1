$ErrorActionPreference = 'Stop'

$containerName = 'ir_postgres_postgis'
$python = Join-Path $PSScriptRoot '.venv\Scripts\python.exe'

if (-not (Test-Path -LiteralPath $python)) {
    throw 'No encuentro backend\.venv. Crea el entorno e instala requirements.txt primero.'
}

$containerEnvironment = @(docker inspect --format '{{range .Config.Env}}{{println .}}{{end}}' $containerName)
if ($LASTEXITCODE -ne 0) {
    throw "No pude leer la configuración del contenedor $containerName."
}

$databaseSettings = @{
    POSTGRES_DB = 'DB_NAME'
    POSTGRES_USER = 'DB_USER'
    POSTGRES_PASSWORD = 'DB_PASSWORD'
}
foreach ($setting in $databaseSettings.Keys) {
    $entry = $containerEnvironment | Where-Object { $_.StartsWith("$setting=") } | Select-Object -First 1
    if (-not $entry) {
        throw "Falta $setting en la configuración del contenedor $containerName."
    }
    Set-Item -Path "Env:$($databaseSettings[$setting])" -Value $entry.Substring($setting.Length + 1)
}

docker exec $containerName pg_isready -U $env:DB_USER -d $env:DB_NAME *> $null
if ($LASTEXITCODE -ne 0) {
    throw "El contenedor $containerName no está listo. Inícialo con docker compose antes de continuar."
}

$env:DB_ENGINE = 'postgresql'
$env:DB_HOST = '127.0.0.1'
$env:DB_PORT = '5433'
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

    & $python manage.py runserver 0.0.0.0:8000
    exit $LASTEXITCODE
}
finally {
    Pop-Location
}