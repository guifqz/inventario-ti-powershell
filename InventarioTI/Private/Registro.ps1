function Initialize-RegistroMaquina {
    [CmdletBinding()]
    [OutputType('InventarioTI.Maquina')]
    param(
        [Parameter(Mandatory)][string]$ComputerName,
        [string]$Erro,
        [string]$StatusColeta = 'Erro'
    )

    [pscustomobject]@{
        PSTypeName           = 'InventarioTI.Maquina'
        ComputerName         = $ComputerName
        Online               = $false
        Erro                 = $Erro
        StatusColeta         = $StatusColeta
        Mensagem             = $null
        ProtocoloUsado       = $null
        Fonte                = 'Remoto'
        IdadeDadosDias       = $null
        Hostname             = $null
        Usuario              = $null
        Fabricante           = $null
        Modelo               = $null
        Serial               = $null
        BiosVersao           = $null
        BiosData             = $null
        CPU                  = $null
        CPUNucleos           = $null
        CPUThreads           = $null
        RAMGB                = $null
        RAMSlotsUsados       = $null
        RAMSlotsTotal        = $null
        RAMVelocidadeMHz     = $null
        RAMTipo              = $null
        Discos               = @()
        SistemaOperacional   = $null
        VersaoSO             = $null
        BuildSO              = $null
        Arquitetura          = $null
        InstaladoEm          = $null
        UltimoBoot           = $null
        UptimeDias           = $null
        RebootPendente       = $null
        IP                   = $null
        MAC                  = $null
        Adaptadores          = @()
        Ativacao             = $null
        Antivirus            = $null
        Monitores            = $null
        Office               = $null
        AcessoRemoto         = @()
        Software             = @()
        NoAD                 = $false
        DNSHostName          = $null
        SistemaOperacionalAD = $null
        VersaoSOAD           = $null
        UltimoLogonAD        = $null
        CriadoEmAD           = $null
        DescricaoAD          = $null
        OU                   = $null
        HabilitadoAD         = $null
        PossivelmenteInativo = $false
        NuncaInventariado    = $false
        ColetadoEm           = Get-Date
    }
}

function Initialize-RegistroFalha {
    [CmdletBinding()]
    [OutputType('InventarioTI.Maquina')]
    param(
        [Parameter(Mandatory)][string]$ComputerName,
        [Parameter(Mandatory)][string]$StatusColeta,
        [string]$Erro,
        [string]$Mensagem
    )

    $registro = Initialize-RegistroMaquina -ComputerName $ComputerName -Erro $Erro -StatusColeta $StatusColeta
    $registro.Mensagem = if ($Mensagem) { $Mensagem } else { Get-MensagemStatus -StatusColeta $StatusColeta -Detalhe $Erro }
    $registro
}
