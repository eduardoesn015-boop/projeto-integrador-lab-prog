import os
import sys
import socket
import subprocess
import ctypes
import smtplib


# =====================================================
# VERIFICAR E SOLICITAR PERMISSAO DE ADMINISTRADOR
# =====================================================

def verificar_administrador():
    try:
        if ctypes.windll.shell32.IsUserAnAdmin():
            return True

        print("Solicitando permissao de Administrador...")

        script = os.path.abspath(sys.argv[0])
        parametros = subprocess.list2cmdline([script] + sys.argv[1:])

        resultado = ctypes.windll.shell32.ShellExecuteW(
            None,
            "runas",
            sys.executable,
            parametros,
            None,
            1
        )

        if resultado <= 32:
            input("\nNao foi possivel obter permissao de Administrador.")
            return False

        sys.exit(0)

    except Exception as erro:
        print(f"Erro ao solicitar Administrador: {erro}")
        input("\nPressione ENTER para sair...")
        return False


# =====================================================
# FUNCOES DO PROGRAMA
# =====================================================

def limpar_tela():
    os.system('cls' if os.name == 'nt' else 'clear')


def exibir_dados_rede():
    print("\n--- DADOS PARA CONFIGURAR NA IMPRESSORA ---")

    try:
        nome_pc = socket.gethostname()

        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip_local = s.getsockname()[0]
        s.close()

        print(f"Nome do Computador (Host): {nome_pc}")
        print(f"Endereco IP Local:         {ip_local}")
        print(f"Caminho de rede padrao:    \\\\{nome_pc}\\Scan")
        print(f"                           \\\\{ip_local}\\Scan")

    except Exception as erro:
        print(f"Erro ao obter dados de rede: {erro}")

    input("\nPressione ENTER para voltar ao menu...")


def verificar_portas_smb():
    print("\n--- DIAGNOSTICO DE PORTAS SMB (REDE) ---")

    alvo = input("Digite o IP ou hostname para testar: ").strip()

    if not alvo:
        alvo = "127.0.0.1"

    portas = {
        445: "SMB (Compartilhamento de Pastas Windows)",
        139: "NetBIOS / SMB Legado"
    }

    print(f"\nTestando portas SMB em: {alvo}...\n")

    for porta, descricao in portas.items():
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(2)

        resultado = sock.connect_ex((alvo, porta))

        if resultado == 0:
            print(f"[OK - ABERTA]   Porta {porta} - {descricao}")
        else:
            print(f"[X - FECHADA]   Porta {porta} - {descricao}")

        sock.close()

    input("\nPressione ENTER para voltar ao menu...")


def testar_portas_smtp():
    print("\n--- DIAGNOSTICO DE PORTAS SMTP (E-MAIL) ---")
    alvo = input("Digite o servidor SMTP (ex: smtp.gmail.com ou IP): ").strip()

    if not alvo:
        print("[ERRO] Servidor nao pode estar vazio.")
        input("\nPressione ENTER para voltar...")
        return

    portas = {
        25:  "SMTP Direto / Legado (Comum em bloqueios de ISP)",
        587: "SMTP com TLS (Padrão para autenticação)",
        465: "SMTP com SSL (Criptografia direta)"
    }

    print(f"\nTestando portas SMTP em: {alvo}...\n")

    for porta, descricao in portas.items():
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(3)

        resultado = sock.connect_ex((alvo, porta))

        if resultado == 0:
            print(f"[OK - ABERTA]   Porta {porta} - {descricao}")
        else:
            print(f"[X - FECHADA]   Porta {porta} - {descricao}")

        sock.close()

    input("\nPressione ENTER para voltar ao menu...")


def criar_atalho_desktop(caminho_alvo, nome_atalho):
    try:
        # Descobre o caminho da Area de Trabalho do usuario atual
        desktop = os.path.join(os.path.expanduser("~"), "Desktop")
        caminho_lnk = os.path.join(desktop, f"{nome_atalho}.lnk")

        # Comando PowerShell nativo para criar o atalho (.lnk)
        comando_ps = (
            f"$ws = New-Object -ComObject WScript.Shell; "
            f"$sc = $ws.CreateShortcut('{caminho_lnk}'); "
            f"$sc.TargetPath = '{caminho_alvo}'; "
            f"$sc.Save()"
        )

        resultado = subprocess.run(["powershell", "-Command", comando_ps], capture_output=True, text=True)
        if resultado.returncode == 0:
            print(f"[OK] Atalho criado na Area de Trabalho com sucesso!")
        else:
            print(f"[AVISO] Nao foi possivel criar o atalho automaticamente.")
    except Exception as e:
        print(f"[AVISO] Erro ao criar atalho: {e}")


def criar_pasta_e_desbloquear_rede():
    print("\n--- CRIAR PASTA, COMPARTILHAR E ATIVAR DESCOBERTA DE REDE ---")

    caminho = input(
        "Digite o caminho da pasta (vazio para C:\\Scan): "
    ).strip()

    if not caminho:
        caminho = "C:\\Scan"

    nome_compartilhamento = input(
        "Nome na rede (vazio para Scan): "
    ).strip()

    if not nome_compartilhamento:
        nome_compartilhamento = "Scan"

    try:
        # 1. Cria a pasta fisica
        if not os.path.exists(caminho):
            os.makedirs(caminho)
            print(f"[OK] Pasta criada em: {caminho}")
        else:
            print(f"[AVISO] A pasta {caminho} ja existe.")

        # 2. Compartilha via comando net share
        comando_share = [
            "net",
            "share",
            f"{nome_compartilhamento}={caminho}",
            "/GRANT:Todos,FULL"
        ]
        processo_share = subprocess.run(
            comando_share,
            capture_output=True,
            text=True
        )

        if processo_share.returncode == 0:
            print(f"[OK] Pasta compartilhada na rede como '{nome_compartilhamento}'!")
        else:
            print("[ERRO] Falha ao compartilhar pasta.")
            print(f"Detalhe: {processo_share.stderr.strip()}")

        # 3. Ativa Descoberta de Rede e Compartilhamento no Firewall do Windows
        print("\nAtivando Descoberta de Rede e Compartilhamento no Firewall...")
        
        regras_firewall = [
            'netsh advfirewall firewall set rule group="File and Printer Sharing" new enable=Yes',
            'netsh advfirewall firewall set rule group="Network Discovery" new enable=Yes'
        ]

        for regra in regras_firewall:
            subprocess.run(regra, shell=True, capture_output=True, text=True)

        print("[OK] Regras de Firewall ajustadas com sucesso!")

        # 4. Pergunta se deseja criar o atalho na Área de Trabalho
        pergunta = input("\nDeseja criar um atalho desta pasta na Area de Trabalho? (s/n): ").strip().lower()
        if pergunta in ['s', 'sim', 'y', 'yes']:
            criar_atalho_desktop(caminho, f"Pasta {nome_compartilhamento}")

        print("\n[SUCESSO] Processo concluido!")

    except Exception as erro:
        print(f"Erro inesperado: {erro}")

    input("\nPressione ENTER para voltar ao menu...")


# =====================================================
# MENU PRINCIPAL
# =====================================================

def menu_principal():
    while True:
        limpar_tela()

        print("=====================================================")
        print("        ASSISTENTE DE DIAGNOSTICO SCAN-TO-FOLDER     ")
        print("=====================================================")
        print("  EXECUTANDO COMO ADMINISTRADOR")
        print("=====================================================")
        print("1 - Exibir Dados de Rede (IP e Nome do PC)")
        print("2 - Testar Portas de Rede SMB (445 e 139)")
        print("3 - Testar Portas SMTP (25, 587 e 465)")
        print("4 - Criar Pasta, Compartilhar e Ativar Descoberta de Rede")
        print("0 - Sair")
        print("=====================================================")

        opcao = input("Escolha uma opcao: ").strip()

        if opcao == "1":
            exibir_dados_rede()

        elif opcao == "2":
            verificar_portas_smb()

        elif opcao == "3":
            testar_portas_smtp()

        elif opcao == "4":
            criar_pasta_e_desbloquear_rede()

        elif opcao == "0":
            print("\nEncerrando o assistente...")
            break

        else:
            input("\nOpcao invalida! Pressione ENTER para tentar novamente...")


# =====================================================
# INICIALIZACAO
# =====================================================

if __name__ == "__main__":
    if verificar_administrador():
        menu_principal()