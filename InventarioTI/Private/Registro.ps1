function Initialize-RegistroMaquina {
    [CmdletBinding()]
    [OutputType('InventarioTI.Maquina')]
    param(
        [Parameter(Mandatory)][string]$ComputerName,
        [string]$Erro
    )

    [pscustomobject]@{
        PSTypeName         = 'InventarioTI.Maquina'
        ComputerName       = $ComputerName
        Online             = $false
        Erro               = $Erro
        Hostname           = $null
        Usuario            = $null
        Fabricante         = $null
        Modelo             = $null
        Serial             = $null
        CPU                = $null
        CPUNucleos         = $null
        RAMGB              = $null
        Discos             = @()
        SistemaOperacional = $null
        VersaoSO           = $null
        BuildSO            = $null
        InstaladoEm        = $null
        UltimoBoot         = $null
        IP                 = $null
        MAC                = $null
        Ativacao           = $null
        Software           = @()
        ColetadoEm         = Get-Date
    }
}
