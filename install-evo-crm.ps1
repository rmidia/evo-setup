# =============================================================================
# INSTALL-EVO-CRM.PS1 — Instalação automatizada do Evo CRM Community (REVISADO)
# =============================================================================
# USO:
#   irm https://raw.githubusercontent.com/SEU-USUARIO/SEU-REPO/main/install-evo-crm-revised.ps1 | iex
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

# ATENÇÃO: NUNCA COLOQUE SUA CHAVE GEMINI DIRETAMENTE AQUI EM REPOSITÓRIOS PÚBLICOS.
# Use variáveis de ambiente. Ex: $env:GEMINI_API_KEY
# Para testes locais, você pode definir temporariamente: $env:GEMINI_API_KEY = "SUA_CHAVE_AQUI"
$GEMINI_API_KEY = $env:GEMINI_API_KEY
if (-not $GEMINI_API_KEY) {
    Write-Host "ERRO: A chave GEMINI_API_KEY não foi encontrada nas variáveis de ambiente." -ForegroundColor Red
    Write-Host "Por favor, defina a variável de ambiente GEMINI_API_KEY antes de executar o script." -ForegroundColor Yellow
    Invoke-SafeExit "Chave GEMINI_API_KEY ausente."
}

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
    GeminiBaseUrl   = "https://generativelanguage.googleapis.com/v1beta/models"

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

# ---------------------------------------------------------------------------
# Sanitize-LogContent
# Remove informações sensíveis de logs antes de enviar para a IA.
# ---------------------------------------------------------------------------
function Sanitize-LogContent {
    param(
        [string]$Content
    )
    $sanitized = $Content
    # Remove caminhos de usuário
    $sanitized = $sanitized -replace "C:\\Users\\.*?\\", "C:\\Users\\<USER>\\"
    $sanitized = $sanitized -replace "/home/.*?/", "/home/<USER>/"
    # Remove chaves SSH (pública e privada) - padrões comuns
    $sanitized = $sanitized -replace "ssh-ed25519 [A-Za-z0-9+/=]+\s.*?", "ssh-ed25519 <PUBLIC_KEY_REDACTED>"
    $sanitized = $sanitized -replace "-----BEGIN OPENSSH PRIVATE KEY-----[\s\S]*?-----END OPENSSH PRIVATE KEY-----", "<PRIVATE_KEY_REDACTED>"
    $sanitized = $sanitized -replace "-----BEGIN RSA PRIVATE KEY-----[\s\S]*?-----END RSA PRIVATE KEY-----", "<PRIVATE_KEY_REDACTED>"
    # Remove chaves de API (padrão Gemini)
    $sanitized = $sanitized -replace "AIzaSy[A-Za-z0-9_\-]{35}", "<GEMINI_API_KEY_REDACTED>"
    # Remove senhas ou tokens genéricos (se houver)
    $sanitized = $sanitized -replace "password=\S+", "password=<REDACTED>"
    $sanitized = $sanitized -replace "token=\S+", "token=<REDACTED>"
    return $sanitized
}

# =============================================================================
# INTEGRACAO COM GEMINI AI
# =============================================================================

function Invoke-GeminiAI {
    param(
        [string]$Prompt,
        [string]$Context = ""
    )

    if (-not $GEMINI_API_KEY) {
        Write-Log "Chave do Gemini não configurada. Pulando análise de IA." -Level "WARN"
        return $null
    }

    Write-Log "Consultando Gemini AI..." -Level "AI"

    $sanitizedContext = Sanitize-LogContent -Content $Context

    $fullPrompt = @"
Você é um especialista em Docker, Linux e instalação de aplicações self-hosted.
Analise o seguinte problema durante a instalação do Evo CRM Community e responda em formato JSON com as seguintes chaves:
- 'cause': A causa provável do erro.
- 'explanation': Uma explicação detalhada do problema e da solução.
- 'command': O comando PowerShell ou shell (Linux) para corrigir o problema. Se for um comando PowerShell, prefixe com 'powershell -Command '. Se for um comando Linux/WSL, prefixe com 'wsl -e bash -c '.
- 'requires_user_input': Booleano indicando se o comando requer interação do usuário.

CONTEXTO DO AMBIENTE:
- Windows com WSL2 e Docker Desktop
- Instalação via PowerShell
- Aplicação: Evo CRM Community (Docker Compose + make)

$sanitizedContext

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

        # Monta a URL exatamente como o Gemini sugeriu: .../models/{MODEL}:generateContent?key={KEY}
        $apiUrl = "$($CONFIG.GeminiBaseUrl)/$($CONFIG.GeminiModel):generateContent?key=$($GEMINI_API_KEY)"

        $response = Invoke-RestMethod `
            -Uri     $apiUrl `
            -Method  POST `
            -Headers @{ "Content-Type" = "application/json" } `
            -Body    $body
        
        $answer = $response.candidates[0].content.parts[0].text

        # Limpeza de Markdown se a IA retornar blocos de código ```json ... ```
        # Usamos o caractere de escape do PowerShell (backtick) para os backticks do Markdown
        $cleanJson = $answer
        if ($cleanJson -match "``````json\s*([\s\S]*?)\s*``````") {
            $cleanJson = $matches[1]
        } elseif ($cleanJson -match "``````\s*([\s\S]*?)\s*``````") {
            $cleanJson = $matches[1]
        }

        # Tenta parsear a resposta como JSON
        try {
            $jsonAnswer = $cleanJson | ConvertFrom-Json
            Write-Log "Resposta da IA (JSON): $($jsonAnswer | ConvertTo-Json -Compress)" -Level "AI"
            return $jsonAnswer
        } catch {
            Write-Log "Resposta da IA não é JSON válido. Tentando extrair campos manualmente..." -Level "WARN"
            # Fallback: Se falhar o JSON, tenta extrair o comando se houver algo entre aspas ou blocos
            return [pscustomobject]@{ 
                cause = "Erro no parse JSON"; 
                explanation = $answer; 
                command = ""; 
                requires_user_input = $false 
            }
        }
    }
    catch {
        Write-Log "Erro ao consultar Gemini AI: $_" -Level "WARN"
        return $null
    }
}

# ---------------------------------------------------------------------------
# Invoke-GeminiRepair
# Tenta corrigir um problema usando a sugestão da IA.
# ---------------------------------------------------------------------------
function Invoke-GeminiRepair {
    param(
        [string]$StepName,
        [string]$ErrorMessage,
        [string]$ErrorContext
    )

    Write-Log "[$StepName] Tentando reparo com IA..." -Level "AI"
    $iaResponse = Invoke-GeminiAI -Prompt $ErrorMessage -Context $ErrorContext

    if ($null -eq $iaResponse -or [string]::IsNullOrWhiteSpace($iaResponse.command)) {
        Write-Log "IA não forneceu um comando de correção ou falhou na consulta." -Level "WARN"
        return $false
    }

    Write-Host ""
    Write-Host "  ================================================================" -ForegroundColor Magenta
    Write-Host "  ANALISE DA IA:" -ForegroundColor Magenta
    Write-Host "  Causa: $($iaResponse.cause)" -ForegroundColor White
    Write-Host "  Explicacao: $($iaResponse.explanation)" -ForegroundColor White
    Write-Host "  Comando Sugerido: $($iaResponse.command)" -ForegroundColor White
    Write-Host "  ================================================================" -ForegroundColor Magenta
    Write-Host ""

    if ($iaResponse.requires_user_input) {
        Write-Log "Comando da IA requer interação do usuário. Solicitando confirmação." -Level "WARN"
        Write-Host "  O comando sugerido pela IA requer sua intervenção. Por favor, execute-o manualmente ou confirme se deseja prosseguir." -ForegroundColor Yellow
        Write-Host "  Comando: $($iaResponse.command)" -ForegroundColor Yellow
        $resp = Read-Host "  Pressione ENTER para continuar após executar/verificar, ou N para cancelar o reparo." -ForegroundColor Yellow
        if ($resp.Trim().ToUpper() -eq "N") {
            Write-Log "Reparo da IA cancelado pelo usuário." -Level "WARN"
            return $false
        }
    }

    Write-Log "Executando comando de correção da IA: $($iaResponse.command)" -Level "AI"
    try {
        Invoke-Expression $iaResponse.command
        Write-Log "Comando da IA executado com sucesso." -Level "SUCCESS"
        return $true
    }
    catch {
        Write-Log "Falha ao executar comando da IA: $_" -Level "ERROR"
        return $false
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

            if ($attempt -lt $maxRetries) {
                Write-Log "[$StepName] Tentando reparo automático com IA..." -Level "AI"
                $repaired = Invoke-GeminiRepair -StepName $StepName -ErrorMessage $errMsg -ErrorContext $ErrorContext
                if ($repaired) {
                    Write-Log "[$StepName] Reparo da IA aplicado. Tentando novamente a etapa." -Level "INFO"
                    # Não incrementa attempt, pois é uma nova tentativa após reparo
                    continue
                } else {
                    Write-Log "[$StepName] Reparo da IA falhou ou não foi possível. Tentando novamente sem reparo." -Level "WARN"
                }
            }

            if ($attempt -ge $maxRetries) {
                Write-Host ""
                Write-Host "  ================================================================" -ForegroundColor Red
                Write-Host "  ERRO CRÍTICO: '$StepName' falhou $maxRetries vezes seguidas." -ForegroundColor Red
                Write-Host "  ================================================================" -ForegroundColor Yellow
                Write-Host "  O script não conseguiu resolver o problema automaticamente." -ForegroundColor Yellow
                Write-Host "  Detalhes do último erro: $errMsg" -ForegroundColor Yellow
                Write-Host "  Contexto enviado para IA: $(Sanitize-LogContent -Content $ErrorContext)" -ForegroundColor DarkGray
                Write-Host ""
                Invoke-SafeExit "Falha crítica em '$StepName' após tentativas de reparo da IA."
            } else {
                Write-Log "Aguardando antes de próxima tentativa..." -Level "INFO"
                Start-Sleep -Seconds 5 # Pequena pausa antes de tentar novamente
            }
        }
    }
}

# =============================================================================
# ETAPA 1a -- Gerar chave SSH e confirmar autenticacao com GitHub
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

    # Remove chaves antigas do Evo CRM para evitar conflitos e garantir uma nova geração
    if (Test-Path $keyPath) {
        Write-Log "Removendo chave SSH antiga do Evo CRM: $keyPath" -Level "WARN"
        Remove-Item $keyPath -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path $pubKeyPath) {
        Write-Log "Removendo chave pública SSH antiga do Evo CRM: $pubKeyPath" -Level "WARN"
        Remove-Item $pubKeyPath -Force -ErrorAction SilentlyContinue
    }

    Write-Host ""
    $email = Read-Host "  Digite seu e-mail do GitHub (para identificar a nova chave SSH)"
    try {
        ssh-keygen -t ed25519 -C $email -f $keyPath -N "" 2>&1 | Out-Null
        Write-Log "Nova chave SSH gerada em: $keyPath" -Level "SUCCESS"
        
        # Aguarda o arquivo aparecer no disco (até 5 segundos)
        $waitCount = 0
        while (-not (Test-Path $pubKeyPath) -and $waitCount -lt 10) {
            Start-Sleep -Milliseconds 500
            $waitCount++
        }
    }
    catch {
        Invoke-SafeExit "Não foi possível gerar a chave SSH: $_"
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
    # Remove entradas antigas para github.com relacionadas a esta chave antes de adicionar
    if (Test-Path $sshConfigPath) {
        $content = Get-Content $sshConfigPath -Raw
        $content = $content -replace "(?smi)Host github.com.*?IdentityFile $($keyPath -replace '\\', '\\\\').*?IdentitiesOnly yes\s*", ""
        Set-Content -Path $sshConfigPath -Value $content -Encoding ASCII
    }
    Add-Content -Path $sshConfigPath -Value $sshConfigEntry -Encoding ASCII
    Write-Log "Entrada github.com adicionada/atualizada no arquivo ~/.ssh/config." -Level "SUCCESS"

    # Corrige permissoes do ~/.ssh/config e da chave privada.
    # O SSH no Windows rejeita qualquer arquivo com ACLs herdadas ou de outros usuarios.
    # Isso é a causa do erro "Bad owner or permissions on ~/.ssh/config".
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
            Write-Log "Aviso: não foi possível corrigir permissões de '$filePath': $_" -Level "WARN"
        }
    }
    Write-Log "Permissões dos arquivos SSH corrigidas." -Level "SUCCESS"

    # Lê a chave pública com múltiplas tentativas (evita erro de arquivo em uso ou atraso)
    $pubKeyRaw = $null
    for ($i = 1; $i -le 5; $i++) {
        $pubKeyRaw = Get-Content $pubKeyPath -Raw -ErrorAction SilentlyContinue
        if ($null -ne $pubKeyRaw) { break }
        Start-Sleep -Seconds 1
    }

    if ($null -eq $pubKeyRaw) {
        Invoke-SafeExit "O arquivo da chave pública não pôde ser lido após várias tentativas: $pubKeyPath"
    }
    $pubKey = $pubKeyRaw.Trim()
    if ([string]::IsNullOrWhiteSpace($pubKey)) {
        Invoke-SafeExit "A chave pública lida está em branco: $pubKeyPath"
    }

    # Copia para a área de transferência (silencioso se falhar)
    try { $pubKey | Set-Clipboard } catch { }

    # Exibe instrucoes
    Write-Host ""
    Write-Host "  ================================================================" -ForegroundColor Cyan
    Write-Host "  CHAVE SSH PÚBLICA — cadastre no GitHub antes de continuar" -ForegroundColor Cyan
    Write-Host "  (já copiada automaticamente para a área de transferência)" -ForegroundColor DarkGray
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
    Write-Log "Chave pública exibida. Aguardando cadastro no GitHub." -Level "INFO"

    # Loop: testa SSH após o usuário confirmar o cadastro
    while ($true) {
        Write-Host ""
        Write-Host "  Aguardando você cadastrar a chave no GitHub..." -ForegroundColor Yellow
        $resp = Read-Host "  Já cadastrou a chave no GitHub? (S/N)"
        if ($resp.Trim().ToUpper() -ne "S") {
            Write-Host "  Atenção: Você precisa cadastrar a chave em https://github.com/settings/keys antes de continuar." -ForegroundColor Red
            Write-Host "  A chave pública está exibida acima. Copie-a e cole no GitHub." -ForegroundColor White
            continue
        }

        Write-Log "Testando conexão SSH com GitHub (ssh -T git@github.com)..." -Level "INFO"

        # O GitHub sempre retorna exit code 1 no "ssh -T" (não permite shell),
        # mas escreve "successfully authenticated" no stderr quando a chave é válida.
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
            Write-Log "Autenticação SSH com GitHub confirmada." -Level "SUCCESS"
            Write-Host "  OK Autenticação SSH com o GitHub confirmada!" -ForegroundColor Green
            Write-Host ""
            return
        }

        # Falhou — orienta o usuario e repete
        Write-Log "SSH ainda não autenticado. Resposta: $sshOut" -Level "WARN"
        Write-Host ""
        Write-Host "  X  Autenticação SSH falhou." -ForegroundColor Red
        if ($sshOut) {
            Write-Host "     Resposta do GitHub:" -ForegroundColor DarkGray
            $sshOut -split "`n" | ForEach-Object { Write-Host "     $_" -ForegroundColor DarkGray }
        }
        Write-Host ""
        Write-Host "  Verifique se:" -ForegroundColor Yellow
        Write-Host "    - A chave foi colada COMPLETA (deve começar com 'ssh-ed25519')" -ForegroundColor White
        Write-Host "    - Você clicou em 'Add SSH key' e ela já aparece na lista" -ForegroundColor White
        Write-Host "    - Está logado na conta correta do GitHub" -ForegroundColor White
        Write-Host ""
        Write-Host "  Chave pública (copie novamente se precisar):" -ForegroundColor Cyan
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
    Invoke-WithAIRetry -StepName "Verificar Docker CLI" -Action {
        $dockerCmd = Get-Command docker -ErrorAction SilentlyContinue
        if (-not $dockerCmd) {
            throw "Docker CLI não encontrado. Instale o Docker Desktop primeiro."
        }
        Write-Log "Docker CLI encontrado." -Level "SUCCESS"
    } -ErrorContext "O comando 'docker' não foi encontrado no PATH. O Docker Desktop está instalado e configurado corretamente?"

    # ---- Docker daemon -------------------------------------------------------
    Invoke-WithAIRetry -StepName "Verificar Docker Daemon" -Action {
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
                        Start-Process -FilePath $exePath -NoNewWindow
                        $launched = $true
                    } catch {
                        Write-Log "Não foi possível abrir automaticamente: $_" -Level "WARN"
                    }
                    break
                }
            }

            if ($launched) {
                Write-Host ""
                Write-Host "  Docker Desktop iniciado. Aguardando daemon (até 3 minutos)..." -ForegroundColor Cyan
            } else {
                Write-Log "Executável do Docker Desktop não encontrado para abertura automática." -Level "WARN"
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
                Write-Host "  O Docker Desktop não iniciou automaticamente." -ForegroundColor Yellow
                Write-Host ""
                Write-Host "  Abra o Docker Desktop manualmente:" -ForegroundColor Yellow
                Write-Host "    1. Localize e abra o Docker Desktop" -ForegroundColor Yellow
                Write-Host "    2. Aguarde o ícone estabilizar na barra de tarefas" -ForegroundColor Yellow
                Write-Host "    3. Volte aqui e responda S quando estiver pronto" -ForegroundColor Yellow
                Write-Host "  ================================================================" -ForegroundColor Yellow

                while (-not $daemonOk) {
                    Write-Host ""
                    $resp = Read-Host "  O Docker Desktop já está aberto e pronto? (S/N)"
                    if ($resp.Trim().ToUpper() -ne "S") {
                        Write-Host "  Ok. Abra o Docker Desktop e volte aqui quando estiver pronto." -ForegroundColor Cyan
                        continue
                    }

                    Write-Log "Verificando Docker após confirmação do usuário..." -Level "INFO"
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
                        Write-Host "  Docker ainda não respondeu." -ForegroundColor Red
                        Write-Host "  Verifique se ele está completamente aberto (ícone estável na bandeja)." -ForegroundColor Yellow
                    }
                }
            }
        }
        if (-not $daemonOk) { throw "Docker daemon não está rodando ou não respondeu." }
        Write-Log "Docker está rodando." -Level "SUCCESS"
    } -ErrorContext "O Docker daemon não está respondendo. Verifique se o Docker Desktop está aberto e funcionando corretamente."

    # ---- Git -----------------------------------------------------------------
    Invoke-WithAIRetry -StepName "Verificar Git" -Action {
        $gitCmd = Get-Command git -ErrorAction SilentlyContinue
        if (-not $gitCmd) {
            throw "Git não encontrado. Tentando instalar via winget..."
        }
        Write-Log "Git encontrado: $(git --version 2>&1)" -Level "SUCCESS"
    } -ErrorContext "O comando 'git' não foi encontrado. Tente instalar o Git manualmente ou verifique se ele está no PATH."

    # ---- make ----------------------------------------------------------------
    Invoke-WithAIRetry -StepName "Verificar make" -Action {
        $makeCmd = Get-Command make -ErrorAction SilentlyContinue
        if (-not $makeCmd) {
            throw "make não encontrado. Tentando instalar..."
        }
        try {
            $mv = make --version 2>&1 | Select-Object -First 1
            Write-Log "make encontrado: $mv" -Level "SUCCESS"
        } catch {
            Write-Log "make encontrado." -Level "SUCCESS"
        }
    } -ErrorContext "O comando 'make' não foi encontrado. O 'make' é necessário para construir o projeto. Tente instalá-lo via winget (GnuWin32.Make) ou Chocolatey."
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
            Write-Log "Porta $($svc.Port) já em uso por: $($usedPorts[$svc.Port])" -Level "WARN"
        } else {
            Write-Log "Porta $($svc.Port) disponível." -Level "SUCCESS"
        }
    }

    Write-Log "Containers Docker em execução:" -Level "INFO"
    $containers = docker ps --format "  {{.Names}} | {{.Image}} | {{.Ports}}" 2>$null
    if ($LASTEXITCODE -eq 0 -and $containers) {
        $containers | ForEach-Object { Write-Log $_ -Level "INFO" }
    } else {
        Write-Log "Nenhum container rodando no momento." -Level "INFO"
    }
}

# =============================================================================
# ETAPA 3 -- Clonar repositorio via SSH
# =============================================================================

function Invoke-CloneRepo {
    $cloneUrl = $CONFIG.RepoUrl   # sempre SSH

    Invoke-WithAIRetry -StepName "Clonar Repositório Evo CRM" -Action {
        if (Test-Path "$($CONFIG.InstallPath)\.git") {
            Write-Log "Repositório já existe. Atualizando submódulos..." -Level "INFO"

            $proc = Start-Process "git" `
                -ArgumentList "submodule update --init --recursive" `
                -WorkingDirectory $CONFIG.InstallPath `
                -Wait -PassThru -NoNewWindow `
                -RedirectStandardOutput "$($CONFIG.LogFolder)\submodule-stdout.log" `
                -RedirectStandardError  "$($CONFIG.LogFolder)\submodule-stderr.log"

            if ($proc.ExitCode -ne 0) {
                $errLog = Get-Content "$($CONFIG.LogFolder)\submodule-stderr.log" -Raw -ErrorAction SilentlyContinue
                throw "Falha ao atualizar submódulos: $errLog"
            }
            Write-Log "Submódulos atualizados com sucesso." -Level "SUCCESS"
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

        if ($proc.ExitCode -ne 0) {
            $errLog = Get-Content $gitLog -Raw -ErrorAction SilentlyContinue
            throw "Clone do repositório falhou: $errLog"
        }
        Write-Log "Clone concluído com sucesso." -Level "SUCCESS"
        Set-Location $CONFIG.InstallPath
    } -ErrorContext "Ocorreu um erro durante o clone do repositório Git via SSH ou na atualização dos submódulos. Verifique a conectividade SSH com o GitHub e as permissões do repositório."
}

# =============================================================================
# ETAPA 4 -- Configurar .env
# =============================================================================

function Initialize-EnvFile {
    Set-Location $CONFIG.InstallPath

    Invoke-WithAIRetry -StepName "Configurar .env" -Action {
        if (-not (Test-Path ".env")) {
            if (Test-Path ".env.example") {
                Copy-Item ".env.example" ".env"
                Write-Log ".env criado a partir do .env.example." -Level "SUCCESS"
            } else {
                throw "O arquivo .env.example não foi encontrado. O repositório pode ter sido clonado de forma incompleta."
            }
        } else {
            Write-Log ".env já existe, mantendo configurações atuais." -Level "INFO"
        }
        Write-Log "Banco de dados: Docker interno (Opção A - padrão)." -Level "INFO"
        Write-Log ".env configurado." -Level "SUCCESS"
    } -ErrorContext "Falha ao inicializar o arquivo .env. Verifique se o .env.example existe e se há permissões de escrita na pasta de instalação."
}

# =============================================================================
# ETAPA 5 -- Executar make setup
# =============================================================================

function Invoke-MakeSetup {
    Set-Location $CONFIG.InstallPath

    Invoke-WithAIRetry -StepName "Executar make setup" -Action {
        $makeCmd = Get-Command make -ErrorAction SilentlyContinue
        if (-not $makeCmd) {
            throw "make não encontrado. Não é possível executar 'make setup' sem ele."
        }

        Write-Log "Iniciando 'make setup' (pode levar 15-20 min na primeira execução)..." -Level "INFO"
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
                throw "Timeout atingido durante 'make setup'."
            }
            if (Test-Path "$($CONFIG.LogFolder)\make-setup-stdout.log") {
                $lastLines = Get-Content "$($CONFIG.LogFolder)\make-setup-stdout.log" -Tail 3 -ErrorAction SilentlyContinue
                if ($lastLines) { $lastLines | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray } }
            }
            Start-Sleep -Seconds 5
        }

        if ($process.ExitCode -ne 0) {
            $stdErr = if (Test-Path "$($CONFIG.LogFolder)\make-setup-stderr.log") {
                Get-Content "$($CONFIG.LogFolder)\make-setup-stderr.log" -Raw -ErrorAction SilentlyContinue
            } else { "" }
            $stdOut = if (Test-Path "$($CONFIG.LogFolder)\make-setup-stdout.log") {
                Get-Content "$($CONFIG.LogFolder)\make-setup-stdout.log" -Tail 50 -ErrorAction SilentlyContinue | Out-String
            } else { "" }
            throw "make setup falhou (código $($process.ExitCode)). STDOUT: $stdOut STDERR: $stdErr"
        }
        Write-Log "make setup concluído com sucesso!" -Level "SUCCESS"
    } -ErrorContext "O comando 'make setup' falhou. Verifique os logs para mais detalhes sobre o erro de compilação ou configuração."
}

# =============================================================================
# ETAPA 6 -- Health check dos servicos
# =============================================================================

function Wait-ServicesReady {
    Write-Log "Aguardando serviços ficarem disponíveis..." -Level "INFO"

    $allReady   = $false
    $attempt    = 0
    $failedSvcs = @()

    Invoke-WithAIRetry -StepName "Health Check dos Serviços" -Action {
        $allReady = $false
        $failedSvcs = @()
        $currentAttempt = 0

        while ($currentAttempt -lt $CONFIG.MaxHealthRetries) {
            $currentAttempt++
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
                    Write-Log "$($svc.Name) -> não respondeu ainda..." -Level "INFO"
                }
            }

            if ($failedSvcs.Count -eq 0) {
                $allReady = $true
                break
            } elseif ($currentAttempt -lt $CONFIG.MaxHealthRetries) {
                Write-Log "Tentativa $currentAttempt/$($CONFIG.MaxHealthRetries) -- $($failedSvcs.Count) serviço(s) subindo. Aguardando $($CONFIG.HealthRetryDelay)s..." -Level "INFO"
                Start-Sleep -Seconds $CONFIG.HealthRetryDelay
            }
        }

        if (-not $allReady) {
            $errorDetails = "Os seguintes serviços não responderam ou retornaram erro após $($CONFIG.MaxHealthRetries) tentativas: "
            foreach ($svc in $failedSvcs) {
                $containerLogs = docker logs $svc.Name 2>&1 | Select-Object -Last 30 | Out-String
                $errorDetails += "`n- $($svc.Name) ($($svc.Url)). Logs do container: `n$containerLogs`n"
            }
            throw $errorDetails
        }
        Write-Log "Todos os serviços estão ativos." -Level "SUCCESS"
    } -ErrorContext "Alguns serviços do Evo CRM não iniciaram corretamente. Verifique os logs dos containers para identificar a causa."

    return $allReady
}

# =============================================================================
# ETAPA 7 -- Resumo final
# =============================================================================

function Write-FinalSummary {
    param([bool]$AllReady)

    Write-Host ""
    Write-Host "  =============================================" -ForegroundColor DarkGreen
    Write-Host "  EVO CRM -- RESULTADO DA INSTALAÇÃO" -ForegroundColor White
    Write-Host "  =============================================" -ForegroundColor DarkGreen
    Write-Host ""

    if ($AllReady) {
        Write-Host "  OK  Todos os serviços estão rodando!" -ForegroundColor Green
        Write-Host ""
        Write-Host "  Acesse agora:" -ForegroundColor White
        Write-Host "  -> Frontend  : http://localhost:5173" -ForegroundColor Cyan
        Write-Host "  -> CRM API   : http://localhost:3000" -ForegroundColor Cyan
        Write-Host "  -> Auth API  : http://localhost:3001" -ForegroundColor Cyan
        Write-Host "  -> Processor : http://localhost:8000" -ForegroundColor Cyan
        Write-Host "  -> Core API  : http://localhost:5555" -ForegroundColor Cyan
        Write-Host "  -> Mailhog   : http://localhost:8025" -ForegroundColor Cyan
    } else {
        Write-Host "  !  Instalação concluída com alertas." -ForegroundColor Yellow
        Write-Host "     Alguns serviços podem ainda estar iniciando." -ForegroundColor Yellow
        Write-Host "     Aguarde alguns minutos e acesse: http://localhost:5173" -ForegroundColor Yellow
    }

    Write-Host ""
    Write-Host "  Comandos úteis (na pasta $($CONFIG.InstallPath)):" -ForegroundColor White
    Write-Host "    make start   -- liga todos os serviços" -ForegroundColor Gray
    Write-Host "    make stop    -- desliga todos os serviços" -ForegroundColor Gray
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

    # Etapa 1a: SSH — OBRIGATÓRIO primeiro (submódulos usam SSH hardcoded)
    Write-Log "Configurando autenticação SSH com o GitHub..." -Level "STEP"
    Assert-SSHKey

    # Etapa 1b: Docker + Git + make
    Write-Log "Verificando pré-requisitos..." -Level "STEP"
    Assert-Prerequisites

    # Etapa 2: Scan de portas/containers
    Write-Log "Escaneando ambiente..." -Level "STEP"
    Get-EnvironmentSnapshot

    # Etapa 3: Clone via SSH (submódulos incluídos)
    Write-Log "Clonando repositório do Evo CRM..." -Level "STEP"
    Invoke-CloneRepo

    # Etapa 4: .env
    Write-Log "Configurando arquivo .env..." -Level "STEP"
    Initialize-EnvFile

    # Etapa 5: make setup
    Write-Log "Executando make setup..." -Level "STEP"
    Invoke-MakeSetup

    # Etapa 6: Health check
    Write-Log "Verificando saúde dos serviços..." -Level "STEP"
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
