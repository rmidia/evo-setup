# Exigir privilégios de Administrador
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "Execute este script como Administrador para garantir a limpeza total."
    exit
}

$ErrorActionPreference = "SilentlyContinue"

function Remove-From-Path {
    param([string]$term)
    $path = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $newPath = ($path -split ';' | Where-Object { $_ -notmatch $term }) -join ';'
    [Environment]::SetEnvironmentVariable("Path", $newPath, "Machine")
    
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $newUserPath = ($userPath -split ';' | Where-Object { $_ -notmatch $term }) -join ';'
    [Environment]::SetEnvironmentVariable("Path", $newUserPath, "User")
}

Write-Host "--- INICIANDO LIMPEZA PROFUNDA ---" -ForegroundColor Cyan

# 1. DOCKER & CONTAINERS
Write-Host "> Removendo Docker..." -ForegroundColor Yellow
Stop-Process -Name "Docker Desktop" -Force
Stop-Service -Name "com.docker.service"
& winget uninstall "Docker.DockerDesktop" --silent
& wsl --unregister docker-desktop
& wsl --unregister docker-desktop-data
Remove-Item -Path "$env:ProgramFiles\Docker", "$env:AppData\Docker", "$env:LocalAppData\Docker", "$env:UserProfile\.docker" -Recurse -Force
Remove-From-Path "Docker"

# 2. GIT
Write-Host "> Removendo Git..." -ForegroundColor Yellow
& winget uninstall "Git.Git" --silent
Remove-Item -Path "$env:ProgramFiles\Git", "$env:UserProfile\.gitconfig", "$env:UserProfile\.git-credentials" -Recurse -Force
Remove-From-Path "Git"

# 3. PYTHON
Write-Host "> Removendo Python e PIP..." -ForegroundColor Yellow
$pyApps = Get-Package -Name "*Python*"
foreach ($app in $pyApps) { Uninstall-Package -InputObject $app -Force }
Remove-Item -Path "$env:LocalAppData\Programs\Python", "$env:AppData\Python" -Recurse -Force
Remove-From-Path "Python"

# 4. NODE.JS & NPM
Write-Host "> Removendo Node.js e ferramentas..." -ForegroundColor Yellow
& winget uninstall "OpenJS.NodeJS" --silent
Stop-Process -Name "node" -Force
Remove-Item -Path "$env:ProgramFiles\nodejs", "$env:AppData\npm", "$env:AppData\npm-cache", "$env:UserProfile\.npmrc" -Recurse -Force
Remove-From-Path "node"

# 5. WSL2 & MAKE
Write-Host "> Removendo WSL2, Distribuições e Make..." -ForegroundColor Yellow
# Remove distros remanescentes
$distros = wsl --list --quiet
foreach ($d in $distros) { if ($d) { wsl --unregister $d } }

# Desativa recursos do Windows
Disable-WindowsOptionalFeature -Online -FeatureName "Microsoft-Windows-Subsystem-Linux" -NoRestart
Disable-WindowsOptionalFeature -Online -FeatureName "VirtualMachinePlatform" -NoRestart

# Remove binários do Make (comumente instalados via Choco ou manual)
Remove-Item -Path "C:\Program Files\bin\make.exe", "C:\make" -Recurse -Force
Remove-From-Path "make"

Write-Host "---"
Write-Host "LIMPEZA CONCLUÍDA!" -ForegroundColor Green
Write-Host "IMPORTANTE: Reinicie o Windows para que as alterações de PATH e Recursos do Windows tenham efeito antes de testar seu script de instalação." -ForegroundColor White -BackgroundColor Red
