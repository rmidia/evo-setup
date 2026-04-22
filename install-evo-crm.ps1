# =============================================================================
# INSTALL-EVO-CRM.PS1 — Instalação automatizada do Evo CRM Community
# Requer: setup-base.ps1 (verification.ps1) executado com sucesso antes
# =============================================================================
# USO:
#   irm https://raw.githubusercontent.com/SEU-USUARIO/SEU-REPO/main/install-evo-crm.ps1 | iex
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

$GEMINI_API_KEY = "SUA-CHAVE-AQUI"   # 🔑 Obtenha gratuitamente em: aistudio.google.com/apikey

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

    # IA — Retry loop
    MaxAIRetries    = 4        # tentativas com assistência da IA antes de perguntar ao usuário
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
    param(
        [string]$Name,
        [scriptblock]$Action,
        [switch]$AllowRetry
    )
    Write-Log -Message $Name -Level "STEP"
    $attempt = 0
    $maxAttempts = if ($AllowRetry) { 3 } else { 1 }

    while ($attempt -lt $maxAttempts) {
        $attempt++
        try {
            & $Action
            return   # sucesso — sai do loop
        }
        catch {
            $errMsg = "$_"
            Write-Log "Falha em '$Name': $errMsg" -Level "ERROR"

            # Chama IA para diagnosticar
            $aiResponse = Invoke-GeminiAI `
                -Prompt "Erro durante a etapa '$Name' da instalação do Evo CRM." `
                -Context "Mensagem de erro:`n$errMsg"

            if ($attempt -lt $maxAttempts) {
                Write-Host ""
                Write-Host "  Deseja tentar esta etapa novamente? (S/N)" -ForegroundColor Yellow
                $retry = Read-Host "  Resposta"
                if ($retry -ne "S" -and $retry -ne "s") { break }
                Write-Log "Tentando novamente ($attempt/$maxAttempts)..." -Level "INFO"
            } else {
                Write-Log "Número máximo de tentativas atingido para '$Name'." -Level "ERROR"
                exit 1
            }
        }
    }
}

function Test-Administrator {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal   = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# =============================================================================
# INTEGRAÇÃO COM GEMINI AI — FIX 3
# Agora com loop de retries assistido por IA, com limite e saída controlada
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
        Write-Host "  ╔══════════════════════════════════════════════════╗" -ForegroundColor Magenta
        Write-Host "  ║  🤖 ANÁLISE DA IA                                ║" -ForegroundColor Magenta
        Write-Host "  ╠══════════════════════════════════════════════════╣" -ForegroundColor Magenta
        # Exibe a resposta linha a linha com indentação
        $answer -split "`n" | ForEach-Object {
            Write-Host "  $($_)" -ForegroundColor White
        }
        Write-Host "  ╚══════════════════════════════════════════════════╝" -ForegroundColor Magenta
        Write-Host ""
        Write-Log $answer -Level "AI"
        return $answer
    }
    catch {
        Write-Log "Erro ao consultar Gemini AI: $_" -Level "WARN"
        return $null
    }
}

# ── Nova função: executa um bloco com retries assistidos pela IA ──────────────
# Tenta até $CONFIG.MaxAIRetries vezes, consultando a IA a cada falha.
# Após esgotar as tentativas, pergunta ao usuário se quer parar ou tentar algo diferente.
function Invoke-WithAIRetry {
    param(
        [string]$StepName,
        [scriptblock]$Action,
        [string]$ErrorContext = ""   # contexto extra para a IA (logs, etc.)
    )

    $attempt    = 0
    $maxRetries = $CONFIG.MaxAIRetries

    while ($true) {
        $attempt++
        Write-Log "Tentativa $attempt/$maxRetries — $StepName" -Level "INFO"

        try {
            & $Action
            Write-Log "$StepName concluído com sucesso na tentativa $attempt." -Level "SUCCESS"
            return $true
        }
        catch {
            $errMsg = "$_"
            Write-Log "Tentativa $attempt falhou: $errMsg" -Level "WARN"

            # Coleta contexto dinâmico se disponível
            $ctx = $ErrorContext
            if ($ctx -eq "") { $ctx = "Mensagem de erro:`n$errMsg" }
            else              { $ctx = "$ctx`n`nMensagem de erro:`n$errMsg" }

            # Consulta a IA
            $aiResponse = Invoke-GeminiAI `
                -Prompt "Falha na etapa '$StepName' — tentativa $attempt/$maxRetries." `
                -Context $ctx

            # Verifica se esgotou as tentativas
            if ($attempt -ge $maxRetries) {
                Write-Host ""
                Write-Host "  ╔══════════════════════════════════════════════════╗" -ForegroundColor Red
                Write-Host "  ║  ✖  Número máximo de tentativas atingido         ║" -ForegroundColor Red
                Write-Host "  ║     A etapa '$StepName' falhou $maxRetries vezes.  " -ForegroundColor Red
                Write-Host "  ╠══════════════════════════════════════════════════╣" -ForegroundColor Red
                Write-Host "  ║  O que deseja fazer?                             ║" -ForegroundColor Yellow
                Write-Host "  ║  [1] Parar a instalação                          ║" -ForegroundColor Yellow
                Write-Host "  ║  [2] Tentar mais $maxRetries vezes com IA         ║" -ForegroundColor Yellow
                Write-Host "  ║  [3] Pular esta etapa e continuar                ║" -ForegroundColor Yellow
                Write-Host "  ╚══════════════════════════════════════════════════╝" -ForegroundColor Red
                Write-Host ""
                $choice = Read-Host "  Escolha (1/2/3)"

                switch ($choice) {
                    "1" {
                        Write-Log "Instalação interrompida pelo usuário após $attempt falhas em '$StepName'." -Level "ERROR"
                        Write-Host ""
                        Write-Host "  Instalação encerrada. Logs em: $($CONFIG.LogFile)" -ForegroundColor Gray
                        Write-Host "  Pressione qualquer tecla para sair..." -ForegroundColor Gray
                        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
                        exit 1
                    }
                    "2" {
                        Write-Log "Reiniciando contador de tentativas para '$StepName'..." -Level "INFO"
                        $attempt = 0   # zera — dá mais $maxRetries tentativas
                    }
                    "3" {
                        Write-Log "Etapa '$StepName' ignorada pelo usuário." -Level "WARN"
                        return $false
                    }
                    default {
                        Write-Log "Opção inválida. Parando instalação." -Level "ERROR"
                        exit 1
                    }
                }
            } else {
                # Ainda há tentativas — pergunta se quer tentar agora ou aguardar
                Write-Host "  Aplicou a sugestão da IA? Deseja tentar novamente? (S/N)" -ForegroundColor Yellow
                $retry = Read-Host "  Resposta"
                if ($retry -ne "S" -and $retry -ne "s") {
                    Write-Log "Usuário optou por não tentar novamente. Encerrando '$StepName'." -Level "WARN"
                    return $false
                }
            }
        }
    }
}

# =============================================================================
# ETAPA 1 — Verificar pré-requisitos — FIX 1 (Docker auto-start)
# =============================================================================

function Assert-Prerequisites {
    # Admin
    if (-not (Test-Administrator)) {
        Write-Log "Execute como Administrador." -Level "ERROR"
        exit 1
    }
    Write-Log "Rodando como Administrador." -Level "SUCCESS"

    # Docker binário
    $docker = Get-Command docker -ErrorAction SilentlyContinue
    if (-not $docker) {
        Write-Log "Docker não encontrado. Execute verification.ps1 primeiro." -Level "ERROR"
        exit 1
    }

    # ── FIX 1: Tenta abrir Docker Desktop automaticamente se não estiver rodando ──
    $dockerInfo = docker info 2>&1
    if ($LASTEXITCODE -ne 0) {

        Write-Log "Docker daemon não está respondendo. Tentando abrir o Docker Desktop..." -Level "WARN"

        # Caminhos comuns de instalação do Docker Desktop
        $dockerDesktopPaths = @(
            "$env:ProgramFiles\Docker\Docker\Docker Desktop.exe",
            "${env:ProgramFiles(x86)}\Docker\Docker\Docker Desktop.exe",
            "$env:LOCALAPPDATA\Programs\Docker\Docker\Docker Desktop.exe"
        )

        $launched = $false
        foreach ($path in $dockerDesktopPaths) {
            if (Test-Path $path) {
                Write-Log "Abrindo Docker Desktop em: $path" -Level "INFO"
                Start-Process $path
                $launched = $true
                break
            }
        }

        if ($launched) {
            Write-Log "Docker Desktop iniciado. Aguardando daemon ficar pronto (até 3 minutos)..." -Level "INFO"
            Write-Host ""
            Write-Host "  ⏳  Aguarde enquanto o Docker Desktop inicia..." -ForegroundColor Cyan
            Write-Host ""
        } else {
            Write-Log "Não foi possível encontrar o executável do Docker Desktop para iniciar automaticamente." -Level "WARN"
        }

        # Aguarda até 3 minutos pelo daemon (36 x 5s)
        $ready   = $false
        $maxWait = 36
        for ($i = 1; $i -le $maxWait; $i++) {
            Start-Sleep -Seconds 5
            $testInfo = docker info 2>&1
            if ($LASTEXITCODE -eq 0) { $ready = $true; break }
            Write-Host "  ⏳  Aguardando Docker... ($($i * 5)s / 180s)" -ForegroundColor DarkGray
        }

        # Se ainda não subiu, pede ao usuário para abrir manualmente — NÃO fecha o PowerShell
        if (-not $ready) {
            Write-Host ""
            Write-Host "  ╔══════════════════════════════════════════════════════╗" -ForegroundColor Yellow
            Write-Host "  ║  Docker Desktop não iniciou automaticamente.         ║" -ForegroundColor Yellow
            Write-Host "  ║                                                      ║" -ForegroundColor Yellow
            Write-Host "  ║  Por favor, abra o Docker Desktop manualmente:       ║" -ForegroundColor Yellow
            Write-Host "  ║  1. Localize o ícone do Docker Desktop               ║" -ForegroundColor Yellow
            Write-Host "  ║  2. Aguarde o ícone ficar estável na barra de tarefas║" -ForegroundColor Yellow
            Write-Host "  ║  3. Pressione ENTER aqui para continuar              ║" -ForegroundColor Yellow
            Write-Host "  ╚══════════════════════════════════════════════════════╝" -ForegroundColor Yellow
            Write-Host ""

            # Loop: fica esperando até o Docker subir — nunca fecha o PowerShell
            do {
                Read-Host "  Pressione ENTER quando o Docker Desktop estiver aberto e pronto"

                Write-Log "Verificando Docker após confirmação do usuário..." -Level "INFO"
                $maxWait2 = 18   # mais 90s após o ENTER
                for ($i = 1; $i -le $maxWait2; $i++) {
                    $testInfo = docker info 2>&1
                    if ($LASTEXITCODE -eq 0) { $ready = $true; break }
                    Write-Host "  ⏳  Verificando... ($i/$maxWait2)" -ForegroundColor DarkGray
                    Start-Sleep -Seconds 5
                }

                if (-not $ready) {
                    Write-Host ""
                    Write-Host "  Docker ainda não respondeu." -ForegroundColor Red
                    Write-Host "  Verifique se o Docker Desktop está completamente iniciado e tente novamente." -ForegroundColor Yellow
                    Write-Host ""
                }
            } while (-not $ready)
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
    # Só é chamado após Assert-Prerequisites — Docker já está garantidamente aberto
    Write-Log "Verificando portas em uso..." -Level "INFO"

    $usedPorts = @{}
    $connections = Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue
    foreach ($conn in $connections) {
        $proc = Get-Process -Id $conn.OwningProcess -ErrorAction SilentlyContinue
        $usedPorts[$conn.LocalPort] = if ($proc) { $proc.ProcessName } else { "desconhecido" }
    }

    foreach ($svc in $CONFIG.Services) {
        if ($usedPorts.ContainsKey($svc.Port)) {
            Write-Log "Porta $($svc.Port) ja em uso por: $($usedPorts[$svc.Port])" -Level "WARN"
        } else {
            Write-Log "Porta $($svc.Port) disponivel." -Level "SUCCESS"
        }
    }

    Write-Log "Containers Docker em execucao:" -Level "INFO"
    $containers = docker ps --format "  {{.Names}} | {{.Image}} | {{.Ports}}" 2>$null
    if ($LASTEXITCODE -eq 0 -and $containers) {
        $containers | ForEach-Object { Write-Log $_ -Level "INFO" }
    } else {
        Write-Log "Nenhum container rodando no momento." -Level "INFO"
    }
}

# =============================================================================
# ETAPA 3 — Clonar repositório — FIX 2 (SSH flow corrigido)
# =============================================================================

function Invoke-SetupSSHKey {
    Write-Host ""
    Write-Log "Configurando chave SSH para acesso ao GitHub..." -Level "INFO"

    $sshDir     = "$env:USERPROFILE\.ssh"
    $keyPath    = "$sshDir\id_evo_crm"
    $pubKeyPath = "$keyPath.pub"

    # Cria pasta .ssh se não existir
    if (-not (Test-Path $sshDir)) {
        New-Item -ItemType Directory -Path $sshDir -Force | Out-Null
    }

    # Gera chave se não existir
    if (-not (Test-Path $pubKeyPath)) {
        Write-Log "Gerando par de chaves SSH..." -Level "INFO"
        $email = Read-Host "  Digite seu e-mail (usado para identificar a chave no GitHub)"
        ssh-keygen -t ed25519 -C $email -f $keyPath -N '""' 2>&1 | Out-Null
        Write-Log "Chave SSH gerada em: $keyPath" -Level "SUCCESS"
    } else {
        Write-Log "Chave SSH já existe em: $keyPath" -Level "INFO"
    }

    # Garante que o ssh-agent está rodando e adiciona a chave
    try {
        $agentService = Get-Service -Name "ssh-agent" -ErrorAction SilentlyContinue
        if ($agentService -and $agentService.Status -ne "Running") {
            Start-Service ssh-agent -ErrorAction SilentlyContinue
        }
    } catch { }
    ssh-add $keyPath 2>&1 | Out-Null

    # Exibe a chave pública
    $pubKey = Get-Content $pubKeyPath -Raw
    Write-Host ""
    Write-Host "  ╔══════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "  ║           SUA CHAVE SSH PÚBLICA                         ║" -ForegroundColor Cyan
    Write-Host "  ╠══════════════════════════════════════════════════════════╣" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  $pubKey" -ForegroundColor White
    Write-Host "  ╠══════════════════════════════════════════════════════════╣" -ForegroundColor Cyan
    Write-Host "  ║  Como adicionar no GitHub:                              ║" -ForegroundColor Cyan
    Write-Host "  ║  1. Acesse: github.com/settings/keys                   ║" -ForegroundColor Cyan
    Write-Host "  ║  2. Clique em 'New SSH key'                            ║" -ForegroundColor Cyan
    Write-Host "  ║  3. Cole a chave acima no campo 'Key'                  ║" -ForegroundColor Cyan
    Write-Host "  ║  4. Clique em 'Add SSH key'                            ║" -ForegroundColor Cyan
    Write-Host "  ╚══════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""

    # Copia para a área de transferência automaticamente
    try { $pubKey | Set-Clipboard } catch { }
    Write-Log "Chave copiada para a área de transferência (se disponível)." -Level "INFO"

    # ── FIX 2: Loop — fica tentando até SSH funcionar ou usuário desistir ────
    $sshReady = $false
    do {
        # Pergunta se o usuário já adicionou a chave
        Write-Host "  Você já adicionou a chave SSH no GitHub? (S/N)" -ForegroundColor Yellow
        $added = Read-Host "  Resposta"

        if ($added -ne "S" -and $added -ne "s") {
            Write-Host ""
            Write-Host "  Adicione a chave e pressione ENTER para continuar." -ForegroundColor Yellow
            Read-Host "  Pressione ENTER quando estiver pronto"
        }

        # Testa a conexão SSH com GitHub
        Write-Log "Testando conexão SSH com GitHub..." -Level "INFO"
        $sshTest = ssh -T git@github.com -o StrictHostKeyChecking=no 2>&1
        $sshStr  = $sshTest | Out-String

        if ($sshStr -match "successfully authenticated") {
            Write-Log "Conexão SSH com GitHub estabelecida com sucesso!" -Level "SUCCESS"
            $sshReady = $true
        } else {
            Write-Host ""
            Write-Host "  ╔══════════════════════════════════════════════════╗" -ForegroundColor Yellow
            Write-Host "  ║  ⚠  Conexão SSH ainda não funcionou.             ║" -ForegroundColor Yellow
            Write-Host "  ║  Certifique-se de que:                           ║" -ForegroundColor Yellow
            Write-Host "  ║  • Copiou a chave COMPLETA no GitHub             ║" -ForegroundColor Yellow
            Write-Host "  ║  • Salvou com 'Add SSH key'                      ║" -ForegroundColor Yellow
            Write-Host "  ║  • Está usando a conta correta do GitHub         ║" -ForegroundColor Yellow
            Write-Host "  ╚══════════════════════════════════════════════════╝" -ForegroundColor Yellow
            Write-Host ""

            Write-Host "  Deseja tentar novamente? (S) ou Cancelar (N)" -ForegroundColor Yellow
            $tryAgain = Read-Host "  Resposta"
            if ($tryAgain -ne "S" -and $tryAgain -ne "s") {
                Write-Log "Usuário cancelou configuração SSH." -Level "WARN"
                return $false
            }
        }
    } while (-not $sshReady)

    return $true
}

function Invoke-CloneRepo {
    if (Test-Path "$($CONFIG.InstallPath)\.git") {
        Write-Log "Repositório já existe em $($CONFIG.InstallPath). Atualizando..." -Level "INFO"
        Set-Location $CONFIG.InstallPath
        $proc = Start-Process "git" -ArgumentList "submodule update --remote --merge" `
            -WorkingDirectory $CONFIG.InstallPath -Wait -PassThru -NoNewWindow
        Write-Log "Repositório atualizado." -Level "SUCCESS"
        return
    }

    # Garante pasta pai
    $parent = Split-Path $CONFIG.InstallPath -Parent
    if (-not (Test-Path $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    $gitLog = "$($CONFIG.LogFolder)\git-clone.log"

    # ── Tentativa 1: HTTPS (não precisa de chave SSH) ──────────────────────────
    Write-Log "Clonando repositório via HTTPS..." -Level "INFO"
    $proc = Start-Process "git" `
        -ArgumentList "clone --recurse-submodules $($CONFIG.RepoUrlHttps) `"$($CONFIG.InstallPath)`"" `
        -WorkingDirectory $parent `
        -Wait -PassThru -NoNewWindow `
        -RedirectStandardError $gitLog

    if ($proc.ExitCode -eq 0) {
        Set-Location $CONFIG.InstallPath
        Write-Log "Repositório clonado com sucesso via HTTPS." -Level "SUCCESS"
        return
    }

    # ── Tentativa 2: SSH direto ────────────────────────────────────────────────
    Write-Log "HTTPS falhou. Tentando via SSH..." -Level "WARN"
    $proc = Start-Process "git" `
        -ArgumentList "clone --recurse-submodules $($CONFIG.RepoUrl) `"$($CONFIG.InstallPath)`"" `
        -WorkingDirectory $parent `
        -Wait -PassThru -NoNewWindow `
        -RedirectStandardError $gitLog

    if ($proc.ExitCode -eq 0) {
        Set-Location $CONFIG.InstallPath
        Write-Log "Repositório clonado com sucesso via SSH." -Level "SUCCESS"
        return
    }

    # ── Tentativa 3: Configura chave SSH e tenta de novo ──────────────────────
    Write-Log "SSH direto também falhou. Iniciando configuração guiada de chave SSH..." -Level "WARN"

    $sshOk = Invoke-SetupSSHKey   # FIX 2 — agora o loop fica aqui até o usuário confirmar ou desistir

    if ($sshOk) {
        # FIX 2: tenta o clone novamente após SSH confirmado
        Write-Log "Tentando clone via SSH com a chave configurada..." -Level "INFO"
        $proc = Start-Process "git" `
            -ArgumentList "clone --recurse-submodules $($CONFIG.RepoUrl) `"$($CONFIG.InstallPath)`"" `
            -WorkingDirectory $parent `
            -Wait -PassThru -NoNewWindow `
            -RedirectStandardError $gitLog

        if ($proc.ExitCode -eq 0) {
            Set-Location $CONFIG.InstallPath
            Write-Log "Repositório clonado com sucesso via SSH." -Level "SUCCESS"
            return
        }

        # Clone ainda falhou após SSH OK — consulta IA e oferece nova tentativa
        $errLog = Get-Content $gitLog -Raw -ErrorAction SilentlyContinue
        Write-Log "Clone falhou mesmo com SSH autenticado. Consultando IA..." -Level "WARN"
        Invoke-GeminiAI `
            -Prompt "O clone SSH do repositório Evo CRM falhou mesmo após autenticar com sucesso no GitHub." `
            -Context "Log do git:`n$errLog"

        Write-Host ""
        Write-Host "  Deseja tentar o clone novamente após aplicar a sugestão da IA? (S/N)" -ForegroundColor Yellow
        $retry = Read-Host "  Resposta"
        if ($retry -eq "S" -or $retry -eq "s") {
            Invoke-CloneRepo   # recursão — tentará tudo de novo
            return
        }
    }

    # ── Tudo falhou — NÃO fecha o PowerShell; aguarda o usuário ───────────────
    $errLog = Get-Content $gitLog -Raw -ErrorAction SilentlyContinue
    Invoke-GeminiAI `
        -Prompt "Não foi possível clonar o repositório do Evo CRM Community via HTTPS nem SSH após configuração de chave." `
        -Context "Log do git:`n$errLog"

    Write-Host ""
    Write-Host "  ╔══════════════════════════════════════════════════════╗" -ForegroundColor Red
    Write-Host "  ║  ✖  Não foi possível clonar o repositório.           ║" -ForegroundColor Red
    Write-Host "  ║                                                      ║" -ForegroundColor Red
    Write-Host "  ║  Opções:                                             ║" -ForegroundColor Yellow
    Write-Host "  ║  [1] Tentar novamente (após corrigir o problema)     ║" -ForegroundColor Yellow
    Write-Host "  ║  [2] Encerrar instalação                             ║" -ForegroundColor Yellow
    Write-Host "  ╚══════════════════════════════════════════════════════╝" -ForegroundColor Red
    Write-Host ""
    $choice = Read-Host "  Escolha (1/2)"

    if ($choice -eq "1") {
        Invoke-CloneRepo   # tenta de novo — o PowerShell continua aberto
    } else {
        Write-Host ""
        Write-Host "  Instalação encerrada. Logs em: $($CONFIG.LogFile)" -ForegroundColor Gray
        Write-Host "  Pressione ENTER para sair..." -ForegroundColor Gray
        Read-Host
        exit 1
    }
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
# ETAPA 5 — Executar make setup — FIX 3 (retry assistido por IA)
# =============================================================================

function Invoke-MakeSetup {
    Set-Location $CONFIG.InstallPath

    Write-Log "Iniciando 'make setup' (pode levar 15-20 min na primeira vez)..." -Level "INFO"
    Write-Log "Acompanhe o progresso abaixo:" -Level "INFO"
    Write-Host ""

    $timeoutSeconds = $CONFIG.SetupTimeoutMin * 60
    $startTime      = Get-Date

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
        return
    }

    # ── FIX 3: Falhou — coleta logs e entra no loop de retry com IA ──────────
    Write-Log "make setup terminou com erro (código $exitCode). Acionando assistência da IA..." -Level "WARN"

    $stdErr = ""
    if (Test-Path "$($CONFIG.LogFolder)\make-setup-stderr.log") {
        $stdErr = Get-Content "$($CONFIG.LogFolder)\make-setup-stderr.log" -Raw -ErrorAction SilentlyContinue
    }
    $stdOut = ""
    if (Test-Path "$($CONFIG.LogFolder)\make-setup-stdout.log") {
        $stdOut = Get-Content "$($CONFIG.LogFolder)\make-setup-stdout.log" -Tail 50 -ErrorAction SilentlyContinue | Out-String
    }

    $errorContext = "STDOUT (últimas 50 linhas):`n$stdOut`n`nSTDERR:`n$stdErr"

    # Usa o loop de retry assistido por IA
    $result = Invoke-WithAIRetry `
        -StepName "make setup" `
        -ErrorContext $errorContext `
        -Action {
            Set-Location $CONFIG.InstallPath
            $p = Start-Process "make" -ArgumentList "setup" `
                -WorkingDirectory $CONFIG.InstallPath `
                -PassThru -NoNewWindow `
                -RedirectStandardOutput "$($CONFIG.LogFolder)\make-setup-stdout.log" `
                -RedirectStandardError  "$($CONFIG.LogFolder)\make-setup-stderr.log" `
                -Wait
            if ($p.ExitCode -ne 0) {
                throw "make setup saiu com código $($p.ExitCode)"
            }
        }

    if (-not $result) {
        Write-Log "make setup não concluído. Instalação pode estar incompleta." -Level "WARN"
    }
}

# =============================================================================
# ETAPA 6 — Health check — FIX 3 (retry com IA nos serviços com falha)
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

    # ── FIX 3: Serviços com falha — IA diagnostica cada um ───────────────────
    if (-not $allReady) {
        Write-Log "Alguns serviços não responderam. Acionando diagnóstico da IA..." -Level "WARN"

        foreach ($svc in $failedSvcs) {
            Write-Log "Coletando logs do serviço: $($svc.Name)" -Level "WARN"
            $containerLogs = docker logs $svc.Name 2>&1 | Select-Object -Last 30 | Out-String
            Invoke-GeminiAI `
                -Prompt "O serviço '$($svc.Name)' não ficou disponível em $($svc.Url) após $($CONFIG.MaxHealthRetries) tentativas." `
                -Context "Logs do container:`n$containerLogs"
        }

        # Pergunta se quer tentar mais tempo antes de prosseguir
        Write-Host ""
        Write-Host "  ╔══════════════════════════════════════════════════╗" -ForegroundColor Yellow
        Write-Host "  ║  Alguns serviços ainda não responderam.          ║" -ForegroundColor Yellow
        Write-Host "  ║  [1] Aguardar mais (mais $($CONFIG.MaxHealthRetries) verificações)  ║" -ForegroundColor Yellow
        Write-Host "  ║  [2] Continuar mesmo assim                       ║" -ForegroundColor Yellow
        Write-Host "  ╚══════════════════════════════════════════════════╝" -ForegroundColor Yellow
        Write-Host ""
        $choice = Read-Host "  Escolha (1/2)"

        if ($choice -eq "1") {
            # Recursão — tenta mais uma rodada completa de health checks
            return Wait-ServicesReady
        }

        Write-Log "Prosseguindo com serviços parcialmente ativos (conforme escolha do usuário)." -Level "WARN"
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

Invoke-Step "Verificando pre-requisitos"              { Assert-Prerequisites }
# Docker garantidamente aberto a partir daqui
Invoke-Step "Escaneando ambiente (portas/containers)" { Get-EnvironmentSnapshot }
Invoke-Step "Clonando repositório do Evo CRM"         { Invoke-CloneRepo }
Invoke-Step "Configurando arquivo .env"               { Initialize-EnvFile }
Invoke-Step "Executando make setup"                   { Invoke-MakeSetup }

$ready = $false
Invoke-Step "Verificando saúde dos serviços"          { $script:ready = Wait-ServicesReady }

Write-FinalSummary -AllReady $script:ready

Write-Log "install-evo-crm.ps1 finalizado." -Level "SUCCESS"
