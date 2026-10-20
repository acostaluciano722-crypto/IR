# Carga la conexion del contenedor existente sin guardar ni imprimir credenciales.
$ErrorActionPreference = 'Stop'
$irContainerName = 'ir_postgres_postgis'
$irInspection = docker inspect $irContainerName | ConvertFrom-Json
if ($LASTEXITCODE -ne 0 -or -not $irInspection) {
    throw "No pude inspeccionar el contenedor $irContainerName."
}
$irContainer = @($irInspection)[0]
if (-not $irContainer.State.Running) {
    throw "El contenedor $irContainerName esta detenido. Inicialo en Docker Desktop."
}
foreach ($irPair in @(
    @('POSTGRES_DB', 'DB_NAME'),
    @('POSTGRES_USER', 'DB_USER'),
    @('POSTGRES_PASSWORD', 'DB_PASSWORD')
)) {
    $irEntry = $irContainer.Config.Env | Where-Object { $_.StartsWith("$($irPair[0])=") } | Select-Object -First 1
    if (-not $irEntry) { throw "Falta $($irPair[0]) en $irContainerName." }
    Set-Item -Path "Env:$($irPair[1])" -Value $irEntry.Substring($irPair[0].Length + 1)
}
$irBinding = @($irContainer.NetworkSettings.Ports.'5432/tcp') | Select-Object -First 1
if (-not $irBinding -or -not $irBinding.HostPort) {
    throw 'PostgreSQL no tiene un puerto publicado en el equipo.'
}
$env:DB_ENGINE = 'postgresql'
$env:DB_HOST = if ($irBinding.HostIp -in @('0.0.0.0', '::', '')) { '127.0.0.1' } else { $irBinding.HostIp }
$env:DB_PORT = $irBinding.HostPort
docker exec $irContainerName pg_isready -U $env:DB_USER -d $env:DB_NAME *> $null
if ($LASTEXITCODE -ne 0) { throw "PostgreSQL no esta listo en $irContainerName." }
