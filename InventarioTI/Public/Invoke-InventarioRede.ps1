function Invoke-InventarioRede {
    <#
    .SYNOPSIS
        Executa Get-InventarioMaquina em varias maquinas, em paralelo, e junta AD e coletas locais.

    .DESCRIPTION
        Monta a lista de maquinas a partir de -ComputerName, de um arquivo texto (-Path,
        um nome por linha; linhas vazias e iniciadas por # sao ignoradas) e/ou do Active
        Directory: o dominio inteiro (-DoAD) ou uma OU (-OrganizationalUnit / -SearchBase).
        A consulta ao AD usa ADSI e nao exige RSAT; se o ADSI falhar e o modulo ActiveDirectory
        existir, ele e usado como alternativa. As fontes se combinam e nomes repetidos sao descartados.

        Antes de coletar, um ping paralelo (com teste das portas 135, 445 e 5985 para quem bloqueia
        ICMP) separa as maquinas offline sem esperar timeouts de CIM. Com -Protocolo Auto
        (padrao) cada maquina tenta WinRM e cai para DCOM se nao houver WinRM.

        Cada registro traz ProtocoloUsado, StatusColeta (Coletado, Offline, AcessoNegado,
        SemWinRMeDcom, Erro ou NaoInventariado), uma Mensagem com a correcao sugerida, Fonte
        (Remoto ou Local) e os dados do AD (OU, descricao, ultimo logon, flags de inatividade).

        Com -PastaColetaLocal, os JSON gravados por tools/Coletar-Local.ps1 entram na mesclagem:
        por maquina vale a coleta com dados mais recentes.

        A coleta usa um RunspacePool, entao funciona igual no Windows PowerShell 5.1 e no
        PowerShell 7. O resultado sai em ordem alfabetica.

    .PARAMETER ComputerName
        Nomes ou IPs das maquinas.

    .PARAMETER Path
        Arquivo texto com um computador por linha.

    .PARAMETER OrganizationalUnit
        Distinguished name da OU (ex.: 'OU=Estacoes,DC=empresa,DC=local'). Alias: SearchBase.

    .PARAMETER DoAD
        Inclui todos os computadores do dominio atual.

    .PARAMETER IncluirDesativados
        Inclui contas de computador desativadas no AD.

    .PARAMETER PastaColetaLocal
        Pasta (normalmente um compartilhamento) com os JSON do coletor local.

    .PARAMETER ThrottleLimit
        Maximo de maquinas coletadas ao mesmo tempo.

    .PARAMETER Credential
        Credencial para as sessoes CIM remotas.

    .PARAMETER Protocolo
        Auto (padrao), Wsman ou Dcom.

    .PARAMETER SemSoftware
        Nao lista o software instalado.

    .PARAMETER IncluirAtivacao
        Inclui o status de ativacao do Windows.

    .PARAMETER TimeoutPingMs
        Tempo de espera da sondagem de rede. Padrao: 1000.

    .EXAMPLE
        Invoke-InventarioRede -ComputerName PC-FINANCEIRO-01, PC-RH-01 -ThrottleLimit 8

    .EXAMPLE
        Invoke-InventarioRede -DoAD -IncluirAtivacao -PastaColetaLocal \\srv01\Ativos | Export-InventarioRelatorio -Path .\saida

    .EXAMPLE
        Invoke-InventarioRede -OrganizationalUnit 'OU=Estacoes,DC=contoso,DC=local' -Credential $cred

    .OUTPUTS
        InventarioTI.Maquina
    #>
    [CmdletBinding()]
    [OutputType('InventarioTI.Maquina')]
    param(
        [string[]]$ComputerName,

        [string]$Path,

        [Alias('SearchBase')]
        [string]$OrganizationalUnit,

        [switch]$DoAD,

        [switch]$IncluirDesativados,

        [string]$PastaColetaLocal,

        [ValidateRange(1, 128)]
        [int]$ThrottleLimit = 16,

        [pscredential]$Credential,

        [ValidateSet('Auto', 'Wsman', 'Dcom')]
        [string]$Protocolo = 'Auto',

        [switch]$SemSoftware,

        [switch]$IncluirAtivacao,

        [ValidateRange(200, 10000)]
        [int]$TimeoutPingMs = 1000
    )

    $computadoresAD = @()
    if ($DoAD -or $OrganizationalUnit) {
        Write-Progress -Activity 'Inventário de rede' -Status 'Consultando o Active Directory' -PercentComplete 0
        $computadoresAD = @(Get-ComputadoresAD -SearchBase $OrganizationalUnit -IncluirDesativados:$IncluirDesativados)
        Write-Verbose "$($computadoresAD.Count) computador(es) no AD"
    }

    $nomes = @(Resolve-AlvoInventario -ComputerName $ComputerName -Path $Path)
    $nomesAD = @($computadoresAD | Where-Object { $_.Habilitado } | ForEach-Object { if ($_.DNSHostName) { $_.DNSHostName } else { $_.Nome } })
    $alvos = @(($nomes + $nomesAD) | Where-Object { $_ } | Sort-Object -Property @{ Expression = { Get-ChaveMaquina -Nome $_ } } |
            Group-Object -Property { Get-ChaveMaquina -Nome $_ } | ForEach-Object { $_.Group[0] })

    if ($alvos.Count -eq 0 -and -not $PastaColetaLocal) {
        Write-Progress -Activity 'Inventário de rede' -Completed
        throw 'Nenhum computador informado. Use -ComputerName, -Path, -OrganizationalUnit, -DoAD ou -PastaColetaLocal.'
    }

    $remotos = [System.Collections.Generic.List[object]]::new()

    if ($alvos.Count -gt 0) {
        Write-Progress -Activity 'Inventário de rede' -Status "Sondando $($alvos.Count) computador(es)" -PercentComplete 5
        $locais = @($alvos | Where-Object { Test-AlvoLocal -Nome $_ })
        $remotosAlvo = @($alvos | Where-Object { -not (Test-AlvoLocal -Nome $_) })

        $sondas = @{}
        if ($remotosAlvo.Count -gt 0) {
            foreach ($s in (Test-HostAtivoParalelo -ComputerName $remotosAlvo -TimeoutMs $TimeoutPingMs)) { $sondas[$s.Nome] = $s }
        }

        $coletar = [System.Collections.Generic.List[object]]::new()
        foreach ($alvo in $alvos) {
            if ($alvo -in $locais) { $coletar.Add(@{ Alvo = $alvo; WinRM = $null; Rpc = $null }); continue }
            $sonda = $sondas[$alvo]
            if ($sonda -and $sonda.Respondeu) {
                $coletar.Add(@{ Alvo = $alvo; WinRM = $sonda.WinRM; Rpc = $sonda.Rpc })
            }
            else {
                $remotos.Add((Initialize-RegistroFalha -ComputerName $alvo -StatusColeta 'Offline' -Erro 'Host nao responde ao ping'))
            }
        }

        if ($coletar.Count -gt 0) {
            $manifesto = Join-Path -Path $MyInvocation.MyCommand.Module.ModuleBase -ChildPath 'InventarioTI.psd1'
            $estado = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
            $estado.ImportPSModule($manifesto)

            $limite = [math]::Min($ThrottleLimit, $coletar.Count)
            $pool = [runspacefactory]::CreateRunspacePool(1, $limite, $estado, $Host)
            $pool.Open()

            $bloco = {
                param($Alvo, $Opcoes)
                Get-InventarioMaquina -ComputerName $Alvo @Opcoes
            }

            $tarefas = foreach ($item in $coletar) {
                $opcoes = @{ Protocolo = $Protocolo; PularPing = $true }
                if ($Credential) { $opcoes.Credential = $Credential }
                if ($SemSoftware) { $opcoes.SemSoftware = $true }
                if ($IncluirAtivacao) { $opcoes.IncluirAtivacao = $true }
                if ($null -ne $item.WinRM) { $opcoes.WinRMAberto = [bool]$item.WinRM }
                if ($null -ne $item.Rpc) { $opcoes.RpcAberto = [bool]$item.Rpc }

                $ps = [powershell]::Create()
                $ps.RunspacePool = $pool
                [void]$ps.AddScript($bloco).AddArgument($item.Alvo).AddArgument($opcoes)
                [pscustomobject]@{ Alvo = $item.Alvo; Shell = $ps; Handle = $ps.BeginInvoke() }
            }
            $tarefas = @($tarefas)

            Write-Verbose "Coletando $($tarefas.Count) maquina(s), ate $limite em paralelo"

            try {
                do {
                    $prontas = @($tarefas | Where-Object { $_.Handle.IsCompleted }).Count
                    $percentual = 10 + [int](85 * $prontas / $tarefas.Count)
                    Write-Progress -Activity 'Inventário de rede' -Status "Coletando: $prontas de $($tarefas.Count) concluídas" -PercentComplete $percentual
                    if ($prontas -lt $tarefas.Count) { Start-Sleep -Milliseconds 250 }
                } while ($prontas -lt $tarefas.Count)

                foreach ($t in $tarefas) {
                    try {
                        $resultado = $t.Shell.EndInvoke($t.Handle)
                        if ($resultado) {
                            foreach ($r in $resultado) { $remotos.Add($r) }
                        }
                        else {
                            $remotos.Add((Initialize-RegistroFalha -ComputerName $t.Alvo -StatusColeta 'Erro' -Erro 'Coleta sem retorno'))
                        }
                    }
                    catch {
                        $remotos.Add((Initialize-RegistroFalha -ComputerName $t.Alvo -StatusColeta 'Erro' -Erro $_.Exception.Message))
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
    }

    $locaisJson = @()
    if ($PastaColetaLocal) {
        Write-Progress -Activity 'Inventário de rede' -Status 'Lendo coletas locais' -PercentComplete 97
        $locaisJson = @(Import-InventarioPasta -Path $PastaColetaLocal)
    }

    Write-Progress -Activity 'Inventário de rede' -Status 'Mesclando resultados' -PercentComplete 99
    Merge-InventarioColeta -Remoto $remotos.ToArray() -Local $locaisJson -AD $computadoresAD
    Write-Progress -Activity 'Inventário de rede' -Completed
}
