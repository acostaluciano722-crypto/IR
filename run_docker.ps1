param([switch]$CheckOnly, [switch]$SkipBuild)

$ErrorActionPreference = 'Stop'
$irComposeArguments = @('compose', '--project-directory', $PSScriptRoot, '-f', (Join-Path $PSScriptRoot 'compose.yaml'))
$irEnvironmentNames = @('DB_ENGINE', 'DB_HOST', 'DB_PORT', 'DB_NAME', 'DB_USER', 'DB_PASSWORD', 'ALLOWED_HOSTS', 'IR_DOCKER_NETWORK')
$irPreviousEnvironment = @{}
foreach ($irName in $irEnvironmentNames) {
    $irPreviousEnvironment[$irName] = [Environment]::GetEnvironmentVariable($irName, 'Process')
}

try {
    # Recupera las credenciales existentes solo en memoria y verifica PostGIS.
    . (Join-Path $PSScriptRoot 'backend\docker_database.ps1')
    $env:DB_HOST = $irContainerName
    $env:DB_PORT = '5432'
    # Resolve .env overrides without writing the rendered configuration or its secrets.
    $irComposeJson = & docker @irComposeArguments config --format json
    if ($LASTEXITCODE -ne 0) { throw 'La configuracion Compose no es valida.' }
    $irComposeConfiguration = $irComposeJson | ConvertFrom-Json
    $irNetworkName = $irComposeConfiguration.networks.ecosystem.name

    if (-not $CheckOnly) {
        $irBackendPort = [int]$irComposeConfiguration.services.backend.ports[0].published
        $irExistingBackend = docker ps --filter 'label=com.docker.compose.project=ir' --filter 'label=com.docker.compose.service=backend' --format '{{.ID}}'
        if ($LASTEXITCODE -ne 0) { throw 'No pude consultar el backend Docker existente.' }
        if (-not $irExistingBackend -and (Get-NetTCPConnection -LocalPort $irBackendPort -State Listen -ErrorAction SilentlyContinue)) {
            throw "El puerto $irBackendPort esta ocupado. Deten el servidor local o define BACKEND_PORT antes de iniciar Docker."
        }
    }

    $irNetworks = @(docker network ls --format '{{.Name}}')
    if ($LASTEXITCODE -ne 0) { throw 'No pude consultar las redes Docker.' }
    if ($irNetworkName -notin $irNetworks) {
        docker network create $irNetworkName | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'No pude crear la red del ecosistema.' }
    }
    if (-not $irContainer.NetworkSettings.Networks.PSObject.Properties[$irNetworkName]) {
        docker network connect $irNetworkName $irContainerName
        if ($LASTEXITCODE -ne 0) { throw 'No pude conectar PostgreSQL a la red del ecosistema.' }
    }

    if (-not $env:ALLOWED_HOSTS) {
        $irLanAddresses = @(
            Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' } |
                ForEach-Object { $_.IPAddress }
        )
        $irConfiguredHosts = $irComposeConfiguration.services.backend.environment.ALLOWED_HOSTS.Split(',')
        $env:ALLOWED_HOSTS = (($irConfiguredHosts + $irLanAddresses) | Sort-Object -Unique) -join ','
    }

    if (-not $CheckOnly) {
        $irUpArguments = @('up', '-d', '--wait', '--wait-timeout', '180')
        if (-not $SkipBuild) { $irUpArguments += '--build' }
        & docker @irComposeArguments @irUpArguments
        if ($LASTEXITCODE -ne 0) { throw 'No se pudo iniciar el ecosistema. Revisa los logs con docker compose logs.' }
    }

    & docker @irComposeArguments exec -T backend python manage.py check
    if ($LASTEXITCODE -ne 0) { throw 'Django no paso sus comprobaciones.' }
    & docker @irComposeArguments exec -T backend python manage.py check_database
    if ($LASTEXITCODE -ne 0) { throw 'Fallo la verificacion PostgreSQL/PostGIS.' }
    & docker @irComposeArguments exec -T backend python manage.py check_workers
    if ($LASTEXITCODE -ne 0) { throw 'Fallo la tarea de prueba de Celery/Redis.' }
    & docker @irComposeArguments ps
    if ($LASTEXITCODE -ne 0) { throw 'No pude consultar los contenedores.' }
    $irPublishedPort = $irComposeConfiguration.services.backend.ports[0].published
    Write-Host "Ecosistema listo. API en http://127.0.0.1:$irPublishedPort/api."
}
finally {
    foreach ($irName in $irEnvironmentNames) {
        [Environment]::SetEnvironmentVariable($irName, $irPreviousEnvironment[$irName], 'Process')
    }
}
