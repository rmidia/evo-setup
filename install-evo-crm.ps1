# =============================================================================
# INSTALL-EVO-CRM.PS1 — Instalação automatizada do Evo CRM Community
# =============================================================================
# USO:
#   irm https://raw.githubusercontent.com/SEU-USUARIO/SEU-REPO/main/install-evo-crm.ps1 | iex
# =============================================================================

# NÃO usa Set-StrictMode nem ErrorActionPreference = Stop globalmente,
# pois ao rodar via "irm | iex" qualquer exit/throw não tratado fecha a janela.
# Cada bloco crítico usa try/catch local.

# Garante execução de scripts nesta sessão
if ((Get-ExecutionPolicy -Scope Process) -notin @("RemoteSigned","Unrestricted","Bypass")) {
    Set-ExecutionPolicy -Scope Process -ExecutionPolicy RemoteSigned -Force
}

# =============================================================================
# CONFIGURACOES — SUBSTITUA ANTES DE PUBLICAR
# =============================================================================

$GEMINI_API_KEY = "SUA-CHAVE-AQUI"   # Obtenha gratuitamente em: aistudio.google.com/apikey

$CONFIG = @{
    # Repositório do Evo CRM
    RepoUrl         = "git@github.com:EvolutionAPI/evo-crm-community.git"
    RepoUrlHttps    = "https://github.com/EvolutionAPI/evo-crm-community.git"

    # Onde será instalado
    InstallPath     = "C:\EvoApps\evo-crm"

    # Log
    LogFolder       = "C:\EvoApps\logs"
    LogFile         = "C:\EvoApps\logs\install-evo-crm.log"

    # Servicos e portas esperadas
    Services        = @(
        @{ Name = "evo-auth-service-community";    Port = 3001; Url = "http://localhost:3001" }
        @{ Name = "evo-ai-crm-community";          Port = 3000; Url = "http://localhost:3000" }
        @{ Name = "evo-ai-frontend-community";     Port = 5173; Url = "http://localhost:5173" }
        @{ Name = "evo-ai-processor-community";    Port = 8000; Url = "http://localhost:8000" }
        @{ Name = "evo-ai-core-service-community"; Port = 5555; Url = "http://localhost:5555" }
    )

    # Health check
    MaxHealthRetries  = 20
    HealthRetryDelay  = 30
    SetupTimeoutMin   = 25

    # IA — Gemini
    GeminiModel     = "gemini-1.5-flash"
    GeminiUrl       = "https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent"

    # Retry com IA
    MaxAIRetries    = 4
}

# =============================================================================
# FUNCOES UTILITARIAS
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
        "INFO"    { Write-Host "  i  $Message" -ForegroundColor Cyan }
        "WARN"    { Write-Host "  !  $Message" -ForegroundColor Yellow }
        "ERROR"   { Write-Host "  X  $Message" -ForegroundColor Red }
        "SUCCESS" { Write-Host "  OK $Message" -ForegroundColor Green }
        "STEP"    { Write-Host "`n>> $Message" -ForegroundColor White }
        "AI"      { Write-Host "  AI $Message" -ForegroundColor Magenta }
    }
}

# ---------------------------------------------------------------------------
# Invoke-SafeExit
# Substitui todos os "exit 1" diretos. Pausa com Read-Host antes de sair
# para que o usuario leia o erro ao inves de ver a janela fechar de repente.
# ---------------------------------------------------------------------------
function Invoke-SafeExit {
    param([string]$Message = "Instalacao encerrada por erro.")
    Write-Host ""
    Write-Host "  ================================================================" -ForegroundColor Red
    Write-Host "  ERRO: $Message" -ForegroundColor Red
    Write-Host "  Log : $($CONFIG.LogFile)" -ForegroundColor DarkGray
    Write-Host "  ================================================================" -ForegroundColor Red
    Write-Log $Message -Level "ERROR"
    Write-Host ""
    Write-Host "  Pressione ENTER para fechar..." -ForegroundColor Gray
    Read-Host | Out-Null
    exit 1
}

function Write-Banner {
    Clear-Host
    Write-Host ""
    Write-Host "  =============================================" -ForegroundColor DarkGreen
    Write-Host "       EVO CRM  --  INSTALACAO v1.0          " -ForegroundColor DarkGreen
    Write-Host "       Plataforma CRM + IA Self-Hosted        " -ForegroundColor DarkGreen
    Write-Host "  =============================================" -ForegroundColor DarkGreen
    Write-Host ""
}

function Test-Administrator {
    $id        = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($id)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# =============================================================================
# INTEGRACAO COM GEMINI AI
# =============================================================================

function Invoke-GeminiAI {
    param(
        [string]$Prompt,
        [string]$Context = ""
    )

    if ($GEMINI_API_KEY -eq "SUA-CHAVE-AQUI") {
        Write-Log "Chave do Gemini nao configurada. Pulando analise de IA." -Level "WARN"
        return $null
    }

    Write-Log "Consultando Gemini AI..." -Level "AI"

    $fullPrompt = @"
Voce e um especialista em Docker, Linux e instalacao de aplicacoes self-hosted.
Analise o seguinte problema durante a instalacao do Evo CRM Community e responda:
1. Qual e a causa provavel do erro?
2. Qual comando ou acao corrige o problema?
3. Responda de forma objetiva e direta, em portugues.

CONTEXTO DO AMBIENTE:
- Windows com WSL2 e Docker Desktop
- Instalacao via PowerShell
- Aplicacao: Evo CRM Community (Docker Compose + make)

$Context

ERRO / SITUACAO:
$Prompt
"@

    $body = @{
        contents = @(
            @{ parts = @( @{ text = $fullPrompt } ) }
        )
    } | ConvertTo-Json -Depth 5

    try {
        Start-Sleep -Seconds 2   # respeita limite RPM do plano gratuito

        $response = Invoke-RestMethod `
            -Uri     "$($CONFIG.GeminiUrl)?key=$GEMINI_API_KEY" `
            -Method  POST `
            -Headers @{ "Content-Type" = "application/json" } `
            -Body    $body

        $answer = $response.candidates[0].content.parts[0].text

        Write-Host ""
        Write-Host "  ================================================================" -ForegroundColor Magenta
        Write-Host "  ANALISE DA IA:" -ForegroundColor Magenta
        Write-Host "  ================================================================" -ForegroundColor Magenta
        $answer -split "`n" | ForEach-Object { Write-Host "  $_" -ForegroundColor White }
        Write-Host "  ================================================================" -ForegroundColor Magenta
        Write-Host ""
        Write-Log $answer -Level "AI"
        return $answer
    }
    catch {
        Write-Log "Erro ao consultar Gemini AI: $_" -Level "WARN"
        return $null
    }
}

# ---------------------------------------------------------------------------
# Invoke-WithAIRetry
# Executa um scriptblock com retries assistidos pela IA.
# A cada falha consulta o Gemini. Ao esgotar tentativas pergunta ao usuario.
# ---------------------------------------------------------------------------
function Invoke-WithAIRetry {
    param(
        [string]$StepName,
        [scriptblock]$Action,
        [string]$ErrorContext = ""
    )

    $attempt    = 0
    $maxRetries = $CONFIG.MaxAIRetries

    while ($true) {
        $attempt++
        Write-Log "[$StepName] Tentativa $attempt de $maxRetries..." -Level "INFO"

        try {
            & $Action
            Write-Log "[$StepName] Concluido com sucesso na tentativa $attempt." -Level "SUCCESS"
            return $true
        }
        catch {
            $errMsg = "$_"
            Write-Log "[$StepName] Tentativa $attempt falhou: $errMsg" -Level "WARN"

            $ctx = if ($ErrorContext -ne "") { "$ErrorContext`n`nErro:`n$errMsg" }
                   else                      { "Erro:`n$errMsg" }

            Invoke-GeminiAI -Prompt "Falha em '$StepName' — tentativa $attempt de $maxRetries." -Context $ctx | Out-Null

            if ($attempt -ge $maxRetries) {
                Write-Host ""
                Write-Host "  ================================================================" -ForegroundColor Red
                Write-Host "  '$StepName' falhou $maxRetries vezes seguidas." -ForegroundColor Red
                Write-Host "  ================================================================" -ForegroundColor Yellow
                Write-Host "  [1] Parar a instalacao" -ForegroundColor Yellow
                Write-Host "  [2] Tentar mais $maxRetries vezes com IA" -ForegroundColor Yellow
                Write-Host "  [3] Pular esta etapa e continuar" -ForegroundColor Yellow
                Write-Host ""
                $choice = Read-Host "  Escolha (1/2/3)"

                switch ($choice.Trim()) {
                    "1" { Invoke-SafeExit "Instalacao interrompida pelo usuario apos $attempt falhas em '$StepName'." }
                    "2" { $attempt = 0 }
                    "3" {
                        Write-Log "[$StepName] Etapa ignorada pelo usuario." -Level "WARN"
                        return $false
                    }
                    default { Invoke-SafeExit "Opcao invalida. Encerrando." }
                }
            } else {
                Write-Host "  Aplique a sugestao da IA e pressione ENTER para tentar novamente." -ForegroundColor Yellow
                Write-Host "  Ou digite N para cancelar esta etapa." -ForegroundColor Yellow
                $resp = Read-Host "  [ENTER = tentar / N = cancelar]"
                if ($resp.Trim().ToUpper() -eq "N") {
                    Write-Log "[$StepName] Cancelado pelo usuario." -Level "WARN"
                    return $false
                }
            }
        }
    }
}

# =============================================================================
# ETAPA 1 -- Verificar pre-requisitos
# Ordem obrigatoria: Docker aberto -> Git -> make
# Nada avanca enquanto qualquer um desses nao estiver OK.
# =============================================================================

function Assert-Prerequisites {

    # ---- Admin ---------------------------------------------------------------
    if (-not (Test-Administrator)) {
        Invoke-SafeExit "Execute o PowerShell como Administrador e tente novamente."
    }
    Write-Log "Rodando como Administrador." -Level "SUCCESS"

    # ---- Docker CLI presente? ------------------------------------------------
    $dockerCmd = Get-Command docker -ErrorAction SilentlyContinue
    if (-not $dockerCmd) {
        Invoke-SafeExit "Docker CLI nao encontrado. Instale o Docker Desktop primeiro."
    }

    # ---- FIX 1 + FIX 4: Docker daemon --  NUNCA fecha o PowerShell -----------
    # Verifica se o daemon ja responde
    $daemonOk = $false
    try {
        $null = docker info 2>&1
        if ($LASTEXITCODE -eq 0) { $daemonOk = $true }
    } catch { }

    if (-not $daemonOk) {

        # Tenta abrir Docker Desktop automaticamente
        $ddPaths = @(
            "$env:ProgramFiles\Docker\Docker\Docker Desktop.exe",
            "${env:ProgramFiles(x86)}\Docker\Docker\Docker Desktop.exe",
            "$env:LOCALAPPDATA\Programs\Docker\Docker\Docker Desktop.exe"
        )

        $launched = $false
        foreach ($exePath in $ddPaths) {
            if (Test-Path $exePath) {
                Write-Log "Abrindo Docker Desktop automaticamente: $exePath" -Level "INFO"
                try {
                    Start-Process -FilePath $exePath -ErrorAction Stop
                    $launched = $true
                } catch {
                    Write-Log "Nao foi possivel abrir automaticamente: $_" -Level "WARN"
                }
                break
            }
        }

        if ($launched) {
            Write-Host ""
            Write-Host "  Docker Desktop iniciado. Aguardando daemon (ate 3 minutos)..." -ForegroundColor Cyan
        } else {
            Write-Log "Executavel do Docker Desktop nao encontrado para abertura automatica." -Level "WARN"
        }

        # Aguarda ate 3 minutos automaticamente (36 x 5 s)
        for ($i = 1; $i -le 36; $i++) {
            Start-Sleep -Seconds 5
            try {
                $null = docker info 2>&1
                if ($LASTEXITCODE -eq 0) { $daemonOk = $true; break }
            } catch { }
            Write-Host "  Aguardando Docker... $($i * 5)s de 180s" -ForegroundColor DarkGray
        }

        # Se ainda nao subiu: pede ao usuario para abrir manualmente.
        # Fica em loop infinito -- JAMAIS fecha o PowerShell sozinho.
        if (-not $daemonOk) {
            Write-Host ""
            Write-Host "  ================================================================" -ForegroundColor Yellow
            Write-Host "  O Docker Desktop nao iniciou automaticamente." -ForegroundColor Yellow
            Write-Host ""
            Write-Host "  Abra o Docker Desktop manualmente:" -ForegroundColor Yellow
            Write-Host "    1. Localize e abra o Docker Desktop" -ForegroundColor Yellow
            Write-Host "    2. Aguarde o icone estabilizar na barra de tarefas" -ForegroundColor Yellow
            Write-Host "    3. Volte aqui e responda S quando estiver pronto" -ForegroundColor Yellow
            Write-Host "  ================================================================" -ForegroundColor Yellow

            while (-not $daemonOk) {
                Write-Host ""
                $resp = Read-Host "  O Docker Desktop ja esta aberto e pronto? (S/N)"
                if ($resp.Trim().ToUpper() -ne "S") {
                    Write-Host "  Ok. Abra o Docker Desktop e volte aqui quando estiver pronto." -ForegroundColor Cyan
                    continue
                }

                Write-Log "Verificando Docker apos confirmacao do usuario..." -Level "INFO"
                for ($j = 1; $j -le 18; $j++) {
                    try {
                        $null = docker info 2>&1
                        if ($LASTEXITCODE -eq 0) { $daemonOk = $true; break }
                    } catch { }
                    Write-Host "  Verificando... $j de 18" -ForegroundColor DarkGray
                    Start-Sleep -Seconds 5
                }

                if (-not $daemonOk) {
                    Write-Host ""
                    Write-Host "  Docker ainda nao respondeu." -ForegroundColor Red
                    Write-Host "  Verifique se ele esta completamente aberto (icone estavelna bandeja)." -ForegroundColor Yellow
                }
            }
        }
    }

    Write-Log "Docker esta rodando." -Level "SUCCESS"

    # ---- Git -----------------------------------------------------------------
    $gitCmd = Get-Command git -ErrorAction SilentlyContinue
    if (-not $gitCmd) {
        Write-Log "Git nao encontrado. Instalando via winget..." -Level "WARN"
        try {
            winget install -e --id Git.Git --silent --accept-source-agreements --accept-package-agreements 2>&1 | Out-Null
            $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" +
                        [System.Environment]::GetEnvironmentVariable("Path","User")
            Write-Log "Git instalado." -Level "SUCCESS"
        } catch {
            Invoke-SafeExit "Nao foi possivel instalar o Git. Instale manualmente em git-scm.com e tente novamente."
        }
    } else {
        Write-Log "Git encontrado: $(git --version 2>&1)" -Level "SUCCESS"
    }

    # ---- make -- FIX 5: BLOQUEIA se nao conseguir instalar -------------------
    $makeCmd = Get-Command make -ErrorAction SilentlyContinue
    if (-not $makeCmd) {
        Write-Log "make nao encontrado. Tentando instalar via winget (GnuWin32)..." -Level "WARN"

        try {
            winget install -e --id GnuWin32.Make --silent --accept-source-agreements --accept-package-agreements 2>&1 | Out-Null
        } catch { }

        $makePath = "C:\Program Files (x86)\GnuWin32\bin"
        if (Test-Path "$makePath\make.exe") {
            $env:Path += ";$makePath"
            $userPath = [System.Environment]::GetEnvironmentVariable("Path","User")
            [System.Environment]::SetEnvironmentVariable("Path", "$userPath;$makePath", "User")
            Write-Log "make instalado via winget e adicionado ao PATH." -Level "SUCCESS"
        } else {
            Write-Log "winget nao instalou o make. Tentando via Chocolatey..." -Level "WARN"

            $chocoCmd = Get-Command choco -ErrorAction SilentlyContinue
            if (-not $chocoCmd) {
                try {
                    Set-ExecutionPolicy Bypass -Scope Process -Force
                    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
                    Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
                    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" +
                                [System.Environment]::GetEnvironmentVariable("Path","User")
                } catch {
                    Write-Log "Falha ao instalar Chocolatey: $_" -Level "WARN"
                }
            }

            try {
                choco install make -y 2>&1 | Out-Null
                $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" +
                            [System.Environment]::GetEnvironmentVariable("Path","User")
            } catch { }

            $makeCmd = Get-Command make -ErrorAction SilentlyContinue
            if ($makeCmd) {
                Write-Log "make instalado via Chocolatey." -Level "SUCCESS"
            } else {
                # Consulta IA para sugerir solucao ao usuario
                Invoke-GeminiAI `
                    -Prompt "O comando 'make' nao foi encontrado apos tentar instalar via winget e Chocolatey no Windows." `
                    -Context "O script precisa do make para rodar o Makefile do Evo CRM. Como instalar no Windows 10/11?" | Out-Null

                # Para aqui -- make e obrigatorio, nao ha como prosseguir
                Invoke-SafeExit "Nao foi possivel instalar o 'make'. Instale manualmente seguindo a sugestao da IA acima e execute o script novamente."
            }
        }
    } else {
        try {
            $mv = make --version 2>&1 | Select-Object -First 1
            Write-Log "make encontrado: $mv" -Level "SUCCESS"
        } catch {
            Write-Log "make encontrado." -Level "SUCCESS"
        }
    }
}

# =============================================================================
# ETAPA 2 -- Escanear portas e containers
# =============================================================================

function Get-EnvironmentSnapshot {
    Write-Log "Verificando portas em uso..." -Level "INFO"

    $usedPorts   = @{}
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
# ETAPA 3a -- Testar conectividade com GitHub
#
# Executada ANTES do clone. Garante que o git consegue se comunicar com o
# GitHub antes de tentar qualquer download.
#
# Fluxo:
#   1) Testa HTTPS  -> se ok, define $script:GitMethod = "https"  e retorna
#   2) Testa SSH    -> se ok, define $script:GitMethod = "ssh"    e retorna
#   3) Ambos falharam:
#      a) Gera chave SSH ed25519
#      b) Exibe a chave publica e instrucoes para adicionar no GitHub
#      c) Pergunta ao usuario: "Ja adicionou? (S/N)"
#      d) Se sim -> testa SSH novamente; se ok, segue; se nao, repete c/d
#      e) Se nao -> repete c
# =============================================================================

# Variavel de escopo de script: qual metodo de git usar no clone
$script:GitMethod = "https"

function New-SSHKey {
    $sshDir     = "$env:USERPROFILE\.ssh"
    $keyPath    = "$sshDir\id_evo_crm"
    $pubKeyPath = "$keyPath.pub"

    if (-not (Test-Path $sshDir)) {
        New-Item -ItemType Directory -Path $sshDir -Force | Out-Null
    }

    if (-not (Test-Path $pubKeyPath)) {
        Write-Host ""
        $email = Read-Host "  Digite seu e-mail do GitHub (para identificar a chave)"
        try {
            ssh-keygen -t ed25519 -C $email -f $keyPath -N "" 2>&1 | Out-Null
            Write-Log "Chave SSH gerada em: $keyPath" -Level "SUCCESS"
        } catch {
            Write-Log "Erro ao gerar chave SSH: $_" -Level "WARN"
            return $false
        }
    } else {
        Write-Log "Chave SSH existente reutilizada: $keyPath" -Level "INFO"
    }

    # Adiciona ao ssh-agent (silencioso)
    try {
        $agent = Get-Service -Name "ssh-agent" -ErrorAction SilentlyContinue
        if ($agent -and $agent.Status -ne "Running") {
            Start-Service ssh-agent -ErrorAction SilentlyContinue
        }
        ssh-add $keyPath 2>&1 | Out-Null
    } catch { }

    if (-not (Test-Path $pubKeyPath)) {
        Write-Log "Chave publica nao encontrada apos geracao: $pubKeyPath" -Level "ERROR"
        return $false
    }

    # Exibe a chave e instrucoes
    $pubKey = (Get-Content $pubKeyPath -Raw).Trim()

    Write-Host ""
    Write-Host "  ================================================================" -ForegroundColor Cyan
    Write-Host "  CHAVE SSH PUBLICA GERADA" -ForegroundColor Cyan
    Write-Host "  Copie TUDO abaixo (ja esta na area de transferencia):" -ForegroundColor Cyan
    Write-Host "  ================================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  $pubKey" -ForegroundColor White
    Write-Host ""
    Write-Host "  ================================================================" -ForegroundColor Cyan
    Write-Host "  Passos para adicionar no GitHub:" -ForegroundColor Cyan
    Write-Host "    1. Abra: https://github.com/settings/keys" -ForegroundColor White
    Write-Host "    2. Clique em 'New SSH key'" -ForegroundColor White
    Write-Host "    3. Cole a chave no campo 'Key'" -ForegroundColor White
    Write-Host "    4. Clique em 'Add SSH key'" -ForegroundColor White
    Write-Host "  ================================================================" -ForegroundColor Cyan
    Write-Host ""

    try { $pubKey | Set-Clipboard } catch { }
    Write-Log "Chave copiada para a area de transferencia." -Level "SUCCESS"

    return $true
}

function Test-GitHubConnectivity {
    Write-Log "Testando conectividade com GitHub..." -Level "INFO"

    # ---- Teste HTTPS ---------------------------------------------------------
    Write-Log "Verificando acesso via HTTPS..." -Level "INFO"
    try {
        $result = git ls-remote $CONFIG.RepoUrlHttps HEAD 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Log "GitHub acessivel via HTTPS." -Level "SUCCESS"
            $script:GitMethod = "https"
            return
        }
    } catch { }
    Write-Log "HTTPS nao disponivel." -Level "WARN"

    # ---- Teste SSH -----------------------------------------------------------
    Write-Log "Verificando acesso via SSH..." -Level "INFO"
    try {
        $result = git ls-remote $CONFIG.RepoUrl HEAD 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Log "GitHub acessivel via SSH." -Level "SUCCESS"
            $script:GitMethod = "ssh"
            return
        }
    } catch { }
    Write-Log "SSH nao disponivel." -Level "WARN"

    # ---- Ambos falharam: gera chave SSH e guia o usuario --------------------
    Write-Log "Sem acesso ao GitHub via HTTPS ou SSH. Iniciando configuracao de chave SSH..." -Level "WARN"

    $keyOk = New-SSHKey
    if (-not $keyOk) {
        Invoke-GeminiAI -Prompt "Nao foi possivel gerar chave SSH no Windows para o GitHub." | Out-Null
        Invoke-SafeExit "Falha ao criar chave SSH. Verifique os logs e tente novamente."
    }

    # Loop: aguarda o usuario adicionar a chave e confirmar, depois testa SSH
    while ($true) {
        Write-Host "  Voce ja adicionou a chave SSH no GitHub? (S/N)" -ForegroundColor Yellow
        $resp = Read-Host "  Resposta"

        if ($resp.Trim().ToUpper() -ne "S") {
            Write-Host "  Ok. Adicione a chave seguindo os passos acima e responda S quando pronto." -ForegroundColor Cyan
            continue
        }

        # Usuario confirmou -- testa SSH novamente
        Write-Log "Testando SSH apos adicao da chave..." -Level "INFO"
        try {
            $result = git ls-remote $CONFIG.RepoUrl HEAD 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Log "GitHub acessivel via SSH com a nova chave." -Level "SUCCESS"
                $script:GitMethod = "ssh"
                return
            }
        } catch { }

        # SSH ainda falhou
        Write-Log "SSH ainda nao funcionou apos adicao da chave." -Level "WARN"
        Invoke-GeminiAI `
            -Prompt "Acesso SSH ao GitHub falhou mesmo apos adicionar a chave em github.com/settings/keys." `
            -Context "Chave gerada em: $env:USERPROFILE\.ssh\id_evo_crm.pub" | Out-Null

        Write-Host ""
        Write-Host "  Verifique se:" -ForegroundColor Yellow
        Write-Host "    - A chave foi colada COMPLETA no GitHub (incluindo 'ssh-ed25519' no inicio)" -ForegroundColor White
        Write-Host "    - Voce clicou em 'Add SSH key' e a chave aparece na lista" -ForegroundColor White
        Write-Host "    - Esta usando a conta correta do GitHub" -ForegroundColor White
        Write-Host ""
    }
}

# =============================================================================
# ETAPA 3b -- Clonar repositorio
# Usa $script:GitMethod definido por Test-GitHubConnectivity.
# Ao chegar aqui a conectividade ja esta confirmada.
# =============================================================================

function Invoke-CloneRepo {
    if (Test-Path "$($CONFIG.InstallPath)\.git") {
        Write-Log "Repositorio ja existe. Atualizando submodulos..." -Level "INFO"
        try {
            Start-Process "git" -ArgumentList "submodule update --remote --merge" `
                -WorkingDirectory $CONFIG.InstallPath -Wait -PassThru -NoNewWindow | Out-Null
        } catch { }
        Write-Log "Repositorio atualizado." -Level "SUCCESS"
        return
    }

    $parent = Split-Path $CONFIG.InstallPath -Parent
    if (-not (Test-Path $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    $gitLog   = "$($CONFIG.LogFolder)\git-clone.log"
    $cloneUrl = if ($script:GitMethod -eq "ssh") { $CONFIG.RepoUrl } else { $CONFIG.RepoUrlHttps }

    Write-Log "Clonando via $($script:GitMethod.ToUpper()): $cloneUrl" -Level "INFO"

    if (Test-Path $CONFIG.InstallPath) {
        Remove-Item -Recurse -Force $CONFIG.InstallPath -ErrorAction SilentlyContinue
    }

    $proc = Start-Process "git" `
        -ArgumentList "clone --recurse-submodules `"$cloneUrl`" `"$($CONFIG.InstallPath)`"" `
        -WorkingDirectory $parent -Wait -PassThru -NoNewWindow `
        -RedirectStandardError $gitLog

    if ($proc.ExitCode -eq 0) {
        Write-Log "Clone concluido com sucesso." -Level "SUCCESS"
        Set-Location $CONFIG.InstallPath
        return
    }

    # Clone falhou mesmo com conectividade confirmada -- consulta IA e oferece retry
    $errLog = Get-Content $gitLog -Raw -ErrorAction SilentlyContinue
    Write-Log "Clone falhou inesperadamente. Consultando IA..." -Level "WARN"
    Invoke-GeminiAI `
        -Prompt "Clone do repositorio Evo CRM falhou mesmo apos conectividade confirmada." `
        -Context "Metodo: $($script:GitMethod)`nLog:`n$errLog" | Out-Null

    Write-Host ""
    Write-Host "  [1] Tentar o clone novamente" -ForegroundColor Yellow
    Write-Host "  [2] Encerrar a instalacao" -ForegroundColor Yellow
    Write-Host ""
    $choice = Read-Host "  Escolha (1/2)"
    if ($choice.Trim() -eq "2") {
        Invoke-SafeExit "Instalacao cancelada: clone do repositorio nao concluido."
    }
    # Tenta de novo recursivamente
    Invoke-CloneRepo
}

# =============================================================================
# ETAPA 4 -- Configurar .env
# =============================================================================

function Initialize-EnvFile {
    Set-Location $CONFIG.InstallPath

    if (-not (Test-Path ".env")) {
        if (Test-Path ".env.example") {
            Copy-Item ".env.example" ".env"
            Write-Log ".env criado a partir do .env.example." -Level "SUCCESS"
        } else {
            Invoke-GeminiAI -Prompt "O arquivo .env.example nao foi encontrado apos o clone do Evo CRM." | Out-Null
            Invoke-SafeExit ".env.example nao encontrado. O repositorio pode ter sido clonado de forma incompleta."
        }
    } else {
        Write-Log ".env ja existe, mantendo configuracoes atuais." -Level "INFO"
    }

    Write-Log "Banco de dados: Docker interno (Opcao A - padrao)." -Level "INFO"
    Write-Log ".env configurado." -Level "SUCCESS"
}

# =============================================================================
# ETAPA 5 -- Executar make setup
# So chega aqui se make estiver instalado (garantido na Etapa 1).
# =============================================================================

function Invoke-MakeSetup {
    Set-Location $CONFIG.InstallPath

    # Confirmacao final -- make obrigatorio
    $makeCmd = Get-Command make -ErrorAction SilentlyContinue
    if (-not $makeCmd) {
        Invoke-SafeExit "make nao encontrado. Nao e possivel executar 'make setup' sem ele."
    }

    Write-Log "Iniciando 'make setup' (pode levar 15-20 min na primeira execucao)..." -Level "INFO"
    Write-Host ""

    $timeoutSeconds = $CONFIG.SetupTimeoutMin * 60
    $startTime      = Get-Date

    $process = Start-Process `
        -FilePath "make" `
        -ArgumentList "setup" `
        -WorkingDirectory $CONFIG.InstallPath `
        -PassThru -NoNewWindow `
        -RedirectStandardOutput "$($CONFIG.LogFolder)\make-setup-stdout.log" `
        -RedirectStandardError  "$($CONFIG.LogFolder)\make-setup-stderr.log"

    while (-not $process.HasExited) {
        $elapsed = (Get-Date) - $startTime
        if ($elapsed.TotalSeconds -gt $timeoutSeconds) {
            Write-Log "Timeout de $($CONFIG.SetupTimeoutMin) minutos atingido." -Level "WARN"
            try { $process.Kill() } catch { }
            break
        }
        if (Test-Path "$($CONFIG.LogFolder)\make-setup-stdout.log") {
            $lastLines = Get-Content "$($CONFIG.LogFolder)\make-setup-stdout.log" -Tail 3 -ErrorAction SilentlyContinue
            if ($lastLines) { $lastLines | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray } }
        }
        Start-Sleep -Seconds 5
    }

    if ($process.ExitCode -eq 0) {
        Write-Log "make setup concluido com sucesso!" -Level "SUCCESS"
        return
    }

    # Falhou -- coleta logs e aciona loop de retry assistido pela IA
    Write-Log "make setup falhou (codigo $($process.ExitCode)). Acionando IA..." -Level "WARN"

    $stdErr = if (Test-Path "$($CONFIG.LogFolder)\make-setup-stderr.log") {
        Get-Content "$($CONFIG.LogFolder)\make-setup-stderr.log" -Raw -ErrorAction SilentlyContinue
    } else { "" }

    $stdOut = if (Test-Path "$($CONFIG.LogFolder)\make-setup-stdout.log") {
        Get-Content "$($CONFIG.LogFolder)\make-setup-stdout.log" -Tail 50 -ErrorAction SilentlyContinue | Out-String
    } else { "" }

    $errorContext = "STDOUT (ultimas 50 linhas):`n$stdOut`n`nSTDERR:`n$stdErr"

    Invoke-WithAIRetry -StepName "make setup" -ErrorContext $errorContext -Action {
        Set-Location $CONFIG.InstallPath
        $p = Start-Process "make" -ArgumentList "setup" `
            -WorkingDirectory $CONFIG.InstallPath `
            -PassThru -NoNewWindow `
            -RedirectStandardOutput "$($CONFIG.LogFolder)\make-setup-stdout.log" `
            -RedirectStandardError  "$($CONFIG.LogFolder)\make-setup-stderr.log" `
            -Wait
        if ($p.ExitCode -ne 0) { throw "make setup saiu com codigo $($p.ExitCode)" }
    } | Out-Null
}

# =============================================================================
# ETAPA 6 -- Health check dos servicos
# =============================================================================

function Wait-ServicesReady {
    Write-Log "Aguardando servicos ficarem disponiveis..." -Level "INFO"

    $allReady   = $false
    $attempt    = 0
    $failedSvcs = @()

    while ($attempt -lt $CONFIG.MaxHealthRetries -and -not $allReady) {
        $attempt++
        $failedSvcs = @()

        foreach ($svc in $CONFIG.Services) {
            try {
                $response = Invoke-WebRequest -Uri $svc.Url -UseBasicParsing -TimeoutSec 5 -ErrorAction SilentlyContinue
                if ($response.StatusCode -lt 500) {
                    Write-Log "$($svc.Name) -> OK ($($svc.Url))" -Level "SUCCESS"
                } else {
                    $failedSvcs += $svc
                    Write-Log "$($svc.Name) -> HTTP $($response.StatusCode)" -Level "WARN"
                }
            } catch {
                $failedSvcs += $svc
                Write-Log "$($svc.Name) -> nao respondeu ainda..." -Level "INFO"
            }
        }

        if ($failedSvcs.Count -eq 0) {
            $allReady = $true
        } elseif ($attempt -lt $CONFIG.MaxHealthRetries) {
            Write-Log "Tentativa $attempt/$($CONFIG.MaxHealthRetries) -- $($failedSvcs.Count) servico(s) subindo. Aguardando $($CONFIG.HealthRetryDelay)s..." -Level "INFO"
            Start-Sleep -Seconds $CONFIG.HealthRetryDelay
        }
    }

    if (-not $allReady) {
        Write-Log "Servicos com falha. Acionando diagnostico da IA..." -Level "WARN"
        foreach ($svc in $failedSvcs) {
            $containerLogs = docker logs $svc.Name 2>&1 | Select-Object -Last 30 | Out-String
            Invoke-GeminiAI `
                -Prompt "O servico '$($svc.Name)' nao respondeu em $($svc.Url) apos $($CONFIG.MaxHealthRetries) tentativas." `
                -Context "Logs do container:`n$containerLogs" | Out-Null
        }

        Write-Host ""
        Write-Host "  [1] Aguardar mais (nova rodada de verificacoes)" -ForegroundColor Yellow
        Write-Host "  [2] Continuar assim mesmo" -ForegroundColor Yellow
        Write-Host ""
        $choice = Read-Host "  Escolha (1/2)"
        if ($choice.Trim() -eq "1") {
            return Wait-ServicesReady
        }
        Write-Log "Prosseguindo com servicos parcialmente ativos (escolha do usuario)." -Level "WARN"
    }

    return $allReady
}

# =============================================================================
# ETAPA 7 -- Resumo final
# =============================================================================

function Write-FinalSummary {
    param([bool]$AllReady)

    Write-Host ""
    Write-Host "  =============================================" -ForegroundColor DarkGreen
    Write-Host "  EVO CRM -- RESULTADO DA INSTALACAO" -ForegroundColor White
    Write-Host "  =============================================" -ForegroundColor DarkGreen
    Write-Host ""

    if ($AllReady) {
        Write-Host "  OK  Todos os servicos estao rodando!" -ForegroundColor Green
        Write-Host ""
        Write-Host "  Acesse agora:" -ForegroundColor White
        Write-Host "  -> Frontend  : http://localhost:5173" -ForegroundColor Cyan
        Write-Host "  -> CRM API   : http://localhost:3000" -ForegroundColor Cyan
        Write-Host "  -> Auth API  : http://localhost:3001" -ForegroundColor Cyan
        Write-Host "  -> Processor : http://localhost:8000" -ForegroundColor Cyan
        Write-Host "  -> Core API  : http://localhost:5555" -ForegroundColor Cyan
        Write-Host "  -> Mailhog   : http://localhost:8025" -ForegroundColor Cyan
    } else {
        Write-Host "  !  Instalacao concluida com alertas." -ForegroundColor Yellow
        Write-Host "     Alguns servicos podem ainda estar iniciando." -ForegroundColor Yellow
        Write-Host "     Aguarde alguns minutos e acesse: http://localhost:5173" -ForegroundColor Yellow
    }

    Write-Host ""
    Write-Host "  Comandos uteis (na pasta $($CONFIG.InstallPath)):" -ForegroundColor White
    Write-Host "    make start   -- liga todos os servicos" -ForegroundColor Gray
    Write-Host "    make stop    -- desliga todos os servicos" -ForegroundColor Gray
    Write-Host "    make logs    -- exibe logs em tempo real" -ForegroundColor Gray
    Write-Host "    make status  -- mostra containers rodando" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  Log completo: $($CONFIG.LogFile)" -ForegroundColor DarkGray
    Write-Host "  =============================================" -ForegroundColor DarkGreen
    Write-Host ""
}

# =============================================================================
# EXECUCAO PRINCIPAL
# Todo o script roda dentro de um try/catch global.
# Erros nao tratados sao capturados e exibidos com pause antes de fechar.
# =============================================================================

try {
    Write-Banner

    # Etapa 1: Docker + Git + make (nao avanca sem todos os tres)
    Write-Log "Verificando pre-requisitos..." -Level "STEP"
    Assert-Prerequisites

    # Etapa 2: Scan de portas/containers (Docker ja garantido)
    Write-Log "Escaneando ambiente..." -Level "STEP"
    Get-EnvironmentSnapshot

    # Etapa 3a: Conectividade com GitHub (DEVE vir antes do clone e do make)
    # Garante que git consegue se comunicar antes de qualquer download.
    Write-Log "Verificando acesso ao GitHub..." -Level "STEP"
    Test-GitHubConnectivity

    # Etapa 3b: Clone (conectividade ja confirmada, metodo definido em $script:GitMethod)
    Write-Log "Clonando repositorio do Evo CRM..." -Level "STEP"
    Invoke-CloneRepo

    # Etapa 4: .env
    Write-Log "Configurando arquivo .env..." -Level "STEP"
    Initialize-EnvFile

    # Etapa 5: make setup (so chega aqui com make instalado e repo clonado)
    Write-Log "Executando make setup..." -Level "STEP"
    Invoke-MakeSetup

    # Etapa 6: Health check
    Write-Log "Verificando saude dos servicos..." -Level "STEP"
    $allReady = Wait-ServicesReady

    Write-FinalSummary -AllReady $allReady
    Write-Log "install-evo-crm.ps1 finalizado." -Level "SUCCESS"
}
catch {
    # Captura qualquer erro nao tratado -- exibe e pausa antes de fechar
    Write-Host ""
    Write-Host "  ================================================================" -ForegroundColor Red
    Write-Host "  ERRO INESPERADO:" -ForegroundColor Red
    Write-Host "  $_" -ForegroundColor Red
    Write-Host "  Log: $($CONFIG.LogFile)" -ForegroundColor DarkGray
    Write-Host "  ================================================================" -ForegroundColor Red
    Write-Host ""
    Write-Host "  Pressione ENTER para fechar..." -ForegroundColor Gray
    Read-Host | Out-Null
}
