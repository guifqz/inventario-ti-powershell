function Get-InventarioMaquina {
    <#
    .SYNOPSIS
        Coleta o inventario de hardware e software de uma ou mais maquinas Windows.

    .DESCRIPTION
        Consulta CIM/WMI e devolve um objeto por maquina com hostname, usuario logado,
        fabricante/modelo, serial, BIOS, CPU, memoria (slots, velocidade, tipo), discos (SSD/HDD e
        saude quando o Windows informa), sistema operacional, ultimo boot e uptime, rede, antivirus
        (Security Center, so estacoes), monitores, Office, ferramentas de acesso remoto, reinicio
        pendente e software instalado (chaves Uninstall de 32 e 64 bits, via StdRegProv).

        Cada consulta opcional falha sozinha e fica $null; so a falha de conexao ou das consultas
        basicas (sistema e SO) marca a maquina como nao coletada.

        Sem -ComputerName a maquina local e inspecionada. Hosts offline ou inacessiveis nao geram
        erro: o objeto volta com Online = $false, StatusColeta (Offline, AcessoNegado, SemWinRMeDcom
        ou Erro) e uma Mensagem em portugues indicando como corrigir.

        Com -Protocolo Auto (padrao) tenta WinRM e, se nao houver WinRM, usa DCOM.

    .PARAMETER ComputerName
        Nome(s) ou IP(s) das maquinas. Aceita pipeline. Padrao: maquina local.

    .PARAMETER Credential
        Credencial usada nas sessoes CIM remotas. Ignorada para a maquina local.

    .PARAMETER Protocolo
        Auto (padrao: WinRM e, na falta dele, DCOM), Wsman ou Dcom.

    .PARAMETER SemSoftware
        Nao lista o software instalado (coleta bem mais rapida). Office e acesso remoto dependem dessa lista.

    .PARAMETER IncluirAtivacao
        Consulta o status de ativacao do Windows (SoftwareLicensingProduct).

    .PARAMETER TimeoutSegundos
        Tempo maximo de cada operacao CIM remota.

    .PARAMETER PularPing
        Nao sonda a rede antes de coletar. Uso interno de Invoke-InventarioRede, que ja fez a sondagem.

    .PARAMETER WinRMAberto
        Resultado conhecido da porta 5985; $false pula a tentativa de WinRM. Uso interno.

    .PARAMETER RpcAberto
        Resultado conhecido da porta 135; $false pula a tentativa de DCOM. Uso interno.

    .EXAMPLE
        Get-InventarioMaquina

        Inventario da maquina local.

    .EXAMPLE
        Get-InventarioMaquina -ComputerName PC-FINANCEIRO-01 -Credential (Get-Credential) -IncluirAtivacao

    .EXAMPLE
        'PC-RH-01', 'PC-RH-02' | Get-InventarioMaquina -SemSoftware | Format-Table ComputerName, StatusColeta, RAMGB

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

        [ValidateSet('Auto', 'Wsman', 'Dcom')]
        [string]$Protocolo = 'Auto',

        [switch]$SemSoftware,

        [switch]$IncluirAtivacao,

        [ValidateRange(5, 600)]
        [int]$TimeoutSegundos = 20,

        [switch]$PularPing,

        [Nullable[bool]]$WinRMAberto,

        [Nullable[bool]]$RpcAberto
    )

    process {
        foreach ($alvo in $ComputerName) {
            $local = Test-AlvoLocal -Nome $alvo
            $maquina = Initialize-RegistroMaquina -ComputerName $alvo
            $winrm = $WinRMAberto
            $rpc = $RpcAberto

            if (-not $local -and -not $PularPing) {
                $sonda = Test-HostAtivoParalelo -ComputerName $alvo | Select-Object -First 1
                if (-not $sonda.Respondeu) {
                    $maquina.StatusColeta = 'Offline'
                    $maquina.Erro = 'Host nao responde ao ping'
                    $maquina.Mensagem = Get-MensagemStatus -StatusColeta 'Offline'
                    $maquina
                    continue
                }
                if ($null -eq $winrm) { $winrm = $sonda.WinRM }
                if ($null -eq $rpc) { $rpc = $sonda.Rpc }
            }

            $sessao = $null
            try {
                $conectou = $true
                if ($local) {
                    $maquina.ProtocoloUsado = 'Local'
                }
                else {
                    $parametrosSessao = @{
                        ComputerName    = $alvo
                        Protocolo       = $Protocolo
                        TimeoutSegundos = $TimeoutSegundos
                        WinRMAberto     = $winrm
                        RpcAberto       = $rpc
                    }
                    if ($Credential) { $parametrosSessao.Credential = $Credential }

                    $abertura = Open-SessaoCim @parametrosSessao
                    $sessao = $abertura.Sessao
                    if ($null -eq $sessao) {
                        $conectou = $false
                        $falha = Resolve-StatusColeta -ErroWsman $abertura.ErroWsman -ErroDcom $abertura.ErroDcom
                        $maquina.StatusColeta = $falha.StatusColeta
                        $maquina.Mensagem = $falha.Mensagem
                        $maquina.Erro = $falha.Erro
                    }
                    else {
                        $maquina.ProtocoloUsado = $abertura.ProtocoloUsado
                    }
                }

                if ($conectou) {
                    Invoke-ColetaMaquina -Maquina $maquina -Sessao $sessao -SemSoftware:$SemSoftware -IncluirAtivacao:$IncluirAtivacao
                }
            }
            catch {
                $falha = Resolve-StatusColeta -ErroGenerico $_.Exception.Message
                $maquina.Online = $false
                $maquina.StatusColeta = $falha.StatusColeta
                $maquina.Mensagem = $falha.Mensagem
                $maquina.Erro = $_.Exception.Message.Trim()
                Write-Verbose "Falha ao coletar ${alvo}: $($maquina.Erro)"
            }
            finally {
                Remove-SessaoCim -Sessao $sessao
            }

            $maquina.ColetadoEm = Get-Date
            $maquina
        }
    }
}
