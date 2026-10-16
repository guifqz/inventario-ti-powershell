# Dados ficticios no formato de saida de Invoke-InventarioRede (ja mesclados com o AD).
# Usado por tools/Gerar-Exemplo.ps1 (docs/) e pelos testes. Nenhum dado real; dominio contoso.local.
# Data de referencia dos exemplos: 2026-10-16.

function Get-DiscoExemplo {
    param(
        [string]$Unidade = 'C:',
        [double]$TamanhoGB,
        [double]$LivreGB,
        [string]$Tipo = 'SSD',
        [string]$Saude = 'Healthy',
        [bool]$Sistema = ($Unidade -eq 'C:')
    )

    [pscustomobject]@{
        Unidade         = $Unidade
        Rotulo          = if ($Sistema) { 'Sistema' } else { 'Dados' }
        TamanhoGB       = $TamanhoGB
        LivreGB         = $LivreGB
        PercentualLivre = [math]::Round(($LivreGB / $TamanhoGB) * 100, 1)
        Tipo            = $Tipo
        Saude           = $Saude
        Sistema         = $Sistema
    }
}

function Get-AntivirusExemplo {
    param([bool]$Ativo = $true, [bool]$Atualizado = $true, [string]$Nome = 'Windows Defender')
    , @([pscustomobject]@{ Nome = $Nome; Ativo = $Ativo; Atualizado = $Atualizado })
}

function Get-MaquinaExemplo {
    param(
        [Parameter(Mandatory)][string]$ComputerName,
        [string]$Status = 'Coletado',
        [string]$Erro,
        [string]$Usuario,
        [string]$Fabricante = 'Dell Inc.',
        [string]$Modelo = 'OptiPlex 3080',
        [string]$CPU = 'Intel(R) Core(TM) i5-10500 CPU @ 3.10GHz',
        [double]$RAMGB = 16,
        [int]$Slots = 4,
        [int]$SlotsUsados = 2,
        [string]$RAMTipo = 'DDR4',
        [object[]]$Discos = @(),
        [string]$SO = 'Microsoft Windows 11 Pro',
        [string]$Build = '22631',
        [string]$IP,
        [int]$QtdSoftware = 0,
        [string]$Fonte = 'Remoto',
        [string]$Protocolo = 'WinRM',
        [double]$IdadeDias = 0.1,
        [double]$UptimeDias = 3,
        [string]$Ativacao = 'Ativado',
        [object]$Antivirus = (Get-AntivirusExemplo),
        [string]$Office = 'Microsoft 365 Apps for enterprise - pt-br',
        [string[]]$AcessoRemoto = @(),
        [bool]$RebootPendente = $false,
        [string]$Setor = 'Estacoes',
        [string]$Descricao,
        [object]$LogonAD = [datetime]'2026-10-15T18:02:00',
        [string]$SOAD,
        [int]$Monitores = 1,
        [bool]$NoAD = $true
    )

    $coletado = $Status -eq 'Coletado'
    $mensagens = @{
        Coletado        = if ($Fonte -eq 'Local') { 'Dados do coletor local, coletados há {0:N0} dia(s).' -f $IdadeDias } else { 'Coleta concluída.' }
        Offline         = 'Não respondeu a ping nem às portas 135, 445 e 5985. Confirme se está ligado e na rede; se foi descartado, remova do AD.'
        AcessoNegado    = 'Acesso negado. Execute com uma conta administradora das estações (ex.: Admins do Domínio) ou informe -Credential.'
        SemWinRMeDcom   = 'WinRM e DCOM indisponíveis (servidor RPC não disponível). Habilite WinRM via GPO ou libere a regra de firewall "Instrumentação de Gerenciamento do Windows (WMI-In)"; alternativa: coletor local por GPO de inicialização.'
        Erro            = "Falha na coleta: $Erro"
        NaoInventariado = 'Consta no AD, mas nenhuma coleta trouxe dados.'
    }
    $coletadoEm = [datetime]'2026-10-16T08:30:00'
    if ($coletado) { $coletadoEm = $coletadoEm.AddDays(-$IdadeDias) }

    $software = foreach ($i in 1..$QtdSoftware) {
        [pscustomobject]@{ Nome = "Aplicativo exemplo $i"; Versao = "1.$i.0"; Fabricante = 'Fornecedor Exemplo'; Arquitetura = 'x64' }
    }
    if ($coletado -and $QtdSoftware -gt 0 -and $Office) {
        $software = @($software) + [pscustomobject]@{ Nome = $Office; Versao = '16.0.17928'; Fabricante = 'Microsoft Corporation'; Arquitetura = 'x64' }
    }
    foreach ($ferramenta in $AcessoRemoto) {
        $software = @($software) + [pscustomobject]@{ Nome = $ferramenta; Versao = '8.0'; Fabricante = $ferramenta; Arquitetura = 'x86' }
    }

    $hash = ([int[]][char[]]$ComputerName | Measure-Object -Sum).Sum
    $mac = '00:50:56:AA:{0:X2}:{1:X2}' -f [int]($hash % 256), [int](($hash * 7) % 256)
    $adaptadores = if ($coletado -and $IP) {
        , @([pscustomobject]@{ Nome = 'Intel(R) Ethernet Connection'; IP = $IP; MAC = $mac; DHCP = $true; Gateway = ($IP -replace '\.\d+$', '.1') })
    }
    else { @() }
    $nomesMonitor = @(
        @{ Fabricante = 'Dell'; Modelo = 'P2422H' }
        @{ Fabricante = 'LG'; Modelo = '24MK430H' }
        @{ Fabricante = 'Samsung'; Modelo = 'S24R350' }
    )
    $listaMonitores = @(for ($i = 0; $i -lt $Monitores; $i++) {
            $n = $nomesMonitor[($hash + $i) % 3]
            [pscustomobject]@{ Fabricante = $n.Fabricante; Modelo = $n.Modelo; Serial = 'MN{0:X6}' -f [int](($hash * 131 + $i * 17) -band 0xFFFFFF) }
        })

    $registro = [pscustomobject]@{
        PSTypeName           = 'InventarioTI.Maquina'
        ComputerName         = $ComputerName
        Online               = $coletado
        Erro                 = $Erro
        StatusColeta         = $Status
        Mensagem             = $mensagens[$Status]
        ProtocoloUsado       = if ($coletado) { if ($Fonte -eq 'Local') { 'Local' } else { $Protocolo } } else { $null }
        Fonte                = $Fonte
        IdadeDadosDias       = if ($coletado) { $IdadeDias } else { $null }
        Hostname             = if ($coletado) { $ComputerName } else { $null }
        Usuario              = $Usuario
        Fabricante           = if ($coletado) { $Fabricante } else { $null }
        Modelo               = if ($coletado) { $Modelo } else { $null }
        Serial               = if ($coletado) { 'SN' + ([int](($hash * 7919) -band 0xFFFFFF)).ToString('X6') } else { $null }
        BiosVersao           = if ($coletado) { '1.' + ($hash % 20) + '.0' } else { $null }
        BiosData             = if ($coletado) { [datetime]'2022-05-10' } else { $null }
        CPU                  = if ($coletado) { $CPU } else { $null }
        CPUNucleos           = if ($coletado) { 6 } else { $null }
        CPUThreads           = if ($coletado) { 12 } else { $null }
        RAMGB                = if ($coletado) { $RAMGB } else { $null }
        RAMSlotsUsados       = if ($coletado) { $SlotsUsados } else { $null }
        RAMSlotsTotal        = if ($coletado) { $Slots } else { $null }
        RAMVelocidadeMHz     = if ($coletado) { 2666 } else { $null }
        RAMTipo              = if ($coletado) { $RAMTipo } else { $null }
        Discos               = @($Discos)
        SistemaOperacional   = if ($coletado) { $SO } else { $null }
        VersaoSO             = if ($coletado) { '10.0.' + $Build } else { $null }
        BuildSO              = if ($coletado) { $Build } else { $null }
        Arquitetura          = if ($coletado) { '64-bit' } else { $null }
        InstaladoEm          = if ($coletado) { [datetime]'2023-03-14T09:20:00' } else { $null }
        UltimoBoot           = if ($coletado) { $coletadoEm.AddDays(-$UptimeDias).Date.AddHours(7.8) } else { $null }
        UptimeDias           = if ($coletado) { $UptimeDias } else { $null }
        RebootPendente       = if ($coletado) { $RebootPendente } else { $null }
        IP                   = if ($coletado) { $IP } else { $null }
        MAC                  = if ($coletado -and $IP) { $mac } else { $null }
        Adaptadores          = $adaptadores
        Ativacao             = if ($coletado) { $Ativacao } else { $null }
        Antivirus            = if ($coletado) { , $Antivirus } else { $null }
        Monitores            = if ($coletado) { , $listaMonitores } else { $null }
        Office               = if ($coletado -and $QtdSoftware -gt 0) { $Office } else { $null }
        AcessoRemoto         = @($AcessoRemoto)
        Software             = @($software)
        NoAD                 = $NoAD
        DNSHostName          = if ($NoAD) { ($ComputerName.ToLower() + '.contoso.local') } else { $null }
        SistemaOperacionalAD = if ($NoAD) { if ($SOAD) { $SOAD } else { $SO } } else { $null }
        VersaoSOAD           = if ($NoAD) { '10.0 (' + $Build + ')' } else { $null }
        UltimoLogonAD        = if ($NoAD) { $LogonAD } else { $null }
        CriadoEmAD           = if ($NoAD) { [datetime]'2023-03-10T10:00:00' } else { $null }
        DescricaoAD          = $Descricao
        OU                   = if ($NoAD) { "contoso.local/$Setor" } else { $null }
        HabilitadoAD         = if ($NoAD) { $true } else { $null }
        PossivelmenteInativo = $false
        NuncaInventariado    = ($NoAD -and -not $coletado)
        ColetadoEm           = $coletadoEm
    }

    if ($NoAD) {
        $base = if ($LogonAD) { [datetime]$LogonAD } else { $registro.CriadoEmAD }
        $registro.PossivelmenteInativo = (([datetime]'2026-10-16' - $base).TotalDays -gt 90)
    }
    $registro
}

function Get-DadosExemplo {
    $ssd = { param($t, $l) Get-DiscoExemplo -TamanhoGB $t -LivreGB $l }
    $hdd = { param($t, $l) Get-DiscoExemplo -TamanhoGB $t -LivreGB $l -Tipo 'HDD' }
    $semAV = @()
    $win10 = @{ SO = 'Microsoft Windows 10 Pro'; Build = '19045' }
    $win7 = @{ SO = 'Microsoft Windows 7 Professional'; Build = '7601' }

    @(
        Get-MaquinaExemplo -ComputerName 'PC-FINANCEIRO-01' -Usuario 'CONTOSO\ana.souza' -IP '192.0.2.11' -QtdSoftware 42 -Setor 'Financeiro' -Descricao 'Ana Souza - Contas a pagar' -Discos (& $ssd 476.3 210.4)
        Get-MaquinaExemplo -ComputerName 'PC-FINANCEIRO-02' -Usuario 'CONTOSO\carlos.lima' -IP '192.0.2.12' -QtdSoftware 38 -Setor 'Financeiro' -Discos (& $ssd 476.3 38.2) -Monitores 2
        Get-MaquinaExemplo -ComputerName 'PC-FINANCEIRO-03' -Usuario 'CONTOSO\lucia.prado' -Fabricante 'Lenovo' -Modelo 'ThinkCentre M70s' -IP '192.0.2.13' -QtdSoftware 35 -Setor 'Financeiro' -Protocolo 'DCOM' -Discos (& $ssd 476.3 301.9)
        Get-MaquinaExemplo -ComputerName 'PC-FINANCEIRO-04' -Usuario 'CONTOSO\renato.melo' -IP '192.0.2.14' -QtdSoftware 33 -Setor 'Financeiro' -Discos (& $ssd 476.3 188.0) -AcessoRemoto 'AnyDesk'
        Get-MaquinaExemplo -ComputerName 'PC-RH-01' -Usuario 'CONTOSO\marta.reis' -Modelo 'Vostro 3888' -RAMGB 8 -Slots 2 -SlotsUsados 1 -IP '192.0.2.21' -QtdSoftware 31 -Setor 'RH' @win10 -Discos (& $hdd 931.5 402.7)
        Get-MaquinaExemplo -ComputerName 'PC-RH-02' -Usuario 'CONTOSO\paulo.nunes' -Modelo 'Vostro 3888' -RAMGB 4 -Slots 2 -SlotsUsados 2 -RAMTipo 'DDR3' -IP '192.0.2.22' -QtdSoftware 27 -Setor 'RH' @win10 -Discos (& $hdd 465.8 240.0)
        Get-MaquinaExemplo -ComputerName 'PC-RECEPCAO-01' -Fabricante 'Lenovo' -Modelo 'ThinkCentre M70s' -RAMGB 4 -Slots 2 -SlotsUsados 2 -RAMTipo 'DDR3' -CPU 'Intel(R) Core(TM) i3-4130 CPU @ 3.40GHz' -IP '192.0.2.31' -QtdSoftware 19 -Setor 'Recepcao' @win7 -Protocolo 'DCOM' -Ativacao 'Notificacao' -Antivirus $semAV -Office 'Microsoft Office Professional Plus 2010' -UptimeDias 61 -Discos (& $hdd 465.8 211.0) -Monitores 1
        Get-MaquinaExemplo -ComputerName 'PC-RECEPCAO-02' -Fabricante 'HP' -Modelo 'ProDesk 400 G1' -RAMGB 4 -Slots 2 -SlotsUsados 1 -RAMTipo 'DDR3' -IP '192.0.2.32' -QtdSoftware 22 -Setor 'Recepcao' -SO 'Microsoft Windows 8.1 Pro' -Build '9600' -Protocolo 'DCOM' -Antivirus (Get-AntivirusExemplo -Ativo $false -Nome 'Antivirus Corporativo') -Office 'Microsoft Office Standard 2013' -Discos (& $hdd 465.8 300.2)
        Get-MaquinaExemplo -ComputerName 'PC-COMPRAS-01' -Usuario 'CONTOSO\paulo.dias' -Fabricante 'HP' -Modelo 'ProDesk 400 G7' -IP '192.0.2.41' -QtdSoftware 36 -Setor 'Compras' -Discos (& $ssd 238.5 21.9), (Get-DiscoExemplo -Unidade 'D:' -TamanhoGB 931.5 -LivreGB 640.2 -Tipo 'HDD')
        Get-MaquinaExemplo -ComputerName 'PC-COMPRAS-02' -Usuario 'CONTOSO\sonia.cruz' -Fabricante 'HP' -Modelo 'ProDesk 400 G7' -IP '192.0.2.42' -QtdSoftware 30 -Setor 'Compras' @win10 -Antivirus (Get-AntivirusExemplo -Atualizado $false -Nome 'Antivirus Corporativo') -Discos (& $ssd 238.5 120.4)
        Get-MaquinaExemplo -ComputerName 'PC-TI-01' -Usuario 'CONTOSO\admin.ti' -RAMGB 32 -Slots 4 -SlotsUsados 4 -IP '192.0.2.51' -QtdSoftware 64 -Setor 'TI' -AcessoRemoto 'AnyDesk', 'RustDesk' -Monitores 2 -Discos (& $ssd 953.9 601.3)
        Get-MaquinaExemplo -ComputerName 'PC-TI-02' -Usuario 'CONTOSO\suporte.ti' -IP '192.0.2.52' -QtdSoftware 51 -Setor 'TI' -UptimeDias 45 -RebootPendente $true -AcessoRemoto 'TeamViewer' -Discos (& $ssd 476.3 255.7)
        Get-MaquinaExemplo -ComputerName 'NB-DIRETORIA-01' -Usuario 'CONTOSO\roberto.alves' -Fabricante 'Lenovo' -Modelo 'ThinkPad T14' -IP '192.0.2.61' -QtdSoftware 47 -Setor 'Diretoria' -Slots 2 -Discos (& $ssd 476.3 120.5)
        Get-MaquinaExemplo -ComputerName 'NB-DIRETORIA-02' -Usuario 'CONTOSO\helena.rocha' -Fabricante 'Lenovo' -Modelo 'ThinkPad T14' -IP '192.0.2.62' -QtdSoftware 44 -Setor 'Diretoria' -Slots 2 -Discos (Get-DiscoExemplo -TamanhoGB 476.3 -LivreGB 199.0 -Saude 'Warning')
        Get-MaquinaExemplo -ComputerName 'NB-COMERCIAL-01' -Usuario 'CONTOSO\igor.faria' -Fabricante 'Dell Inc.' -Modelo 'Latitude 5420' -IP '192.0.2.63' -QtdSoftware 39 -Setor 'Comercial' -Slots 2 -Discos (& $ssd 238.5 28.6)
        Get-MaquinaExemplo -ComputerName 'NB-COMERCIAL-02' -Usuario 'CONTOSO\vera.tavares' -Fabricante 'Dell Inc.' -Modelo 'Latitude 5410' -RAMGB 8 -IP '192.0.2.64' -QtdSoftware 37 -Setor 'Comercial' -Slots 2 @win10 -Discos (& $ssd 238.5 90.0)
        Get-MaquinaExemplo -ComputerName 'PC-LOGISTICA-01' -Usuario 'CONTOSO\jorge.leal' -IP '192.0.2.71' -QtdSoftware 28 -Setor 'Logistica' -AcessoRemoto 'TeamViewer' -Discos (& $ssd 476.3 330.0)
        Get-MaquinaExemplo -ComputerName 'PC-LOGISTICA-02' -Usuario 'CONTOSO\bia.lopes' -RAMGB 8 -IP '192.0.2.72' -QtdSoftware 26 -Setor 'Logistica' -Discos (& $hdd 931.5 600.0)
        Get-MaquinaExemplo -ComputerName 'PC-PRODUCAO-01' -Usuario 'CONTOSO\operador1' -Fabricante 'HP' -Modelo 'EliteDesk 800 G3' -RAMGB 8 -IP '192.0.2.81' -QtdSoftware 24 -Setor 'Producao' @win10 -Fonte 'Local' -IdadeDias 6.1 -Discos (& $ssd 238.5 100.0)
        Get-MaquinaExemplo -ComputerName 'PC-PRODUCAO-02' -Usuario 'CONTOSO\operador2' -Fabricante 'HP' -Modelo 'EliteDesk 800 G5' -IP '192.0.2.82' -QtdSoftware 25 -Setor 'Producao' -Fonte 'Local' -IdadeDias 2.1 -Discos (& $ssd 238.5 140.0)
        Get-MaquinaExemplo -ComputerName 'PC-PRODUCAO-03' -Usuario 'CONTOSO\operador3' -Fabricante 'HP' -Modelo 'Compaq 6200' -RAMGB 2 -Slots 2 -SlotsUsados 1 -RAMTipo 'DDR3' -CPU 'Intel(R) Core(TM) i3-2100 CPU @ 3.10GHz' -IP '192.0.2.83' -QtdSoftware 14 -Setor 'Producao' @win7 -Fonte 'Local' -IdadeDias 20.4 -Ativacao 'Nao licenciado' -Antivirus $semAV -Office $null -Discos (& $hdd 232.9 98.4)
        Get-MaquinaExemplo -ComputerName 'PC-JURIDICO-01' -Usuario 'CONTOSO\camila.braga' -IP '192.0.2.91' -QtdSoftware 41 -Setor 'Juridico' -Discos (& $ssd 476.3 280.0)
        Get-MaquinaExemplo -ComputerName 'PC-MARKETING-01' -Usuario 'CONTOSO\diego.melo' -RAMGB 32 -Slots 4 -SlotsUsados 2 -IP '192.0.2.92' -QtdSoftware 58 -Setor 'Marketing' -Monitores 2 -Discos (& $ssd 953.9 410.0)
        Get-MaquinaExemplo -ComputerName 'PC-MARKETING-02' -Usuario 'CONTOSO\paula.viana' -IP '192.0.2.93' -QtdSoftware 49 -Setor 'Marketing' -AcessoRemoto 'RustDesk' -Discos (& $ssd 476.3 215.0)
        Get-MaquinaExemplo -ComputerName 'SRV-ARQUIVOS-01' -Fabricante 'Dell Inc.' -Modelo 'PowerEdge T340' -RAMGB 32 -Slots 4 -SlotsUsados 2 -CPU 'Intel(R) Xeon(R) E-2234 CPU @ 3.60GHz' -IP '192.0.2.5' -QtdSoftware 22 -Setor 'Servidores' -SO 'Microsoft Windows Server 2012 R2 Standard' -Build '9600' -Antivirus $null -Office $null -UptimeDias 112 -Descricao 'Servidor de arquivos' -Discos (& $ssd 223.0 60.4), (Get-DiscoExemplo -Unidade 'E:' -TamanhoGB 3725.3 -LivreGB 310.8 -Tipo 'HDD')
        Get-MaquinaExemplo -ComputerName 'SRV-APP-01' -Fabricante 'Dell Inc.' -Modelo 'PowerEdge R250' -RAMGB 64 -Slots 4 -SlotsUsados 2 -CPU 'Intel(R) Xeon(R) E-2314 CPU @ 2.80GHz' -IP '192.0.2.6' -QtdSoftware 27 -Setor 'Servidores' -SO 'Microsoft Windows Server 2022 Standard' -Build '20348' -Antivirus $null -Office $null -Descricao 'ERP e banco de dados' -Discos (& $ssd 446.6 233.9)
        Get-MaquinaExemplo -ComputerName 'SRV-DC-01' -Fabricante 'Dell Inc.' -Modelo 'PowerEdge T140' -RAMGB 16 -IP '192.0.2.2' -QtdSoftware 18 -Setor 'Servidores' -SO 'Microsoft Windows Server 2012 Standard' -Build '9200' -Antivirus $null -Office $null -Protocolo 'DCOM' -Descricao 'Controlador de domínio' -Discos (& $ssd 223.0 120.0)
        Get-MaquinaExemplo -ComputerName 'SRV-BACKUP-01' -Fabricante 'Dell Inc.' -Modelo 'PowerEdge T140' -RAMGB 16 -IP '192.0.2.7' -QtdSoftware 16 -Setor 'Servidores' -SO 'Microsoft Windows Server 2016 Standard' -Build '14393' -Antivirus $null -Office $null -Descricao 'Backup e NAS' -Discos (& $ssd 223.0 150.0), (Get-DiscoExemplo -Unidade 'F:' -TamanhoGB 7450.0 -LivreGB 3100.0 -Tipo 'HDD')
        Get-MaquinaExemplo -ComputerName 'PC-ESTAGIO-01' -Usuario 'CONTOSO\estagio1' -IP '192.0.2.101' -QtdSoftware 20 -Setor 'Estagio' -Fonte 'Local' -IdadeDias 15.3 -Discos (& $ssd 238.5 150.0)
        Get-MaquinaExemplo -ComputerName 'PC-ESTAGIO-02' -Usuario 'CONTOSO\estagio2' -RAMGB 8 -IP '192.0.2.102' -QtdSoftware 20 -Setor 'Estagio' -Discos (& $ssd 238.5 170.0)
        Get-MaquinaExemplo -ComputerName 'PC-VISITANTE-01' -Usuario 'VISITANTE\externo' -Fabricante 'Acer' -Modelo 'Veriton X' -IP '192.0.2.150' -QtdSoftware 15 -NoAD $false -Office $null -Discos (& $ssd 238.5 140.0) -Descricao ''
        Get-MaquinaExemplo -ComputerName 'PC-ALMOXARIFADO-01' -Status 'Offline' -Erro 'Host nao responde ao ping' -Setor 'Almoxarifado' -LogonAD ([datetime]'2026-10-02T17:40:00')
        Get-MaquinaExemplo -ComputerName 'PC-ALMOXARIFADO-02' -Status 'Offline' -Erro 'Host nao responde ao ping' -Setor 'Almoxarifado' -SO 'Microsoft Windows 10 Pro' -LogonAD ([datetime]'2025-03-18T09:15:00') -Descricao 'Bancada antiga'
        Get-MaquinaExemplo -ComputerName 'PC-VENDAS-03' -Status 'AcessoNegado' -Erro 'Acesso negado' -Setor 'Vendas'
        Get-MaquinaExemplo -ComputerName 'PC-VENDAS-04' -Status 'SemWinRMeDcom' -Erro 'WinRM: Porta 5985 (WinRM) inacessível; DCOM: O servidor RPC não está disponível' -Setor 'Vendas'
        Get-MaquinaExemplo -ComputerName 'PC-VENDAS-05' -Status 'Erro' -Erro 'Tempo limite da operação excedido' -Setor 'Vendas'
        Get-MaquinaExemplo -ComputerName 'PC-VENDAS-06' -Status 'SemWinRMeDcom' -Erro 'WinRM: Porta 5985 (WinRM) inacessível; DCOM: O servidor RPC não está disponível' -Setor 'Vendas'
        Get-MaquinaExemplo -ComputerName 'PC-ANTIGO-01' -Status 'NaoInventariado' -Setor 'Descartados' -SO 'Microsoft Windows 7 Professional' -LogonAD ([datetime]'2024-06-11T08:00:00') -Descricao 'Substituído em 2024'
        Get-MaquinaExemplo -ComputerName 'PC-ANTIGO-02' -Status 'NaoInventariado' -Setor 'Descartados' -SO 'Microsoft Windows 7 Professional' -LogonAD $null
        Get-MaquinaExemplo -ComputerName 'NB-VIAGEM-01' -Status 'Offline' -Erro 'Host nao responde ao ping' -Setor 'Diretoria' -LogonAD ([datetime]'2026-09-24T19:20:00') -Descricao 'Notebook de viagem'
    )
}
