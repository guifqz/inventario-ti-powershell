function Get-InventarioMaquina {
    <#
    .SYNOPSIS
        Coleta o inventario de hardware e software de uma ou mais maquinas Windows.

    .DESCRIPTION
        Consulta CIM/WMI e devolve um objeto por maquina com hostname, usuario logado,
        fabricante/modelo, serial, CPU, memoria, discos (com tipo SSD/HDD quando o
        Windows informa), sistema operacional, ultimo boot, rede e software instalado
        (chaves Uninstall de 32 e 64 bits, lidas via StdRegProv, sem PowerShell Remoting).

        Sem -ComputerName a maquina local e inspecionada. Hosts offline ou inacessiveis
        nao geram erro: o objeto volta com Online = $false e o motivo em Erro.

    .PARAMETER ComputerName
        Nome(s) ou IP(s) das maquinas. Aceita pipeline. Padrao: maquina local.

    .PARAMETER Credential
        Credencial usada nas sessoes CIM remotas. Ignorada para a maquina local.

    .PARAMETER Protocolo
        Wsman (padrao) ou Dcom. Use Dcom em maquinas sem WinRM habilitado.

    .PARAMETER SemSoftware
        Nao lista o software instalado (coleta bem mais rapida).

    .PARAMETER IncluirAtivacao
        Consulta o status de ativacao do Windows (SoftwareLicensingProduct).

    .PARAMETER TimeoutSegundos
        Tempo maximo de cada operacao CIM remota.

    .EXAMPLE
        Get-InventarioMaquina

        Inventario da maquina local.

    .EXAMPLE
        Get-InventarioMaquina -ComputerName PC-FINANCEIRO-01 -Credential (Get-Credential) -IncluirAtivacao

    .EXAMPLE
        'PC-RH-01', 'PC-RH-02' | Get-InventarioMaquina -SemSoftware | Format-Table ComputerName, Online, RAMGB

    .OUTPUTS
        InventarioTI.Maquina
    #>
    [CmdletBinding()]
    [OutputType('InventarioTI.Maquina')]
    param(
        [Parameter(ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('Name', 'CN')]
        [string[]]$ComputerName = $env:COMPUTERNAME,

        [pscredential]$Credential,

        [ValidateSet('Wsman', 'Dcom')]
        [string]$Protocolo = 'Wsman',

        [switch]$SemSoftware,

        [switch]$IncluirAtivacao,

        [ValidateRange(5, 600)]
        [int]$TimeoutSegundos = 20
    )

    process {
        foreach ($alvo in $ComputerName) {
            $local = $alvo -in @('.', 'localhost', $env:COMPUTERNAME, '127.0.0.1')

            $maquina = Initialize-RegistroMaquina -ComputerName $alvo

            if (-not $local -and -not (Test-Connection -ComputerName $alvo -Count 1 -Quiet -ErrorAction SilentlyContinue)) {
                $maquina.Erro = 'Host nao responde ao ping'
                $maquina
                continue
            }

            $sessao = $null
            try {
                if (-not $local) {
                    $parametrosSessao = @{
                        ComputerName    = $alvo
                        Protocolo       = $Protocolo
                        TimeoutSegundos = $TimeoutSegundos
                    }
                    if ($Credential) { $parametrosSessao.Credential = $Credential }
                    $sessao = New-SessaoCim @parametrosSessao
                }

                $sistema = Get-DadosCim -ClassName Win32_ComputerSystem -Sessao $sessao | Select-Object -First 1
                $bios = Get-DadosCim -ClassName Win32_BIOS -Sessao $sessao | Select-Object -First 1
                $os = Get-DadosCim -ClassName Win32_OperatingSystem -Sessao $sessao | Select-Object -First 1
                $processador = @(Get-DadosCim -ClassName Win32_Processor -Sessao $sessao)

                $maquina.Online = $true
                $maquina.Hostname = $sistema.Name
                $maquina.Usuario = $sistema.UserName
                $maquina.Fabricante = $sistema.Manufacturer
                $maquina.Modelo = $sistema.Model
                $maquina.Serial = $bios.SerialNumber
                $maquina.CPU = ($processador | Select-Object -First 1).Name.Trim()
                $maquina.CPUNucleos = ($processador | Measure-Object -Property NumberOfCores -Sum).Sum
                $maquina.RAMGB = [math]::Round($sistema.TotalPhysicalMemory / 1GB, 1)
                $maquina.SistemaOperacional = $os.Caption.Trim()
                $maquina.VersaoSO = $os.Version
                $maquina.BuildSO = $os.BuildNumber
                $maquina.InstaladoEm = $os.InstallDate
                $maquina.UltimoBoot = $os.LastBootUpTime

                $maquina.Discos = @(Get-DiscosMaquina -Sessao $sessao)

                $rede = Get-DadosCim -ClassName Win32_NetworkAdapterConfiguration -Filter 'IPEnabled = TRUE' -Sessao $sessao |
                    Where-Object { $_.IPAddress | Where-Object { $_ -match '^\d{1,3}(\.\d{1,3}){3}$' } } |
                    Select-Object -First 1
                if ($rede) {
                    $maquina.IP = $rede.IPAddress | Where-Object { $_ -match '^\d{1,3}(\.\d{1,3}){3}$' } | Select-Object -First 1
                    $maquina.MAC = $rede.MACAddress
                }

                if ($IncluirAtivacao) {
                    $maquina.Ativacao = Get-StatusAtivacao -Sessao $sessao
                }

                if (-not $SemSoftware) {
                    $maquina.Software = @(Get-SoftwareInstalado -Sessao $sessao | Sort-Object -Property Nome)
                }
            }
            catch {
                $maquina.Erro = $_.Exception.Message.Trim()
                Write-Verbose "Falha ao coletar ${alvo}: $($maquina.Erro)"
            }
            finally {
                Remove-SessaoCim -Sessao $sessao
            }

            $maquina
        }
    }
}

