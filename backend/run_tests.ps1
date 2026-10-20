$ErrorActionPreference = 'Stop'
$irPython = Join-Path $PSScriptRoot '.venv\Scripts\python.exe'
if (-not (Test-Path -LiteralPath $irPython)) { throw 'Instala backend\.venv y requirements.txt primero.' }
. (Join-Path $PSScriptRoot 'docker_database.ps1')

# Copia solo el esquema externo: no copia usuarios, claves, viajes ni saldos.
$irTables = @(
    'usuario', 'rangos', 'zona_geografica', 'tarifa', 'perfil_pasajero',
    'perfil_conductor', 'vehiculo', 'documentos', 'viaje', 'ofertas',
    'transacciones', 'historial_puntos', 'tickets_de_soporte',
    'retiro_bonificacion', 'bonificacion_usuario'
)
$irDumpArguments = @('exec', $irContainerName, 'pg_dump', '-U', $env:DB_USER, '-d', $env:DB_NAME, '--schema-only', '--no-owner', '--no-privileges')
foreach ($irTable in $irTables) { $irDumpArguments += @('--table', "public.$irTable") }
$irSchema = & docker @irDumpArguments
if ($LASTEXITCODE -ne 0) { throw 'No pude leer el esquema PostgreSQL.' }

$irTestDatabase = 'test_ir_' + [guid]::NewGuid().ToString('N')
$irPreviousTestName = $env:DB_TEST_NAME
docker exec $irContainerName createdb -U $env:DB_USER $irTestDatabase
if ($LASTEXITCODE -ne 0) { throw 'No pude crear la base aislada de pruebas.' }
try {
    docker exec $irContainerName psql -U $env:DB_USER -d $irTestDatabase -v ON_ERROR_STOP=1 -c 'CREATE EXTENSION IF NOT EXISTS postgis;' | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'No pude habilitar PostGIS para las pruebas.' }
    $irSchema | docker exec -i $irContainerName psql -U $env:DB_USER -d $irTestDatabase -v ON_ERROR_STOP=1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'No pude preparar el esquema de pruebas.' }
    $env:DB_TEST_NAME = $irTestDatabase
    Push-Location $PSScriptRoot
    try {
        & $irPython manage.py test coredata config.tests --keepdb --noinput
        if ($LASTEXITCODE -ne 0) { throw 'Fallaron las pruebas de persistencia.' }
    }
    finally { Pop-Location }
}
finally {
    $env:DB_TEST_NAME = $irPreviousTestName
    # Nombre generado aqui; nunca se elimina la base de la aplicacion.
    if ($irTestDatabase -notmatch '^test_ir_[a-f0-9]{32}$') { throw 'Nombre de base de pruebas inesperado.' }
    docker exec $irContainerName dropdb -U $env:DB_USER --force $irTestDatabase
    if ($LASTEXITCODE -ne 0) { Write-Warning "No pude limpiar la base temporal $irTestDatabase." }
}
