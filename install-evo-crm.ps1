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

$GEMINI_API_KEY = "AIzaSyBv2eJ3Atp1g9i7I7N9BsIpfQZNGewFfHg"   # Obtenha gratuitamente em: aistudio.google.com/apikey

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

    # SSH
    SSHKeyPath      = "$env:USERPROFILE\.ssh\id_evo_crm"
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
# ETAPA 1a -- Gerar chave SSH e confirmar autenticacao com GitHub
#
# Os submódulos do Evo CRM têm URLs SSH hardcoded no .gitmodules, portanto
# SSH funcional é pré-requisito obrigatório antes de qualquer clone.
# Esta etapa:
#   1. Gera a chave ed25519 (se ainda nao existir)
#   2. Configura ~/.ssh/config para usar a chave ao conectar no GitHub
#   3. Exibe a chave pública e instrucoes de cadastro
#   4. Fica em loop até confirmar autenticacao bem-sucedida com "ssh -T"
# =============================================================================

function Assert-SSHKey {
    $keyPath    = $CONFIG.SSHKeyPath
    $pubKeyPath = "$keyPath.pub"
    $sshDir     = Split-Path $keyPath -Parent

    Write-Log "Configurando chave SSH para o GitHub..." -Level "INFO"

    # Cria o diretório .ssh se necessário
    if (-not (Test-Path $sshDir)) {
        New-Item -ItemType Directory -Path $sshDir -Force | Out-Null
    }

    # Gera a chave apenas se ainda não existir
    if (-not (Test-Path $pubKeyPath)) {
        Write-Host ""
        $email = Read-Host "  Digite seu e-mail do GitHub (para identificar a chave SSH)"
        try {
            ssh-keygen -t ed25519 -C $email -f $keyPath -N "" 2>&1 | Out-Null
            Write-Log "Chave SSH gerada em: $keyPath" -Level "SUCCESS"
        }
        catch {
            Invoke-SafeExit "Nao foi possivel gerar a chave SSH: $_"
        }
    }
    else {
        Write-Log "Chave SSH existente encontrada: $keyPath" -Level "INFO"
    }

    # Garante que a chave está no ssh-agent
    try {
        $agent = Get-Service -Name "ssh-agent" -ErrorAction SilentlyContinue
        if ($agent -and $agent.Status -ne "Running") {
            Start-Service ssh-agent -ErrorAction SilentlyContinue
        }
        ssh-add $keyPath 2>&1 | Out-Null
    }
    catch { }

    # Configura ~/.ssh/config para usar esta chave ao conectar ao GitHub
    $sshConfigPath = "$sshDir\config"
    $sshConfigEntry = @"

Host github.com
    HostName github.com
    User git
    IdentityFile $keyPath
    IdentitiesOnly yes
"@
    $alreadyConfigured = $false
    if (Test-Path $sshConfigPath) {
        $existing = Get-Content $sshConfigPath -Raw -ErrorAction SilentlyContinue
        if ($existing -match [regex]::Escape($keyPath)) {
            $alreadyConfigured = $true
        }
    }
    if (-not $alreadyConfigured) {
        Add-Content -Path $sshConfigPath -Value $sshConfigEntry -Encoding ASCII
        Write-Log "Entrada github.com adicionada ao arquivo ~/.ssh/config." -Level "SUCCESS"
    }

    # Corrige permissoes do ~/.ssh/config e da chave privada.
    # O SSH no Windows rejeita qualquer arquivo com ACLs herdadas ou de outros usuarios.
    # Isso e a causa do erro "Bad owner or permissions on ~/.ssh/config".
    foreach ($filePath in @($sshConfigPath, $keyPath, $pubKeyPath)) {
        if (-not (Test-Path $filePath)) { continue }
        try {
            # Remove heranca de ACLs e limpa todas as entradas existentes
            $acl = Get-Acl $filePath
            $acl.SetAccessRuleProtection($true, $false)   # bloqueia heranca, remove regras herdadas
            $acl.Access | ForEach-Object { $acl.RemoveAccessRule($_) | Out-Null }

            # Adiciona apenas o usuario atual com controle total
            $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
            $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
                $currentUser,
                "FullControl",
                "Allow"
            )
            $acl.AddAccessRule($rule)
            Set-Acl -Path $filePath -AclObject $acl
        }
        catch {
            Write-Log "Aviso: nao foi possivel corrigir permissoes de '$filePath': $_" -Level "WARN"
        }
    }
    Write-Log "Permissoes dos arquivos SSH corrigidas." -Level "SUCCESS"

    # Lê a chave pública
    $pubKey = (Get-Content $pubKeyPath -Raw -ErrorAction SilentlyContinue).Trim()
    if (-not $pubKey) {
        Invoke-SafeExit "Nao foi possivel ler a chave publica em: $pubKeyPath"
    }

    # Copia para a área de transferência (silencioso se falhar)
    try { $pubKey | Set-Clipboard } catch { }

    # Exibe instrucoes
    Write-Host ""
    Write-Host "  ================================================================" -ForegroundColor Cyan
    Write-Host "  CHAVE SSH PUBLICA — cadastre no GitHub antes de continuar" -ForegroundColor Cyan
    Write-Host "  (ja copiada automaticamente para a area de transferencia)" -ForegroundColor DarkGray
    Write-Host "  ================================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  $pubKey" -ForegroundColor White
    Write-Host ""
    Write-Host "  ================================================================" -ForegroundColor Cyan
    Write-Host "  Como cadastrar:" -ForegroundColor Cyan
    Write-Host "    1. Abra: https://github.com/settings/keys" -ForegroundColor White
    Write-Host "    2. Clique em 'New SSH key'" -ForegroundColor White
    Write-Host "    3. Cole a chave no campo 'Key' (Ctrl+V)" -ForegroundColor White
    Write-Host "    4. Clique em 'Add SSH key'" -ForegroundColor White
    Write-Host "  ================================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Log "Chave publica exibida. Aguardando cadastro no GitHub." -Level "INFO"

    # Loop: testa SSH após o usuário confirmar o cadastro
    while ($true) {
        $resp = Read-Host "  Ja cadastrou a chave no GitHub? (S/N)"
        if ($resp.Trim().ToUpper() -ne "S") {
            Write-Host "  Ok. Cadastre a chave seguindo os passos acima e responda S." -ForegroundColor Yellow
            continue
        }

        Write-Log "Testando conexao SSH com GitHub (ssh -T git@github.com)..." -Level "INFO"

        # O GitHub sempre retorna exit code 1 no "ssh -T" (nao permite shell),
        # mas escreve "successfully authenticated" no stderr quando a chave e valida.
        $sshStderr = "$($CONFIG.LogFolder)\ssh-test-stderr.log"
        $sshStdout = "$($CONFIG.LogFolder)\ssh-test-stdout.log"
        $proc = Start-Process `
            -FilePath       "ssh" `
            -ArgumentList   "-T git@github.com -o StrictHostKeyChecking=no -o BatchMode=yes -i `"$keyPath`"" `
            -Wait -PassThru -NoNewWindow `
            -RedirectStandardOutput $sshStdout `
            -RedirectStandardError  $sshStderr

        $sshOut = ""
        if (Test-Path $sshStderr) {
            $sshOut = Get-Content $sshStderr -Raw -ErrorAction SilentlyContinue
        }

        if ($sshOut -match "successfully authenticated") {
            Write-Log "Autenticacao SSH com GitHub confirmada." -Level "SUCCESS"
            Write-Host "  OK Autenticacao SSH com o GitHub confirmada!" -ForegroundColor Green
            Write-Host ""
            return
        }

        # Falhou — orienta o usuario e repete
        Write-Log "SSH ainda nao autenticado. Resposta: $sshOut" -Level "WARN"
        Write-Host ""
        Write-Host "  X  Autenticacao SSH falhou." -ForegroundColor Red
        if ($sshOut) {
            Write-Host "     Resposta do GitHub:" -ForegroundColor DarkGray
            $sshOut -split "`n" | ForEach-Object { Write-Host "     $_" -ForegroundColor DarkGray }
        }
        Write-Host ""
        Write-Host "  Verifique se:" -ForegroundColor Yellow
        Write-Host "    - A chave foi colada COMPLETA (deve comecar com 'ssh-ed25519')" -ForegroundColor White
        Write-Host "    - Voce clicou em 'Add SSH key' e ela ja aparece na lista" -ForegroundColor White
        Write-Host "    - Esta logado na conta correta do GitHub" -ForegroundColor White
        Write-Host ""
        Write-Host "  Chave publica (copie novamente se precisar):" -ForegroundColor Cyan
        Write-Host "  $pubKey" -ForegroundColor White
        Write-Host ""
        try { $pubKey | Set-Clipboard } catch { }
    }
}

# =============================================================================
# ETAPA 1b -- Verificar pre-requisitos (Docker, Git, make)
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

    # ---- Docker daemon -------------------------------------------------------
    $daemonOk = $false
    try {
        $null = docker info 2>&1
        if ($LASTEXITCODE -eq 0) { $daemonOk = $true }
    } catch { }

    if (-not $daemonOk) {

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

        for ($i = 1; $i -le 36; $i++) {
            Start-Sleep -Seconds 5
            try {
                $null = docker info 2>&1
                if ($LASTEXITCODE -eq 0) { $daemonOk = $true; break }
            } catch { }
            Write-Host "  Aguardando Docker... $($i * 5)s de 180s" -ForegroundColor DarkGray
        }

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
                    Write-Host "  Verifique se ele esta completamente aberto (icone estavel na bandeja)." -ForegroundColor Yellow
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

    # ---- make ----------------------------------------------------------------
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
                Invoke-GeminiAI `
                    -Prompt "O comando 'make' nao foi encontrado apos tentar instalar via winget e Chocolatey no Windows." `
                    -Context "O script precisa do make para rodar o Makefile do Evo CRM. Como instalar no Windows 10/11?" | Out-Null

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
# ETAPA 3 -- Clonar repositorio via SSH
#
# SSH ja foi validado em Assert-SSHKey, portanto usamos diretamente
# a URL SSH. Isso garante que os submódulos (que têm URLs SSH hardcoded
# no .gitmodules) também funcionem sem precisar de reescrita de URL.
# =============================================================================

function Invoke-CloneRepo {
    $cloneUrl = $CONFIG.RepoUrl   # sempre SSH

    if (Test-Path "$($CONFIG.InstallPath)\.git") {
        Write-Log "Repositorio ja existe. Atualizando submodulos..." -Level "INFO"

        $proc = Start-Process "git" `
            -ArgumentList "submodule update --init --recursive" `
            -WorkingDirectory $CONFIG.InstallPath `
            -Wait -PassThru -NoNewWindow `
            -RedirectStandardOutput "$($CONFIG.LogFolder)\submodule-stdout.log" `
            -RedirectStandardError  "$($CONFIG.LogFolder)\submodule-stderr.log"

        if ($proc.ExitCode -eq 0) {
            Write-Log "Submodulos atualizados com sucesso." -Level "SUCCESS"
        } else {
            $errLog = Get-Content "$($CONFIG.LogFolder)\submodule-stderr.log" -Raw -ErrorAction SilentlyContinue
            Write-Log "Falha ao atualizar submodulos: $errLog" -Level "WARN"
            Invoke-GeminiAI `
                -Prompt "Falha ao atualizar submódulos git via SSH no Evo CRM." `
                -Context "Log:`n$errLog" | Out-Null
        }
        return
    }

    $parent = Split-Path $CONFIG.InstallPath -Parent
    if (-not (Test-Path $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    $gitLog = "$($CONFIG.LogFolder)\git-clone.log"
    Write-Log "Clonando via SSH: $cloneUrl" -Level "INFO"

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

    $errLog = Get-Content $gitLog -Raw -ErrorAction SilentlyContinue
    Write-Log "Clone falhou. Consultando IA..." -Level "WARN"
    Invoke-GeminiAI `
        -Prompt "Clone do repositorio Evo CRM falhou via SSH." `
        -Context "Log:`n$errLog" | Out-Null

    Write-Host ""
    Write-Host "  [1] Tentar o clone novamente" -ForegroundColor Yellow
    Write-Host "  [2] Encerrar a instalacao" -ForegroundColor Yellow
    Write-Host ""
    $choice = Read-Host "  Escolha (1/2)"
    if ($choice.Trim() -eq "2") {
        Invoke-SafeExit "Instalacao cancelada: clone do repositorio nao concluido."
    }
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
# =============================================================================

function Invoke-MakeSetup {
    Set-Location $CONFIG.InstallPath

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
# =============================================================================

try {
    Write-Banner

    # Etapa 1a: SSH — OBRIGATORIO primeiro (submodulos usam SSH hardcoded)
    Write-Log "Configurando autenticacao SSH com o GitHub..." -Level "STEP"
    Assert-SSHKey

    # Etapa 1b: Docker + Git + make
    Write-Log "Verificando pre-requisitos..." -Level "STEP"
    Assert-Prerequisites

    # Etapa 2: Scan de portas/containers
    Write-Log "Escaneando ambiente..." -Level "STEP"
    Get-EnvironmentSnapshot

    # Etapa 3: Clone via SSH (submodulos incluidos)
    Write-Log "Clonando repositorio do Evo CRM..." -Level "STEP"
    Invoke-CloneRepo

    # Etapa 4: .env
    Write-Log "Configurando arquivo .env..." -Level "STEP"
    Initialize-EnvFile

    # Etapa 5: make setup
    Write-Log "Executando make setup..." -Level "STEP"
    Invoke-MakeSetup

    # Etapa 6: Health check
    Write-Log "Verificando saude dos servicos..." -Level "STEP"
    $allReady = Wait-ServicesReady

    Write-FinalSummary -AllReady $allReady
    Write-Log "install-evo-crm.ps1 finalizado." -Level "SUCCESS"
}
catch {
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
