# =====================================================
# VERIFICAR E SOLICITAR PERMISSAO DE ADMINISTRADOR
# =====================================================
function Verificar-Administrador {
    $identidade = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identidade)
    $ehAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    if ($ehAdmin) {
        return $true
    }

    Write-Host "Solicitando permissao de Administrador..." -ForegroundColor Yellow
    try {
        Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
        exit
    } catch {
        Read-Host "`nNao foi possivel obter permissao de Administrador. Pressione ENTER para sair"
        return $false
    }
}

# =====================================================
# FUNCOES DO PROGRAMA
# =====================================================

function Exibir-DadosRede {
    Write-Host "`n--- DADOS PARA CONFIGURAR NA IMPRESSORA ---" -ForegroundColor Cyan
    try {
        $nomePC = $env:COMPUTERNAME
        $ipLocal = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object {
            $_.InterfaceAlias -notmatch "Loopback" -and $_.IPAddress -notlike "169.254.*"
        } | Select-Object -First 1).IPAddress

        if (-not $ipLocal) { $ipLocal = "Nao identificado" }

        Write-Host "Nome do Computador (Host): $nomePC"
        Write-Host "Endereco IP Local:         $ipLocal"
        Write-Host "Caminho de rede padrao:    \\$nomePC\Scan"
        Write-Host "                           \\$ipLocal\Scan"
    } catch {
        Write-Host "Erro ao obter dados de rede: $_" -ForegroundColor Red
    }

    Read-Host "`nPressione ENTER para voltar ao menu"
}

function Verificar-PortasSMB {
    Write-Host "`n--- DIAGNOSTICO DE PORTAS SMB (REDE) ---" -ForegroundColor Cyan
    $alvo = (Read-Host "Digite o IP ou hostname para testar (vazio para 127.0.0.1)").Trim()
    if ([string]::IsNullOrWhiteSpace($alvo)) { $alvo = "127.0.0.1" }

    $portas = [ordered]@{
        445 = "SMB (Compartilhamento de Pastas Windows)"
        139 = "NetBIOS / SMB Legado"
    }

    Write-Host "`nTestando portas SMB em: $alvo...`n"

    foreach ($item in $portas.GetEnumerator()) {
        $porta = $item.Key
        $descricao = $item.Value
        $tcp = New-Object System.Net.Sockets.TcpClient
        $conexao = $tcp.BeginConnect($alvo, $porta, $null, $null)
        $espera = $conexao.AsyncWaitHandle.WaitOne(2000, $false)

        if ($espera -and $tcp.Connected) {
            Write-Host "[OK - ABERTA]   Porta $porta - $descricao" -ForegroundColor Green
        } else {
            Write-Host "[X - FECHADA]   Porta $porta - $descricao" -ForegroundColor Red
        }
        $tcp.Close()
    }

    Read-Host "`nPressione ENTER para voltar ao menu"
}

function Testar-PortasSMTP {
    Write-Host "`n--- DIAGNOSTICO DE PORTAS SMTP (E-MAIL) ---" -ForegroundColor Cyan
    $alvo = (Read-Host "Digite o servidor SMTP (ex: smtp.gmail.com ou IP)").Trim()

    if ([string]::IsNullOrWhiteSpace($alvo)) {
        Write-Host "[ERRO] Servidor nao pode estar vazio." -ForegroundColor Red
        Read-Host "`nPressione ENTER para voltar"
        return
    }

    $portas = [ordered]@{
        25  = "SMTP Direto / Legado (Comum em bloqueios de ISP)"
        587 = "SMTP com TLS (Padrao para autenticacao)"
        465 = "SMTP com SSL (Criptografia direta)"
    }

    Write-Host "`nTestando portas SMTP em: $alvo...`n"

    foreach ($item in $portas.GetEnumerator()) {
        $porta = $item.Key
        $descricao = $item.Value
        $tcp = New-Object System.Net.Sockets.TcpClient
        $conexao = $tcp.BeginConnect($alvo, $porta, $null, $null)
        $espera = $conexao.AsyncWaitHandle.WaitOne(3000, $false)

        if ($espera -and $tcp.Connected) {
            Write-Host "[OK - ABERTA]   Porta $porta - $descricao" -ForegroundColor Green
        } else {
            Write-Host "[X - FECHADA]   Porta $porta - $descricao" -ForegroundColor Red
        }
        $tcp.Close()
    }

    Read-Host "`nPressione ENTER para voltar ao menu"
}

function Criar-AtalhoDesktop {
    param([string]$CaminhoAlvo, [string]$NomeAtalho)
    try {
        $desktop = [Environment]::GetFolderPath("Desktop")
        $caminhoLnk = Join-Path $desktop "$NomeAtalho.lnk"

        $ws = New-Object -ComObject WScript.Shell
        $sc = $ws.CreateShortcut($caminhoLnk)
        $sc.TargetPath = $CaminhoAlvo
        $sc.Save()

        Write-Host "[OK] Atalho criado na Area de Trabalho com sucesso!" -ForegroundColor Green
    } catch {
        Write-Host "[AVISO] Nao foi possivel criar o atalho automaticamente: $_" -ForegroundColor Yellow
    }
}

function Criar-PastaEDesbloquearRede {
    Write-Host "`n--- CRIAR PASTA, COMPARTILHAR E ATIVAR DESCOBERTA DE REDE ---" -ForegroundColor Cyan

    $caminho = (Read-Host "Digite o caminho da pasta (vazio para C:\Scan)").Trim()
    if ([string]::IsNullOrWhiteSpace($caminho)) { $caminho = "C:\Scan" }

    $nomeCompartilhamento = (Read-Host "Nome na rede (vazio para Scan)").Trim()
    if ([string]::IsNullOrWhiteSpace($nomeCompartilhamento)) { $nomeCompartilhamento = "Scan" }

    try {
        # 1. Cria a pasta fisica
        if (-not (Test-Path -Path $caminho)) {
            New-Item -ItemType Directory -Path $caminho -Force | Out-Null
            Write-Host "[OK] Pasta criada em: $caminho" -ForegroundColor Green
        } else {
            Write-Host "[AVISO] A pasta $caminho ja existe." -ForegroundColor Yellow
        }

        # 2. Compartilha via comando net share (mantendo compatibilidade total)
        $saidaShare = net share "$nomeCompartilhamento=$caminho" /GRANT:Todos,FULL 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "[OK] Pasta compartilhada na rede como '$nomeCompartilhamento'!" -ForegroundColor Green
        } else {
            Write-Host "[ERRO] Falha ao compartilhar pasta." -ForegroundColor Red
            Write-Host "Detalhe: $saidaShare"
        }

        # 3. Ativa Descoberta de Rede e Compartilhamento no Firewall do Windows
        Write-Host "`nAtivando Descoberta de Rede e Compartilhamento no Firewall..."
        netsh advfirewall firewall set rule group="File and Printer Sharing" new enable=Yes | Out-Null
        netsh advfirewall firewall set rule group="Network Discovery" new enable=Yes | Out-Null
        Write-Host "[OK] Regras de Firewall ajustadas com sucesso!" -ForegroundColor Green

        # 4. Pergunta se deseja criar o atalho na Area de Trabalho
        $pergunta = (Read-Host "`nDeseja criar um atalho desta pasta na Area de Trabalho? (s/n)").Trim().ToLower()
        if ($pergunta -in @("s", "sim", "y", "yes")) {
            Criar-AtalhoDesktop -CaminhoAlvo $caminho -NomeAtalho "Pasta $nomeCompartilhamento"
        }

        Write-Host "`n[SUCESSO] Processo concluido!" -ForegroundColor Green
    } catch {
        Write-Host "Erro inesperado: $_" -ForegroundColor Red
    }

    Read-Host "`nPressione ENTER para voltar ao menu"
}

# =====================================================
# MENU PRINCIPAL
# =====================================================

function Menu-Principal {
    while ($true) {
        Clear-Host
        Write-Host "=====================================================" -ForegroundColor Cyan
        Write-Host "        ASSISTENTE DE DIAGNOSTICO SCAN-TO-FOLDER     " -ForegroundColor Cyan
        Write-Host "=====================================================" -ForegroundColor Cyan
        Write-Host "  EXECUTANDO COMO ADMINISTRADOR" -ForegroundColor Green
        Write-Host "====================================================="
        Write-Host "1 - Exibir Dados de Rede (IP e Nome do PC)"
        Write-Host "2 - Testar Portas de Rede SMB (445 e 139)"
        Write-Host "3 - Testar Portas SMTP (25, 587 e 465)"
        Write-Host "4 - Criar Pasta, Compartilhar e Ativar Descoberta de Rede"
        Write-Host "0 - Sair"
        Write-Host "====================================================="

        $opcao = (Read-Host "Escolha uma opcao").Trim()

        switch ($opcao) {
            "1" { Exibir-DadosRede }
            "2" { Verificar-PortasSMB }
            "3" { Testar-PortasSMTP }
            "4" { Criar-PastaEDesbloquearRede }
            "0" {
                Write-Host "`nEncerrando o assistente..."
                return
            }
            default {
                Read-Host "`nOpcao invalida! Pressione ENTER para tentar novamente"
            }
        }
    }
}

# =====================================================
# INICIALIZACAO
# =====================================================
if (Verificar-Administrador) {
    Menu-Principal
}