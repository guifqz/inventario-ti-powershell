# Camada fina sobre os cmdlets CIM. Existe para isolar o acesso ao sistema
# e permitir mock nos testes (CimSession real nao e facil de simular).

function Get-DadosCim {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ClassName,
        [string]$Namespace,
        [string]$Filter,
        [object]$Sessao
    )

    $parametros = @{ ClassName = $ClassName; ErrorAction = 'Stop' }
    if ($Namespace) { $parametros.Namespace = $Namespace }
    if ($Filter) { $parametros.Filter = $Filter }
    if ($Sessao) { $parametros.CimSession = $Sessao }

    Get-CimInstance @parametros
}

function New-SessaoCim {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$ComputerName,
        [pscredential]$Credential,
        [ValidateSet('Wsman', 'Dcom')][string]$Protocolo = 'Wsman',
        [int]$TimeoutSegundos = 20
    )

    if (-not $PSCmdlet.ShouldProcess($ComputerName, 'Abrir sessao CIM')) { return }

    $opcao = New-CimSessionOption -Protocol $Protocolo
    $parametros = @{
        ComputerName        = $ComputerName
        SessionOption       = $opcao
        OperationTimeoutSec = $TimeoutSegundos
        ErrorAction         = 'Stop'
    }
    if ($Credential) { $parametros.Credential = $Credential }

    New-CimSession @parametros
}

function Remove-SessaoCim {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [object]$Sessao
    )

    if ($Sessao -and $PSCmdlet.ShouldProcess('sessao CIM', 'Encerrar')) {
        Remove-CimSession -CimSession $Sessao -ErrorAction SilentlyContinue
    }
}

function Invoke-RegistroCim {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('EnumKey', 'GetStringValue', 'GetDWORDValue')][string]$Metodo,
        [Parameter(Mandatory)][string]$SubChave,
        [string]$Valor,
        [object]$Sessao
    )

    $argumentos = @{ hDefKey = [uint32]2147483650; sSubKeyName = $SubChave }
    if ($Valor) { $argumentos.sValueName = $Valor }

    $parametros = @{
        Namespace   = 'root\default'
        ClassName   = 'StdRegProv'
        MethodName  = $Metodo
        Arguments   = $argumentos
        ErrorAction = 'Stop'
    }
    if ($Sessao) { $parametros.CimSession = $Sessao }

    Invoke-CimMethod @parametros
}

function Get-SoftwareInstalado {
    [CmdletBinding()]
    param(
        [object]$Sessao
    )

    $raizes = @(
        'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
        'SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
    )

    $vistos = @{}
    foreach ($raiz in $raizes) {
        $arquitetura = if ($raiz -like '*WOW6432Node*') { 'x86' } else { 'x64' }

        $chaves = Invoke-RegistroCim -Metodo EnumKey -SubChave $raiz -Sessao $Sessao
        foreach ($chave in $chaves.sNames) {
            $caminho = "$raiz\$chave"

            $nome = (Invoke-RegistroCim -Metodo GetStringValue -SubChave $caminho -Valor 'DisplayName' -Sessao $Sessao).sValue
            if ([string]::IsNullOrWhiteSpace($nome)) { continue }

            $componente = (Invoke-RegistroCim -Metodo GetDWORDValue -SubChave $caminho -Valor 'SystemComponent' -Sessao $Sessao).uValue
            if ($componente -eq 1) { continue }

            $versao = (Invoke-RegistroCim -Metodo GetStringValue -SubChave $caminho -Valor 'DisplayVersion' -Sessao $Sessao).sValue
            $id = '{0}|{1}' -f $nome, $versao
            if ($vistos.ContainsKey($id)) { continue }
            $vistos[$id] = $true

            [pscustomobject]@{
                Nome         = $nome
                Versao       = $versao
                Fabricante   = (Invoke-RegistroCim -Metodo GetStringValue -SubChave $caminho -Valor 'Publisher' -Sessao $Sessao).sValue
                Arquitetura  = $arquitetura
            }
        }
    }
}
