# =============================================================================
# SETUP-BASE.PS1 — Script de Fundação
# Verifica e prepara o ambiente Windows para instalação de aplicações
# =============================================================================
# USO:
#   irm https://raw.githubusercontent.com/SEU-USUARIO/SEU-REPO/main/setup-base.ps1 | iex
#
# SUBSTITUA antes de publicar no GitHub:
#   [SUBSTITUIR] SEU-USUARIO  → seu usuário do GitHub
#   [SUBSTITUIR] SEU-REPO     → nome do repositório
# =============================================================================

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Garante que scripts locais e remotos assinados possam executar nesta sessão
if ((Get-ExecutionPolicy -Scope Process) -notin @("RemoteSigned","Unrestricted","Bypass")) {
    Set-ExecutionPolicy -Scope Process -ExecutionPolicy RemoteSigned -Force
}

# -----------------------------------------------------------------------------
# CONFIGURAÇÕES GLOBAIS — Ajuste conforme necessário
# -----------------------------------------------------------------------------
$CONFIG = @{
    AppsFolderBase    = "C:\EvoApps"                   # Pasta raiz de todas as apps
    LogFolder         = "C:\EvoApps\logs"              # Pasta de logs
    LogFile           = "C:\EvoApps\logs\setup-base.log"
    MinWindowsBuild   = 19041                           # Windows 10 v2004 mínimo para WSL2
    DockerInstallerUrl = "https://desktop.docker.com/win/main/amd64/Docker%20Desktop%20Installer.exe"
    RequiredPorts     = @(80, 443, 3000, 8080)         # Portas que serão monitoradas
}

# -----------------------------------------------------------------------------
# FUNÇÕES UTILITÁRIAS
# -----------------------------------------------------------------------------

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet("INFO","WARN","ERROR","SUCCESS","STEP")]
        [string]$Level = "INFO"
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logLine   = "[$timestamp] [$Level] $Message"

    # Garante que a pasta de log existe
    if (-not (Test-Path $CONFIG.LogFolder)) {
        New-Item -ItemType Directory -Path $CONFIG.LogFolder -Force | Out-Null
    }

    Add-Content -Path $CONFIG.LogFile -Value $logLine -Encoding UTF8

    # Cores no terminal
    switch ($Level) {
        "INFO"    { Write-Host "  ℹ  $Message" -ForegroundColor Cyan }
        "WARN"    { Write-Host "  ⚠  $Message" -ForegroundColor Yellow }
        "ERROR"   { Write-Host "  ✖  $Message" -ForegroundColor Red }
        "SUCCESS" { Write-Host "  ✔  $Message" -ForegroundColor Green }
        "STEP"    { Write-Host "`n▶  $Message" -ForegroundColor White }
    }
}

function Write-Banner {
    Clear-Host
    Write-Host ""
    Write-Host "  ╔══════════════════════════════════════════════╗" -ForegroundColor DarkCyan
    Write-Host "  ║         EVO APPS — SETUP BASE v1.0           ║" -ForegroundColor DarkCyan
    Write-Host "  ║     Preparando ambiente de instalação        ║" -ForegroundColor DarkCyan
    Write-Host "  ╚══════════════════════════════════════════════╝" -ForegroundColor DarkCyan
    Write-Host ""
}

function Test-Administrator {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal   = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Invoke-Step {
    param(
        [string]$Name,
        [scriptblock]$Action
    )
    Write-Log -Message $Name -Level "STEP"
    try {
        & $Action
    }
    catch {
        Write-Log -Message "Falha em '$Name': $_" -Level "ERROR"
        throw
    }
}

# -----------------------------------------------------------------------------
# ETAPA 0 — Privilégios de Administrador
# -----------------------------------------------------------------------------
function Assert-AdminPrivileges {
    if (-not (Test-Administrator)) {
        Write-Log "Script precisa ser executado como Administrador." -Level "ERROR"
        Write-Host ""
        Write-Host "  Execute o PowerShell como Administrador e tente novamente." -ForegroundColor Yellow
        Write-Host ""
        exit 1
    }
    Write-Log "Rodando com privilégios de Administrador." -Level "SUCCESS"
}

# -----------------------------------------------------------------------------
# ETAPA 1 — Verificar versão do Windows
# -----------------------------------------------------------------------------
function Test-WindowsVersion {
    $build = [System.Environment]::OSVersion.Version.Build
    Write-Log "Windows Build detectado: $build" -Level "INFO"

    if ($build -lt $CONFIG.MinWindowsBuild) {
        Write-Log "Windows Build $build não suporta WSL2. Mínimo: $($CONFIG.MinWindowsBuild)." -Level "ERROR"
        Write-Log "Atualize para Windows 10 v2004 ou superior (ou Windows 11)." -Level "ERROR"
        exit 1
    }
    Write-Log "Versão do Windows compatível (Build $build)." -Level "SUCCESS"
}

# -----------------------------------------------------------------------------
# ETAPA 2 — Verificar/Instalar WSL2
# -----------------------------------------------------------------------------
function Install-WSL2IfNeeded {
    $wslInstalled = Get-Command wsl -ErrorAction SilentlyContinue

    if ($wslInstalled) {
        $wslVersion = wsl --list --verbose 2>&1
        Write-Log "WSL já instalado." -Level "SUCCESS"
        Write-Log "Distribuições: $wslVersion" -Level "INFO"
    }
    else {
        Write-Log "WSL não encontrado. Instalando WSL2..." -Level "WARN"
        wsl --install --no-distribution
        Write-Log "WSL2 instalado. Uma reinicialização pode ser necessária." -Level "SUCCESS"
        $script:NeedsReboot = $true
    }

    # Garantir que o WSL padrão é versão 2
    wsl --set-default-version 2 2>&1 | Out-Null
    Write-Log "WSL padrão definido como versão 2." -Level "SUCCESS"
}

# -----------------------------------------------------------------------------
# ETAPA 3 — Verificar/Instalar Docker Desktop
# -----------------------------------------------------------------------------
function Install-DockerIfNeeded {
    $dockerCmd = Get-Command docker -ErrorAction SilentlyContinue

    if ($dockerCmd) {
        $dockerVersion = docker --version 2>&1
        Write-Log "Docker encontrado: $dockerVersion" -Level "SUCCESS"
        Write-Log "Abra o Docker Desktop antes de executar o script de instalação da aplicação." -Level "INFO"
    }
    else {
        Write-Log "Docker Desktop não encontrado. Baixando instalador..." -Level "WARN"

        $installerPath = "$env:TEMP\DockerDesktopInstaller.exe"
        Write-Log "Download iniciado (pode demorar alguns minutos)..." -Level "INFO"

        Invoke-WebRequest -Uri $CONFIG.DockerInstallerUrl -OutFile $installerPath -UseBasicParsing

        Write-Log "Instalando Docker Desktop (modo silencioso)..." -Level "INFO"
        Start-Process -FilePath $installerPath -ArgumentList "install --quiet" -Wait

        Write-Log "Docker Desktop instalado. Abra-o manualmente antes de instalar as aplicações." -Level "SUCCESS"
        $script:NeedsReboot = $true
    }
}

# -----------------------------------------------------------------------------
# ETAPA 4 — Verificar/Instalar winget
# -----------------------------------------------------------------------------
function Assert-Winget {
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if (-not $winget) {
        Write-Log "winget não encontrado. Verifique a versão do Windows ou instale manualmente via Microsoft Store." -Level "WARN"
    }
    else {
        Write-Log "winget disponível: $(winget --version)" -Level "SUCCESS"
    }
}

# -----------------------------------------------------------------------------
# ETAPA 4.1 — Verificar/Instalar Python
# -----------------------------------------------------------------------------
function Install-PythonIfNeeded {
    $pythonCmd = Get-Command python -ErrorAction SilentlyContinue

    if ($pythonCmd) {
        $pythonVersion = python --version 2>&1
        Write-Log "Python encontrado: $pythonVersion" -Level "SUCCESS"
    }
    else {
        Write-Log "Python não encontrado. Instalando via winget..." -Level "WARN"

        $winget = Get-Command winget -ErrorAction SilentlyContinue
        if (-not $winget) {
            Write-Log "winget não disponível. Instale o Python manualmente: https://www.python.org/downloads/" -Level "ERROR"
            return
        }

        winget install -e --id Python.Python.3 --silent --accept-source-agreements --accept-package-agreements
        
        # Recarrega o PATH da sessão atual
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" +
                    [System.Environment]::GetEnvironmentVariable("Path","User")

        $pythonVersion = python --version 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Log "Python instalado com sucesso: $pythonVersion" -Level "SUCCESS"
        }
        else {
            Write-Log "Python instalado mas requer reinicialização para estar disponível no PATH." -Level "WARN"
            $script:NeedsReboot = $true
        }
    }
}

# -----------------------------------------------------------------------------
# ETAPA 4.2 — Verificar/Instalar Node.js
# -----------------------------------------------------------------------------
function Install-NodeIfNeeded {
    $nodeCmd = Get-Command node -ErrorAction SilentlyContinue

    if ($nodeCmd) {
        $nodeVersion = & node --version 2>&1
        $npmVersion  = & npm.cmd --version 2>&1
        Write-Log "Node.js encontrado: $nodeVersion" -Level "SUCCESS"
        Write-Log "npm encontrado: v$npmVersion" -Level "SUCCESS"
    }
    else {
        Write-Log "Node.js não encontrado. Instalando via winget..." -Level "WARN"

        $winget = Get-Command winget -ErrorAction SilentlyContinue
        if (-not $winget) {
            Write-Log "winget não disponível. Instale o Node.js manualmente: https://nodejs.org/" -Level "ERROR"
            return
        }

        winget install -e --id OpenJS.NodeJS.LTS --silent --accept-source-agreements --accept-package-agreements 2>&1 | Out-Null

        # Recarrega o PATH sem reiniciar
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" +
                    [System.Environment]::GetEnvironmentVariable("Path","User")

        $nodeCheck = Get-Command node -ErrorAction SilentlyContinue
        if ($nodeCheck) {
            $nodeVersion = & node --version 2>&1
            Write-Log "Node.js instalado com sucesso: $nodeVersion" -Level "SUCCESS"
        }
        else {
            Write-Log "Node.js instalado. Será necessário reiniciar para usar." -Level "WARN"
            $script:NeedsReboot = $true
        }
    }
}

# -----------------------------------------------------------------------------
# ETAPA 5 — Criar estrutura de pastas
# -----------------------------------------------------------------------------
function Initialize-FolderStructure {
    $folders = @(
        $CONFIG.AppsFolderBase,
        $CONFIG.LogFolder
    )

    foreach ($folder in $folders) {
        if (-not (Test-Path $folder)) {
            New-Item -ItemType Directory -Path $folder -Force | Out-Null
            Write-Log "Pasta criada: $folder" -Level "SUCCESS"
        }
        else {
            Write-Log "Pasta já existe: $folder" -Level "INFO"
        }
    }
}

# -----------------------------------------------------------------------------
# ETAPA 6 — Escanear portas em uso
# -----------------------------------------------------------------------------
function Get-UsedPorts {
    Write-Log "Escaneando portas em uso..." -Level "INFO"

    $usedPorts = @{}

    # Pega todas as conexões TCP ativas
    $connections = Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue

    foreach ($conn in $connections) {
        $port = $conn.LocalPort
        $pid  = $conn.OwningProcess

        try {
            $proc = Get-Process -Id $pid -ErrorAction SilentlyContinue
            $procName = if ($proc) { $proc.ProcessName } else { "desconhecido" }
        }
        catch { $procName = "desconhecido" }

        $usedPorts[$port] = $procName
    }

    # Salva mapa de portas no arquivo para outros scripts consultarem
    $portsFile = "$($CONFIG.AppsFolderBase)\ports-in-use.json"
    $usedPorts | ConvertTo-Json | Set-Content -Path $portsFile -Encoding UTF8

    Write-Log "Mapa de portas salvo em: $portsFile" -Level "SUCCESS"

    # Log das portas que interessam ao projeto
    foreach ($port in $CONFIG.RequiredPorts) {
        if ($usedPorts.ContainsKey($port)) {
            Write-Log "Porta $port em uso por: $($usedPorts[$port])" -Level "WARN"
        }
        else {
            Write-Log "Porta $port disponível." -Level "SUCCESS"
        }
    }

    return $usedPorts
}

function Find-FreePort {
    param([int]$StartPort = 3000)

    $portsFile = "$($CONFIG.AppsFolderBase)\ports-in-use.json"
    $usedPorts = @{}

    if (Test-Path $portsFile) {
        $usedPorts = Get-Content $portsFile | ConvertFrom-Json -AsHashtable
    }

    $port = $StartPort
    while ($usedPorts.ContainsKey($port)) {
        $port++
    }

    Write-Log "Próxima porta disponível a partir de ${StartPort}: $port" -Level "INFO"
    return $port
}

# -----------------------------------------------------------------------------
# ETAPA 7 — Verificar containers Docker existentes
# -----------------------------------------------------------------------------
function Get-RunningContainers {
    $dockerCmd = Get-Command docker -ErrorAction SilentlyContinue
    if (-not $dockerCmd) { return }

    Write-Log "Containers Docker em execução:" -Level "INFO"
    $containers = docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Ports}}\t{{.Status}}" 2>&1

    if ($containers) {
        $containers | ForEach-Object { Write-Log "  $_" -Level "INFO" }

        # Salva estado atual dos containers
        $containersFile = "$($CONFIG.AppsFolderBase)\containers-running.json"
        docker ps --format "{{json .}}" 2>&1 | Set-Content -Path $containersFile -Encoding UTF8
        Write-Log "Estado dos containers salvo em: $containersFile" -Level "SUCCESS"
    }
    else {
        Write-Log "Nenhum container rodando." -Level "INFO"
    }
}

# -----------------------------------------------------------------------------
# ETAPA 8 — Resumo e resultado
# -----------------------------------------------------------------------------
function Write-Summary {
    param([hashtable]$UsedPorts)

    Write-Host ""
    Write-Host "  ═══════════════════════════════════════════════" -ForegroundColor DarkCyan
    Write-Host "  RESUMO DO AMBIENTE" -ForegroundColor White
    Write-Host "  ═══════════════════════════════════════════════" -ForegroundColor DarkCyan

    $os = Get-CimInstance Win32_OperatingSystem
    Write-Host "  OS        : $($os.Caption) (Build $($os.BuildNumber))" -ForegroundColor Gray
    Write-Host "  RAM Total : $([math]::Round($os.TotalVisibleMemorySize / 1MB, 1)) GB" -ForegroundColor Gray
    Write-Host "  Pasta Base: $($CONFIG.AppsFolderBase)" -ForegroundColor Gray
    Write-Host "  Log       : $($CONFIG.LogFile)" -ForegroundColor Gray

    if ($script:NeedsReboot) {
        Write-Host ""
        Write-Host "  ⚠  REINICIALIZAÇÃO NECESSÁRIA" -ForegroundColor Yellow
        Write-Host "     Após reiniciar, execute o script de instalação da aplicação." -ForegroundColor Yellow
    }
    else {
        Write-Host ""
        Write-Host "  ✔  Ambiente pronto! Execute o script da aplicação desejada." -ForegroundColor Green
    }

    Write-Host "  ═══════════════════════════════════════════════" -ForegroundColor DarkCyan
    Write-Host ""
}

# =============================================================================
# EXECUÇÃO PRINCIPAL
# =============================================================================

$script:NeedsReboot = $false

Write-Banner

Invoke-Step "Verificando privilégios de administrador" { Assert-AdminPrivileges }
Invoke-Step "Verificando versão do Windows"            { Test-WindowsVersion }
Invoke-Step "Criando estrutura de pastas"              { Initialize-FolderStructure }
Invoke-Step "Verificando WSL2"                         { Install-WSL2IfNeeded }
Invoke-Step "Verificando Docker Desktop"               { Install-DockerIfNeeded }
Invoke-Step "Verificando winget"                       { Assert-Winget }
Invoke-Step "Verificando Python"                       { Install-PythonIfNeeded }
Invoke-Step "Verificando Node.js"                      { Install-NodeIfNeeded }
Invoke-Step "Escaneando portas em uso"                 { $ports = Get-UsedPorts }
Invoke-Step "Verificando containers ativos"            { Get-RunningContainers }

Write-Summary -UsedPorts $ports

Write-Log "setup-base.ps1 concluído com sucesso." -Level "SUCCESS"
