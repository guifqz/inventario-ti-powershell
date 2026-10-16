function Invoke-InventarioRede {
    <#
    .SYNOPSIS
        Executa Get-InventarioMaquina em varias maquinas, em paralelo.

    .DESCRIPTION
        Monta a lista de maquinas a partir de -ComputerName, de um arquivo texto (-Path,
        um nome por linha; linhas vazias e iniciadas por # sao ignoradas) e/ou de uma OU
        do Active Directory (-OrganizationalUnit, exige o modulo ActiveDirectory).
        As fontes se combinam e nomes repetidos sao descartados.

        A coleta usa um RunspacePool, entao funciona igual no Windows PowerShell 5.1 e
        no PowerShell 7. A ordem do resultado segue a ordem alfabetica da lista.

    .PARAMETER ComputerName
        Nomes ou IPs das maquinas.

    .PARAMETER Path
        Arquivo texto com um computador por linha.

    .PARAMETER OrganizationalUnit
        Distinguished name da OU (ex.: 'OU=Estacoes,DC=empresa,DC=local').

    .PARAMETER ThrottleLimit
        Maximo de maquinas coletadas ao mesmo tempo.

    .PARAMETER Credential
        Credencial para as sessoes CIM remotas.

    .PARAMETER Protocolo
        Wsman (padrao) ou Dcom.

    .PARAMETER SemSoftware
        Nao lista o software instalado.

    .PARAMETER IncluirAtivacao
        Inclui o status de ativacao do Windows.

    .EXAMPLE
        Invoke-InventarioRede -ComputerName PC-FINANCEIRO-01, PC-RH-01 -ThrottleLimit 8

    .EXAMPLE
        Invoke-InventarioRede -Path .\computadores.txt -SemSoftware | Export-InventarioRelatorio -Path .\saida

    .EXAMPLE
        Invoke-InventarioRede -OrganizationalUnit 'OU=Estacoes,DC=empresa,DC=local' -Credential $cred

    .OUTPUTS
        InventarioTI.Maquina
    #>
    [CmdletBinding()]
    [OutputType('InventarioTI.Maquina')]
    param(
        [string[]]$ComputerName,

        [string]$Path,

        [string]$OrganizationalUnit,

        [ValidateRange(1, 128)]
        [int]$ThrottleLimit = 16,

        [pscredential]$Credential,

        [ValidateSet('Wsman', 'Dcom')]
        [string]$Protocolo = 'Wsman',

        [switch]$SemSoftware,

        [switch]$IncluirAtivacao
    )

    $alvos = @(Resolve-AlvoInventario -ComputerName $ComputerName -Path $Path -OrganizationalUnit $OrganizationalUnit)
    if ($alvos.Count -eq 0) {
        throw 'Nenhum computador informado. Use -ComputerName, -Path ou -OrganizationalUnit.'
    }

    $opcoes = @{ Protocolo = $Protocolo }
    if ($Credential) { $opcoes.Credential = $Credential }
    if ($SemSoftware) { $opcoes.SemSoftware = $true }
    if ($IncluirAtivacao) { $opcoes.IncluirAtivacao = $true }

    $manifesto = Join-Path -Path $MyInvocation.MyCommand.Module.ModuleBase -ChildPath 'InventarioTI.psd1'
    $estado = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
    $estado.ImportPSModule($manifesto)

    $limite = [math]::Min($ThrottleLimit, $alvos.Count)
    $pool = [runspacefactory]::CreateRunspacePool(1, $limite, $estado, $Host)
    $pool.Open()

    $bloco = {
        param($Alvo, $Opcoes)
        Get-InventarioMaquina -ComputerName $Alvo @Opcoes
    }

    $tarefas = foreach ($alvo in $alvos) {
        $ps = [powershell]::Create()
        $ps.RunspacePool = $pool
        [void]$ps.AddScript($bloco).AddArgument($alvo).AddArgument($opcoes)
        [pscustomobject]@{ Alvo = $alvo; Shell = $ps; Handle = $ps.BeginInvoke() }
    }

    Write-Verbose "Coletando $($alvos.Count) maquina(s), ate $limite em paralelo"

    try {
        foreach ($t in $tarefas) {
            try {
                $resultado = $t.Shell.EndInvoke($t.Handle)
                if ($resultado) {
                    $resultado
                }
                else {
                    Initialize-RegistroMaquina -ComputerName $t.Alvo -Erro 'Coleta sem retorno'
                }
            }
            catch {
                Initialize-RegistroMaquina -ComputerName $t.Alvo -Erro $_.Exception.Message
            }
            finally {
                $t.Shell.Dispose()
            }
        }
    }
    finally {
        $pool.Close()
        $pool.Dispose()
    }
}

