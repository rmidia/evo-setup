# =============================================================================
# INSTALL-EVO-CRM.PS1 — Instalação automatizada do Evo CRM Community
# Requer: verification.ps1 (verification.ps1) executado com sucesso antes
# =============================================================================
# USO:
#   irm https://raw.githubusercontent.com/rmidia/evo-setup/main/install-evo-crm.ps1 | iex
# =============================================================================

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Garante execução de scripts nesta sessão
if ((Get-ExecutionPolicy -Scope Process) -notin @("RemoteSigned","Unrestricted","Bypass")) {
    Set-ExecutionPolicy -Scope Process -ExecutionPolicy RemoteSigned -Force
}

# =============================================================================
# ⚙️  CONFIGURAÇÕES — SUBSTITUA ANTES DE PUBLICAR
# =============================================================================

$GEMINI_API_KEY = "AIzaSyBv2eJ3Atp1g9i7I7N9BsIpfQZNGewFfHg"   # 🔑 Obtenha gratuitamente em: aistudio.google.com/apikey

$CONFIG = @{
    # Repositório do Evo CRM
    RepoUrl         = "git@github.com:EvolutionAPI/evo-crm-community.git"
    RepoUrlHttps    = "https://github.com/EvolutionAPI/evo-crm-community.git"

    # Onde será instalado
    InstallPath     = "C:\EvoApps\evo-crm"

    # Log
    LogFolder       = "C:\EvoApps\logs"
    LogFile         = "C:\EvoApps\logs\install-evo-crm.log"

    # Serviços e portas esperadas
    Services        = @(
        @{ Name = "evo-auth-service-community"; Port = 3001; Url = "http://localhost:3001" }
        @{ Name = "evo-ai-crm-community";       Port = 3000; Url = "http://localhost:3000" }
        @{ Name = "evo-ai-frontend-community";  Port = 5173; Url = "http://localhost:5173" }
        @{ Name = "evo-ai-processor-community"; Port = 8000; Url = "http://localhost:8000" }
        @{ Name = "evo-ai-core-service-community"; Port = 5555; Url = "http://localhost:5555" }
    )

    # Health check
    MaxHealthRetries  = 20     # tentativas
    HealthRetryDelay  = 30     # segundos entre tentativas
    SetupTimeoutMin   = 25     # minutos máximos para o make setup

    # IA — Gemini (gratuito via Google AI Studio)
    GeminiModel     = "gemini-1.5-flash"
    GeminiUrl       = "https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent"
}

# =============================================================================
# FUNÇÕES UTILITÁRIAS
# =============================================================================

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet("INFO","WARN","ERROR","SUCCESS","STEP","AI")]
        [string]$Level = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logLine   = "[$timestamp] [$Level] $Message"

    if (-not (Test-Path $CONFIG.LogFolder)) {
        New-Item -ItemType Directory -Path $CONFIG.LogFolder -Force | Out-Null
    }
    Add-Content -Path $CONFIG.LogFile -Value $logLine -Encoding UTF8

    switch ($Level) {
        "INFO"    { Write-Host "  ℹ  $Message" -ForegroundColor Cyan }
        "WARN"    { Write-Host "  ⚠  $Message" -ForegroundColor Yellow }
        "ERROR"   { Write-Host "  ✖  $Message" -ForegroundColor Red }
        "SUCCESS" { Write-Host "  ✔  $Message" -ForegroundColor Green }
        "STEP"    { Write-Host "`n▶  $Message" -ForegroundColor White }
        "AI"      { Write-Host "  🤖 $Message" -ForegroundColor Magenta }
    }
}

function Write-Banner {
    Clear-Host
    Write-Host ""
    Write-Host "  ╔══════════════════════════════════════════════╗" -ForegroundColor DarkGreen
    Write-Host "  ║        EVO CRM — INSTALAÇÃO v1.0             ║" -ForegroundColor DarkGreen
    Write-Host "  ║   Plataforma CRM + IA Self-Hosted            ║" -ForegroundColor DarkGreen
    Write-Host "  ╚══════════════════════════════════════════════╝" -ForegroundColor DarkGreen
    Write-Host ""
}

function Invoke-Step {
    param([string]$Name, [scriptblock]$Action)
    Write-Log -Message $Name -Level "STEP"
    try {
        & $Action
    }
    catch {
        Write-Log "Falha em '$Name': $_" -Level "ERROR"
        throw
    }
}

function Test-Administrator {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal   = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# =============================================================================
# INTEGRAÇÃO COM GEMINI AI (gratuito — aistudio.google.com/apikey)
# =============================================================================

function Invoke-GeminiAI {
    param(
        [string]$Prompt,
        [string]$Context = ""
    )

    if ($GEMINI_API_KEY -eq "SUA-CHAVE-AQUI") {
        Write-Log "Chave da API do Gemini não configurada. Pulando análise de IA." -Level "WARN"
        return $null
    }

    Write-Log "Consultando Gemini AI..." -Level "AI"

    $fullPrompt = @"
Você é um especialista em Docker, Linux e instalação de aplicações self-hosted.
Analise o seguinte problema durante a instalação do Evo CRM Community e responda:
1. Qual é a causa provável do erro?
2. Qual comando ou ação corrige o problema?
3. Responda de forma objetiva e direta, em português.

CONTEXTO DO AMBIENTE:
- Windows com WSL2 e Docker Desktop
- Instalação via PowerShell
- Aplicação: Evo CRM Community (Docker Compose + make)

$Context

ERRO / SITUAÇÃO:
$Prompt
"@

    $body = @{
        contents = @(
            @{
                parts = @(
                    @{ text = $fullPrompt }
                )
            }
        )
    } | ConvertTo-Json -Depth 5

    try {
        # Aguarda 2s para respeitar limite de RPM do plano gratuito
        Start-Sleep -Seconds 2

        $response = Invoke-RestMethod `
            -Uri     "$($CONFIG.GeminiUrl)?key=$GEMINI_API_KEY" `
            -Method  POST `
            -Headers @{ "Content-Type" = "application/json" } `
            -Body    $body

        $answer = $response.candidates[0].content.parts[0].text

        Write-Log "Gemini AI respondeu:" -Level "AI"
        Write-Host ""
        Write-Host $answer -ForegroundColor Magenta
        Write-Host ""
        Write-Log $answer -Level "AI"
        return $answer
    }
    catch {
        Write-Log "Erro ao consultar Gemini AI: $_" -Level "WARN"
        return $null
    }
}

# =============================================================================
# ETAPA 1 — Verificar pré-requisitos
# =============================================================================

function Assert-Prerequisites {
    # Admin
    if (-not (Test-Administrator)) {
        Write-Log "Execute como Administrador." -Level "ERROR"
        exit 1
    }
    Write-Log "Rodando como Administrador." -Level "SUCCESS"

    # Docker
    $docker = Get-Command docker -ErrorAction SilentlyContinue
    if (-not $docker) {
        Write-Log "Docker não encontrado. Execute verification.ps1 primeiro." -Level "ERROR"
        exit 1
    }

    # Verifica se Docker Desktop está aberto
    $dockerInfo = docker info 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Log "Docker não está rodando. Abrindo Docker Desktop..." -Level "WARN"

        $dockerPaths = @(
            "C:\Program Files\Docker\Docker\Docker Desktop.exe",
            "$env:LOCALAPPDATA\Docker\Docker Desktop.exe"
        )
        foreach ($path in $dockerPaths) {
            if (Test-Path $path) {
                Start-Process $path
                Write-Log "Aguardando Docker iniciar (máx 90s)..." -Level "INFO"
                break
            }
        }

        $ready = $false
        for ($i = 1; $i -le 9; $i++) {
            Start-Sleep -Seconds 10
            $dockerInfo = docker info 2>&1
            if ($LASTEXITCODE -eq 0) { $ready = $true; break }
            Write-Log "Tentativa $i/9 — aguardando Docker..." -Level "INFO"
        }

        if (-not $ready) {
            Write-Log "Docker não respondeu. Abra o Docker Desktop manualmente e re-execute." -Level "ERROR"
            exit 1
        }
    }
    Write-Log "Docker está rodando." -Level "SUCCESS"

    # Git
    $git = Get-Command git -ErrorAction SilentlyContinue
    if (-not $git) {
        Write-Log "Git não encontrado. Instalando via winget..." -Level "WARN"
        winget install -e --id Git.Git --silent --accept-source-agreements --accept-package-agreements 2>&1 | Out-Null
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" +
                    [System.Environment]::GetEnvironmentVariable("Path","User")
        Write-Log "Git instalado." -Level "SUCCESS"
    } else {
        Write-Log "Git encontrado: $(git --version)" -Level "SUCCESS"
    }

    # make — via winget (GnuWin32) ou choco
    $make = Get-Command make -ErrorAction SilentlyContinue
    if (-not $make) {
        Write-Log "make não encontrado. Instalando via winget..." -Level "WARN"

        # Tenta via winget
        winget install -e --id GnuWin32.Make --silent --accept-source-agreements --accept-package-agreements 2>&1 | Out-Null

        # Adiciona ao PATH se instalou no local padrão
        $makePath = "C:\Program Files (x86)\GnuWin32\bin"
        if (Test-Path "$makePath\make.exe") {
            $env:Path += ";$makePath"
            # Persiste no PATH do usuário
            $userPath = [System.Environment]::GetEnvironmentVariable("Path","User")
            [System.Environment]::SetEnvironmentVariable("Path", "$userPath;$makePath", "User")
            Write-Log "make instalado e adicionado ao PATH." -Level "SUCCESS"
        } else {
            Write-Log "make não encontrado após instalação. Tentando via Chocolatey..." -Level "WARN"

            $choco = Get-Command choco -ErrorAction SilentlyContinue
            if (-not $choco) {
                # Instala Chocolatey
                Set-ExecutionPolicy Bypass -Scope Process -Force
                [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
                Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
                $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" +
                            [System.Environment]::GetEnvironmentVariable("Path","User")
            }
            choco install make -y 2>&1 | Out-Null
            $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" +
                        [System.Environment]::GetEnvironmentVariable("Path","User")

            $make = Get-Command make -ErrorAction SilentlyContinue
            if ($make) {
                Write-Log "make instalado via Chocolatey." -Level "SUCCESS"
            } else {
                $aiSuggestion = Invoke-GeminiAI -Prompt "O comando 'make' não foi encontrado após tentar instalar via winget e Chocolatey no Windows. Como resolver para usar Makefile com Docker Compose no Windows?"
                Write-Log "Não foi possível instalar o make automaticamente. Veja a sugestão da IA acima." -Level "ERROR"
                exit 1
            }
        }
    } else {
        Write-Log "make encontrado." -Level "SUCCESS"
    }
}

# =============================================================================
# ETAPA 2 — Escanear portas e containers existentes
# =============================================================================

function Get-EnvironmentSnapshot {
    Write-Log "Verificando portas em uso..." -Level "INFO"

    $usedPorts = @{}
    $connections = Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue
    foreach ($conn in $connections) {
        $proc = Get-Process -Id $conn.OwningProcess -ErrorAction SilentlyContinue
        $usedPorts[$conn.LocalPort] = if ($proc) { $proc.ProcessName } else { "desconhecido" }
    }

    foreach ($svc in $CONFIG.Services) {
        if ($usedPorts.ContainsKey($svc.Port)) {
            Write-Log "Porta $($svc.Port) já em uso por: $($usedPorts[$svc.Port])" -Level "WARN"
        } else {
            Write-Log "Porta $($svc.Port) disponível." -Level "SUCCESS"
        }
    }

    Write-Log "Containers Docker em execução:" -Level "INFO"
    $containers = docker ps --format "  {{.Names}} | {{.Image}} | {{.Ports}}" 2>&1
    if ($containers) {
        $containers | ForEach-Object { Write-Log $_ -Level "INFO" }
    } else {
        Write-Log "Nenhum container rodando no momento." -Level "INFO"
    }
}

# =============================================================================
# ETAPA 3 — Clonar repositório
# =============================================================================

function Invoke-CloneRepo {
    if (Test-Path "$($CONFIG.InstallPath)\.git") {
        Write-Log "Repositório já existe em $($CONFIG.InstallPath). Atualizando..." -Level "INFO"
        Set-Location $CONFIG.InstallPath
        git submodule update --remote --merge 2>&1 | ForEach-Object { Write-Log $_ -Level "INFO" }
        Write-Log "Repositório atualizado." -Level "SUCCESS"
        return
    }

    # Garante pasta pai
    $parent = Split-Path $CONFIG.InstallPath -Parent
    if (-not (Test-Path $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    Set-Location $parent

    Write-Log "Clonando repositório (com submódulos)..." -Level "INFO"

    # Tenta SSH primeiro, cai para HTTPS se falhar
    git clone --recurse-submodules $CONFIG.RepoUrl 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Log "Clone via SSH falhou. Tentando HTTPS..." -Level "WARN"
        git clone --recurse-submodules $CONFIG.RepoUrlHttps 2>&1
        if ($LASTEXITCODE -ne 0) {
            $logs = git clone --recurse-submodules $CONFIG.RepoUrlHttps 2>&1 | Out-String
            Invoke-GeminiAI -Prompt "Erro ao clonar repositório do Evo CRM:" -Context $logs
            Write-Log "Falha ao clonar. Veja a sugestão da IA acima." -Level "ERROR"
            exit 1
        }
    }

    Set-Location $CONFIG.InstallPath
    Write-Log "Repositório clonado em: $($CONFIG.InstallPath)" -Level "SUCCESS"
}

# =============================================================================
# ETAPA 4 — Configurar .env
# =============================================================================

function Initialize-EnvFile {
    Set-Location $CONFIG.InstallPath

    if (-not (Test-Path ".env")) {
        if (Test-Path ".env.example") {
            Copy-Item ".env.example" ".env"
            Write-Log ".env criado a partir do .env.example." -Level "SUCCESS"
        } else {
            Write-Log ".env.example não encontrado!" -Level "ERROR"
            Invoke-GeminiAI -Prompt "O arquivo .env.example não foi encontrado no repositório do Evo CRM Community após o clone. O que pode ter dado errado e como resolver?"
            exit 1
        }
    } else {
        Write-Log ".env já existe, mantendo configurações atuais." -Level "INFO"
    }

    # Usando Opção A (Docker) — valores padrão já funcionam
    Write-Log "Banco de dados: Docker interno (Opção A — padrão)." -Level "INFO"
    Write-Log ".env configurado. Nenhuma alteração necessária para o banco." -Level "SUCCESS"
}

# =============================================================================
# ETAPA 5 — Executar make setup
# =============================================================================

function Invoke-MakeSetup {
    Set-Location $CONFIG.InstallPath

    Write-Log "Iniciando 'make setup' (pode levar 15-20 min na primeira vez)..." -Level "INFO"
    Write-Log "Acompanhe o progresso abaixo:" -Level "INFO"
    Write-Host ""

    $timeoutSeconds = $CONFIG.SetupTimeoutMin * 60
    $startTime      = Get-Date

    # Executa make setup capturando saída em tempo real
    $setupLog  = @()
    $errorLog  = @()
    $success   = $false

    $process = Start-Process `
        -FilePath "make" `
        -ArgumentList "setup" `
        -WorkingDirectory $CONFIG.InstallPath `
        -PassThru `
        -NoNewWindow `
        -RedirectStandardOutput "$($CONFIG.LogFolder)\make-setup-stdout.log" `
        -RedirectStandardError  "$($CONFIG.LogFolder)\make-setup-stderr.log"

    # Monitora o processo com timeout
    while (-not $process.HasExited) {
        $elapsed = (Get-Date) - $startTime

        if ($elapsed.TotalSeconds -gt $timeoutSeconds) {
            Write-Log "Timeout de $($CONFIG.SetupTimeoutMin) minutos atingido." -Level "WARN"
            $process.Kill()
            break
        }

        # Mostra últimas linhas do log em tempo real
        if (Test-Path "$($CONFIG.LogFolder)\make-setup-stdout.log") {
            $lastLines = Get-Content "$($CONFIG.LogFolder)\make-setup-stdout.log" -Tail 3 -ErrorAction SilentlyContinue
            if ($lastLines) {
                $lastLines | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }
            }
        }

        Start-Sleep -Seconds 5
    }

    $exitCode = $process.ExitCode

    if ($exitCode -eq 0) {
        Write-Log "make setup concluído com sucesso!" -Level "SUCCESS"
        $success = $true
    } else {
        Write-Log "make setup terminou com erro (código $exitCode)." -Level "WARN"

        # Coleta logs de erro para análise da IA
        $stdErr = ""
        if (Test-Path "$($CONFIG.LogFolder)\make-setup-stderr.log") {
            $stdErr = Get-Content "$($CONFIG.LogFolder)\make-setup-stderr.log" -Raw -ErrorAction SilentlyContinue
        }
        $stdOut = ""
        if (Test-Path "$($CONFIG.LogFolder)\make-setup-stdout.log") {
            $stdOut = Get-Content "$($CONFIG.LogFolder)\make-setup-stdout.log" -Tail 50 -ErrorAction SilentlyContinue | Out-String
        }

        $context = "STDOUT (últimas 50 linhas):`n$stdOut`n`nSTDERR:`n$stdErr"
        $aiResponse = Invoke-GeminiAI -Prompt "O comando 'make setup' do Evo CRM falhou com código de saída $exitCode." -Context $context

        if ($aiResponse) {
            Write-Host ""
            Write-Log "Deseja tentar novamente após aplicar a sugestão? (S/N)" -Level "INFO"
            $retry = Read-Host "Resposta"
            if ($retry -eq "S" -or $retry -eq "s") {
                Write-Log "Tentando 'make setup' novamente..." -Level "INFO"
                Invoke-MakeSetup
                return
            }
        }

        Write-Log "Instalação interrompida. Verifique os logs em: $($CONFIG.LogFolder)" -Level "ERROR"
        exit 1
    }
}

# =============================================================================
# ETAPA 6 — Health check: aguardar todos os serviços subirem
# =============================================================================

function Wait-ServicesReady {
    Write-Log "Aguardando serviços ficarem disponíveis..." -Level "INFO"
    Write-Log "Isso pode levar alguns minutos após o setup." -Level "INFO"

    $allReady    = $false
    $attempt     = 0
    $failedSvcs  = @()

    while ($attempt -lt $CONFIG.MaxHealthRetries -and -not $allReady) {
        $attempt++
        $failedSvcs = @()

        foreach ($svc in $CONFIG.Services) {
            try {
                $response = Invoke-WebRequest -Uri $svc.Url -UseBasicParsing -TimeoutSec 5 -ErrorAction SilentlyContinue
                if ($response.StatusCode -lt 500) {
                    Write-Log "$($svc.Name) → OK ($($svc.Url))" -Level "SUCCESS"
                } else {
                    $failedSvcs += $svc
                    Write-Log "$($svc.Name) → HTTP $($response.StatusCode)" -Level "WARN"
                }
            }
            catch {
                $failedSvcs += $svc
                Write-Log "$($svc.Name) → não respondeu ainda..." -Level "INFO"
            }
        }

        if ($failedSvcs.Count -eq 0) {
            $allReady = $true
        } else {
            if ($attempt -lt $CONFIG.MaxHealthRetries) {
                Write-Log "Tentativa $attempt/$($CONFIG.MaxHealthRetries) — $($failedSvcs.Count) serviço(s) ainda subindo. Aguardando $($CONFIG.HealthRetryDelay)s..." -Level "INFO"
                Start-Sleep -Seconds $CONFIG.HealthRetryDelay
            }
        }
    }

    if (-not $allReady) {
        # Coleta logs dos containers com falha para análise da IA
        foreach ($svc in $failedSvcs) {
            Write-Log "Coletando logs do serviço: $($svc.Name)" -Level "WARN"
            $containerLogs = docker logs $svc.Name 2>&1 | Select-Object -Last 30 | Out-String
            Invoke-GeminiAI `
                -Prompt "O serviço '$($svc.Name)' não ficou disponível em $($svc.Url) após $($CONFIG.MaxHealthRetries) tentativas." `
                -Context "Logs do container:`n$containerLogs"
        }
        Write-Log "Nem todos os serviços responderam. Verifique as sugestões da IA acima." -Level "WARN"
    }

    return $allReady
}

# =============================================================================
# ETAPA 7 — Resumo final
# =============================================================================

function Write-FinalSummary {
    param([bool]$AllReady)

    Write-Host ""
    Write-Host "  ═══════════════════════════════════════════════════" -ForegroundColor DarkGreen
    Write-Host "  EVO CRM — RESULTADO DA INSTALAÇÃO" -ForegroundColor White
    Write-Host "  ═══════════════════════════════════════════════════" -ForegroundColor DarkGreen
    Write-Host ""

    if ($AllReady) {
        Write-Host "  ✔  Todos os serviços estão rodando!" -ForegroundColor Green
        Write-Host ""
        Write-Host "  Acesse agora:" -ForegroundColor White
        Write-Host "  → Frontend  : http://localhost:5173" -ForegroundColor Cyan
        Write-Host "  → CRM API   : http://localhost:3000" -ForegroundColor Cyan
        Write-Host "  → Auth API  : http://localhost:3001" -ForegroundColor Cyan
        Write-Host "  → Processor : http://localhost:8000" -ForegroundColor Cyan
        Write-Host "  → Core API  : http://localhost:5555" -ForegroundColor Cyan
        Write-Host "  → Mailhog   : http://localhost:8025" -ForegroundColor Cyan
    } else {
        Write-Host "  ⚠  Instalação concluída com alertas." -ForegroundColor Yellow
        Write-Host "     Alguns serviços podem ainda estar iniciando." -ForegroundColor Yellow
        Write-Host "     Aguarde alguns minutos e acesse: http://localhost:5173" -ForegroundColor Yellow
    }

    Write-Host ""
    Write-Host "  Comandos úteis (execute na pasta $($CONFIG.InstallPath)):" -ForegroundColor White
    Write-Host "  make start    — liga todos os serviços" -ForegroundColor Gray
    Write-Host "  make stop     — desliga todos os serviços" -ForegroundColor Gray
    Write-Host "  make logs     — exibe logs em tempo real" -ForegroundColor Gray
    Write-Host "  make status   — mostra containers rodando" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  Log completo: $($CONFIG.LogFile)" -ForegroundColor DarkGray
    Write-Host "  ═══════════════════════════════════════════════════" -ForegroundColor DarkGreen
    Write-Host ""
}

# =============================================================================
# EXECUÇÃO PRINCIPAL
# =============================================================================

Write-Banner

Invoke-Step "Verificando pré-requisitos"              { Assert-Prerequisites }
Invoke-Step "Escaneando ambiente (portas/containers)" { Get-EnvironmentSnapshot }
Invoke-Step "Clonando repositório do Evo CRM"         { Invoke-CloneRepo }
Invoke-Step "Configurando arquivo .env"               { Initialize-EnvFile }
Invoke-Step "Executando make setup"                   { Invoke-MakeSetup }

$ready = $false
Invoke-Step "Verificando saúde dos serviços"          { $script:ready = Wait-ServicesReady }

Write-FinalSummary -AllReady $script:ready

Write-Log "install-evo-crm.ps1 finalizado." -Level "SUCCESS"
