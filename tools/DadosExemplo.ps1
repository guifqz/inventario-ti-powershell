# Dados ficticios no formato de saida de Get-InventarioMaquina.
# Usado por tools/Gerar-Exemplo.ps1 (docs/) e pelos testes. Nenhum dado real.

function Get-DiscoExemplo {
    param(
        [string]$Unidade = 'C:',
        [double]$TamanhoGB,
        [double]$LivreGB,
        [string]$Tipo = 'SSD'
    )

    [pscustomobject]@{
        Unidade         = $Unidade
        Rotulo          = ''
        TamanhoGB       = $TamanhoGB
        LivreGB         = $LivreGB
        PercentualLivre = [math]::Round(($LivreGB / $TamanhoGB) * 100, 1)
        Tipo            = $Tipo
    }
}

function Get-MaquinaExemplo {
    param(
        [Parameter(Mandatory)][string]$ComputerName,
        [bool]$Online = $true,
        [string]$Erro,
        [string]$Usuario,
        [string]$Fabricante = 'Dell Inc.',
        [string]$Modelo = 'OptiPlex 3080',
        [string]$CPU = 'Intel(R) Core(TM) i5-10500 CPU @ 3.10GHz',
        [double]$RAMGB = 16,
        [object[]]$Discos = @(),
        [string]$SO = 'Microsoft Windows 11 Pro',
        [string]$Build = '22631',
        [string]$IP,
        [string]$MAC,
        [int]$QtdSoftware = 0
    )

    $software = foreach ($i in 1..$QtdSoftware) {
        [pscustomobject]@{ Nome = "Aplicativo exemplo $i"; Versao = "1.$i.0"; Fabricante = 'Fornecedor Exemplo'; Arquitetura = 'x64' }
    }

    [pscustomobject]@{
        PSTypeName         = 'InventarioTI.Maquina'
        ComputerName       = $ComputerName
        Online             = $Online
        Erro               = $Erro
        Hostname           = if ($Online) { $ComputerName } else { $null }
        Usuario            = $Usuario
        Fabricante         = if ($Online) { $Fabricante } else { $null }
        Modelo             = if ($Online) { $Modelo } else { $null }
        Serial             = if ($Online) { 'SN' + ((([int[]][char[]]$ComputerName | Measure-Object -Sum).Sum * 7919) -band 0xFFFFFF).ToString('X6') } else { $null }
        CPU                = if ($Online) { $CPU } else { $null }
        CPUNucleos         = if ($Online) { 6 } else { $null }
        RAMGB              = if ($Online) { $RAMGB } else { $null }
        Discos             = @($Discos)
        SistemaOperacional = if ($Online) { $SO } else { $null }
        VersaoSO           = if ($Online) { '10.0.' + $Build } else { $null }
        BuildSO            = if ($Online) { $Build } else { $null }
        InstaladoEm        = if ($Online) { [datetime]'2023-03-14T09:20:00' } else { $null }
        UltimoBoot         = if ($Online) { [datetime]'2026-10-12T07:48:00' } else { $null }
        IP                 = $IP
        MAC                = $MAC
        Ativacao           = if ($Online) { 'Ativado' } else { $null }
        Software           = @($software)
        ColetadoEm         = [datetime]'2026-10-14T08:30:00'
    }
}

function Get-DadosExemplo {
    @(
        Get-MaquinaExemplo -ComputerName 'PC-FINANCEIRO-01' -Usuario 'EMPRESA\ana.souza' -IP '192.0.2.11' -MAC '00:50:56:AA:00:11' -QtdSoftware 42 `
            -Discos (Get-DiscoExemplo -TamanhoGB 476.3 -LivreGB 210.4)
        Get-MaquinaExemplo -ComputerName 'PC-FINANCEIRO-02' -Usuario 'EMPRESA\carlos.lima' -IP '192.0.2.12' -MAC '00:50:56:AA:00:12' -QtdSoftware 38 `
            -Discos (Get-DiscoExemplo -TamanhoGB 476.3 -LivreGB 38.2)
        Get-MaquinaExemplo -ComputerName 'PC-RH-01' -Usuario 'EMPRESA\marta.reis' -Modelo 'Vostro 3888' -RAMGB 8 -IP '192.0.2.21' -MAC '00:50:56:AA:00:21' -QtdSoftware 31 `
            -SO 'Microsoft Windows 10 Pro' -Build '19045' `
            -Discos (Get-DiscoExemplo -TamanhoGB 931.5 -LivreGB 402.7 -Tipo 'HDD')
        Get-MaquinaExemplo -ComputerName 'PC-RECEPCAO-01' -Fabricante 'Lenovo' -Modelo 'ThinkCentre M70s' -RAMGB 4 -IP '192.0.2.31' -MAC '00:50:56:AA:00:31' -QtdSoftware 19 `
            -SO 'Microsoft Windows 7 Professional' -Build '7601' -CPU 'Intel(R) Core(TM) i3-4130 CPU @ 3.40GHz' `
            -Discos (Get-DiscoExemplo -TamanhoGB 465.8 -LivreGB 211.0 -Tipo 'HDD')
        Get-MaquinaExemplo -ComputerName 'PC-COMPRAS-01' -Usuario 'EMPRESA\paulo.dias' -Fabricante 'HP' -Modelo 'ProDesk 400 G7' -IP '192.0.2.41' -MAC '00:50:56:AA:00:41' -QtdSoftware 36 `
            -Discos (Get-DiscoExemplo -TamanhoGB 238.5 -LivreGB 21.9), (Get-DiscoExemplo -Unidade 'D:' -TamanhoGB 931.5 -LivreGB 640.2 -Tipo 'HDD')
        Get-MaquinaExemplo -ComputerName 'PC-TI-01' -Usuario 'EMPRESA\admin.ti' -RAMGB 32 -IP '192.0.2.51' -MAC '00:50:56:AA:00:51' -QtdSoftware 64 `
            -Discos (Get-DiscoExemplo -TamanhoGB 953.9 -LivreGB 601.3)
        Get-MaquinaExemplo -ComputerName 'NB-DIRETORIA-01' -Usuario 'EMPRESA\roberto.alves' -Fabricante 'Lenovo' -Modelo 'ThinkPad T14' -RAMGB 16 -IP '192.0.2.61' -MAC '00:50:56:AA:00:61' -QtdSoftware 47 `
            -Discos (Get-DiscoExemplo -TamanhoGB 476.3 -LivreGB 120.5)
        Get-MaquinaExemplo -ComputerName 'SRV-ARQUIVOS-01' -Fabricante 'Dell Inc.' -Modelo 'PowerEdge T340' -RAMGB 32 -IP '192.0.2.5' -MAC '00:50:56:AA:00:05' -QtdSoftware 22 `
            -SO 'Microsoft Windows Server 2012 R2 Standard' -Build '9600' -CPU 'Intel(R) Xeon(R) E-2234 CPU @ 3.60GHz' `
            -Discos (Get-DiscoExemplo -TamanhoGB 223.0 -LivreGB 60.4), (Get-DiscoExemplo -Unidade 'E:' -TamanhoGB 3725.3 -LivreGB 310.8 -Tipo 'HDD')
        Get-MaquinaExemplo -ComputerName 'SRV-APP-01' -Fabricante 'Dell Inc.' -Modelo 'PowerEdge R250' -RAMGB 64 -CPU 'Intel(R) Xeon(R) E-2314 CPU @ 2.80GHz' -IP '192.0.2.6' -MAC '00:50:56:AA:00:06' -QtdSoftware 27 `
            -SO 'Microsoft Windows Server 2022 Standard' -Build '20348' `
            -Discos (Get-DiscoExemplo -TamanhoGB 446.6 -LivreGB 233.9)
        Get-MaquinaExemplo -ComputerName 'PC-ALMOXARIFADO-01' -Online $false -Erro 'Host nao responde ao ping'
        Get-MaquinaExemplo -ComputerName 'PC-VENDAS-03' -Online $false -Erro 'Acesso negado'
    )
}
