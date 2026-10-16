# Sondagem de rede (ping + portas TCP em paralelo) e classificacao do resultado da coleta.
# As funcoes de classificacao sao puras e cobertas por tests/Rede.Tests.ps1.

function Test-AlvoLocal {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)][string]$Nome
    )

    $nome = $Nome.Trim()
    $nome -in @('.', 'localhost', '127.0.0.1', '::1', $env:COMPUTERNAME) -or
    $nome -like "$($env:COMPUTERNAME).*"
}

function Test-PortaTcpParalelo {
    # Tenta conectar em todas as combinacoes host x porta ao mesmo tempo. Devolve hashtable 'host|porta' -> bool.
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)][string[]]$ComputerName,
        [Parameter(Mandatory)][int[]]$Porta,
        [int]$TimeoutMs = 1000
    )

    $tentativas = [System.Collections.Generic.List[object]]::new()
    foreach ($nome in $ComputerName) {
        foreach ($p in $Porta) {
            $cliente = [System.Net.Sockets.TcpClient]::new()
            $tarefa = $null
            try { $tarefa = $cliente.ConnectAsync($nome, $p) } catch { Write-Verbose "TCP ${nome}:${p} falhou: $($_.Exception.Message)" }
            $tentativas.Add([pscustomobject]@{ Chave = "$nome|$p"; Cliente = $cliente; Tarefa = $tarefa })
        }
    }

    $pendentes = [System.Threading.Tasks.Task[]]@($tentativas | Where-Object { $null -ne $_.Tarefa } | ForEach-Object { $_.Tarefa })
    if ($pendentes.Count -gt 0) {
        try { [void][System.Threading.Tasks.Task]::WaitAll($pendentes, $TimeoutMs) } catch { Write-Verbose "Algumas conexoes TCP falharam: $($_.Exception.Message)" }
    }

    $resultado = @{}
    foreach ($t in $tentativas) {
        $resultado[$t.Chave] = ($null -ne $t.Tarefa -and $t.Tarefa.Status -eq 'RanToCompletion' -and $t.Cliente.Connected)
        $t.Cliente.Dispose()
    }
    $resultado
}

function Test-HostAtivoParalelo {
    # Ping assincrono em todos os hosts de uma vez. Quem nao responde ao ping ainda e testado em TCP
    # (135, 445, 5985), porque o firewall do Windows costuma bloquear ICMP em estacoes.
    # Devolve por host: Respondeu, Via, WinRM (5985 aberta) e Rpc (135 aberta).
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string[]]$ComputerName,
        [int]$TimeoutMs = 1000
    )

    $pings = [System.Collections.Generic.List[object]]::new()
    foreach ($nome in $ComputerName) {
        $ping = [System.Net.NetworkInformation.Ping]::new()
        $tarefa = $null
        try { $tarefa = $ping.SendPingAsync($nome, $TimeoutMs) } catch { Write-Verbose "Ping $nome falhou: $($_.Exception.Message)" }
        $pings.Add([pscustomobject]@{ Nome = $nome; Ping = $ping; Tarefa = $tarefa })
    }

    $pendentes = [System.Threading.Tasks.Task[]]@($pings | Where-Object { $null -ne $_.Tarefa } | ForEach-Object { $_.Tarefa })
    if ($pendentes.Count -gt 0) {
        try { [void][System.Threading.Tasks.Task]::WaitAll($pendentes, $TimeoutMs + 500) } catch { Write-Verbose "Alguns pings falharam: $($_.Exception.Message)" }
    }

    $portas = Test-PortaTcpParalelo -ComputerName $ComputerName -Porta 135, 445, 5985 -TimeoutMs $TimeoutMs

    foreach ($p in $pings) {
        $pingOk = ($null -ne $p.Tarefa -and $p.Tarefa.Status -eq 'RanToCompletion' -and $p.Tarefa.Result.Status -eq 'Success')
        $p.Ping.Dispose()

        $tcp = @(135, 445, 5985) | Where-Object { $portas["$($p.Nome)|$_"] }
        $via = if ($pingOk) { 'Ping' } elseif (@($tcp).Count -gt 0) { 'TCP' } else { $null }

        [pscustomobject]@{
            Nome      = $p.Nome
            Respondeu = [bool]$via
            Via       = $via
            WinRM     = [bool]$portas["$($p.Nome)|5985"]
            Rpc       = [bool]$portas["$($p.Nome)|135"]
        }
    }
}

function Get-ClasseErro {
    # AcessoNegado | Rpc | WinRM | Outro. As mensagens variam com o idioma do Windows, entao casa tambem codigos.
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowNull()][AllowEmptyString()][string]$Mensagem
    )

    if ([string]::IsNullOrWhiteSpace($Mensagem)) { return $null }

    if ($Mensagem -match 'acesso.{0,6}negado|access.{0,6}denied|80070005|2147942405|unauthorized|E_ACCESSDENIED') { return 'AcessoNegado' }
    if ($Mensagem -match 'RPC|800706BA|0x6BA|\b1722\b') { return 'Rpc' }
    if ($Mensagem -match 'WinRM|WS-Management|WSMan|8033\d{4}|21508\d{5}|porta 5985') { return 'WinRM' }
    'Outro'
}

function Get-MensagemStatus {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$StatusColeta,
        [string]$Detalhe
    )

    switch ($StatusColeta) {
        'Coletado' { 'Coleta concluída.' }
        'Offline' { 'Não respondeu a ping nem às portas 135, 445 e 5985. Confirme se está ligado e na rede; se foi descartado, remova do AD.' }
        'AcessoNegado' { 'Acesso negado. Execute com uma conta administradora das estações (ex.: Admins do Domínio) ou informe -Credential.' }
        'SemWinRMeDcom' { 'WinRM e DCOM indisponíveis (servidor RPC não disponível). Habilite WinRM via GPO ou libere a regra de firewall "Instrumentação de Gerenciamento do Windows (WMI-In)"; alternativa: coletor local por GPO de inicialização.' }
        'NaoInventariado' { 'Consta no AD, mas nenhuma coleta trouxe dados.' }
        default { if ($Detalhe) { "Falha na coleta: $Detalhe" } else { 'Falha na coleta.' } }
    }
}

function Resolve-StatusColeta {
    # Traduz os erros de WinRM/DCOM/coleta em StatusColeta + mensagem amigavel.
    [CmdletBinding()]
    param(
        [AllowNull()][string]$ErroWsman,
        [AllowNull()][string]$ErroDcom,
        [AllowNull()][string]$ErroGenerico
    )

    $erros = @($ErroWsman, $ErroDcom, $ErroGenerico) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_.Trim() }
    $erros = @($erros | Select-Object -Unique)

    $texto = if ($ErroWsman -and $ErroDcom -and $ErroWsman.Trim() -ne $ErroDcom.Trim()) {
        "WinRM: $($ErroWsman.Trim()); DCOM: $($ErroDcom.Trim())"
    }
    else {
        $erros -join '; '
    }

    $classes = @($erros | ForEach-Object { Get-ClasseErro -Mensagem $_ })

    $status = if ($classes -contains 'AcessoNegado') { 'AcessoNegado' }
    elseif ((Get-ClasseErro -Mensagem $ErroDcom) -eq 'Rpc') { 'SemWinRMeDcom' }
    else { 'Erro' }

    $detalhe = $texto
    if ($status -eq 'Erro' -and $ErroWsman -and -not $ErroDcom -and (Get-ClasseErro -Mensagem $ErroWsman) -eq 'WinRM') {
        $detalhe = "$texto. WinRM indisponível: use -Protocolo Auto (ou Dcom) ou habilite WinRM por GPO"
    }

    [pscustomobject]@{
        StatusColeta = $status
        Mensagem     = Get-MensagemStatus -StatusColeta $status -Detalhe $detalhe
        Erro         = $texto
    }
}
