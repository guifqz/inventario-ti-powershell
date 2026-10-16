# Junta coleta remota, coleta local (JSON na pasta de rede) e dados do AD em um registro por maquina.
# Regras puras, cobertas por tests/Mesclagem.Tests.ps1.

function Get-ChaveMaquina {
    # Nome curto em maiusculas: 'pc-01.contoso.local' e 'PC-01' sao a mesma maquina. IPs ficam inteiros.
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowNull()][AllowEmptyString()][string]$Nome
    )

    if ([string]::IsNullOrWhiteSpace($Nome)) { return '' }
    $n = $Nome.Trim()
    if ($n -match '^\d{1,3}(\.\d{1,3}){3}$') { return $n }
    ($n -split '\.')[0].ToUpperInvariant()
}

function Copy-RegistroMaquina {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Maquina
    )

    $copia = [ordered]@{}
    foreach ($p in $Maquina.PSObject.Properties) { $copia[$p.Name] = $p.Value }
    $copia.PSTypeName = 'InventarioTI.Maquina'
    [pscustomobject]$copia
}

function Merge-InventarioColeta {
    <#
    Regras: por maquina vence a coleta com dados mais recente (empate favorece a remota); se nenhuma
    trouxe dados, fica o registro da falha remota. Depois anexa o AD e marca inatividade e "nunca inventariada".
    #>
    [CmdletBinding()]
    [OutputType('InventarioTI.Maquina')]
    param(
        [AllowNull()][AllowEmptyCollection()][object[]]$Remoto,
        [AllowNull()][AllowEmptyCollection()][object[]]$Local,
        [AllowNull()][AllowEmptyCollection()][object[]]$AD,
        [datetime]$DataReferencia = (Get-Date),
        [int]$DiasInatividadeAD = $script:DiasInatividadeADPadrao
    )

    $grupos = @{}
    $adPorChave = @{}
    $registrar = {
        param($Chave)
        if (-not $grupos.ContainsKey($Chave)) { $grupos[$Chave] = @{ Remoto = @(); Local = @() } }
    }

    foreach ($m in @($Remoto | Where-Object { $null -ne $_ })) {
        $k = Get-ChaveMaquina -Nome $m.ComputerName
        & $registrar $k
        $grupos[$k].Remoto += $m
    }
    foreach ($m in @($Local | Where-Object { $null -ne $_ })) {
        $k = Get-ChaveMaquina -Nome $m.ComputerName
        & $registrar $k
        $grupos[$k].Local += $m
    }
    foreach ($c in @($AD | Where-Object { $null -ne $_ })) {
        $k = Get-ChaveMaquina -Nome $c.Nome
        & $registrar $k
        $adPorChave[$k] = $c
    }

    foreach ($chave in ($grupos.Keys | Sort-Object)) {
        $g = $grupos[$chave]
        $ad = $adPorChave[$chave]

        $comDados = @(@($g.Remoto | ForEach-Object { $_ }) + @($g.Local | ForEach-Object { $_ }) | Where-Object { $_ -and $_.Online })
        $escolhido = $null
        if ($comDados.Count -gt 0) {
            $escolhido = $comDados | Sort-Object -Property @{ Expression = { $_.ColetadoEm }; Descending = $true }, @{ Expression = { if ($_.Fonte -eq 'Local') { 1 } else { 0 } } } | Select-Object -First 1
        }
        elseif (@($g.Remoto).Count -gt 0) {
            $escolhido = $g.Remoto | Select-Object -First 1
        }

        if ($escolhido) {
            $registro = Copy-RegistroMaquina -Maquina $escolhido
        }
        else {
            $registro = Initialize-RegistroFalha -ComputerName $ad.Nome -StatusColeta 'NaoInventariado'
            $registro.ColetadoEm = $null
        }

        if ($registro.Online) {
            $registro.IdadeDadosDias = [math]::Round(($DataReferencia - [datetime]$registro.ColetadoEm).TotalDays, 1)

            $falhaRemota = @($g.Remoto | Where-Object { -not $_.Online }) | Select-Object -First 1
            if ($registro.Fonte -eq 'Local') {
                $registro.ProtocoloUsado = 'Local'
                $registro.StatusColeta = 'Coletado'
                $registro.Mensagem = 'Dados do coletor local, coletados em {0:dd/MM/yyyy HH:mm} ({1:N0} dia(s) atrás).' -f $registro.ColetadoEm, $registro.IdadeDadosDias
                if ($falhaRemota) { $registro.Mensagem += " Coleta remota: $($falhaRemota.StatusColeta)." }
            }
        }

        if ($ad) {
            $registro.NoAD = $true
            if ($ad.Nome) { $registro.ComputerName = $ad.Nome }
            $registro.DNSHostName = $ad.DNSHostName
            $registro.SistemaOperacionalAD = $ad.SistemaOperacionalAD
            $registro.VersaoSOAD = $ad.VersaoSOAD
            $registro.UltimoLogonAD = $ad.UltimoLogonAD
            $registro.CriadoEmAD = $ad.CriadoEm
            $registro.DescricaoAD = $ad.Descricao
            $registro.OU = $ad.OU
            $registro.HabilitadoAD = $ad.Habilitado
            $registro.PossivelmenteInativo = Test-InativoAD -UltimoLogon $ad.UltimoLogonAD -CriadoEm $ad.CriadoEm -DataReferencia $DataReferencia -Dias $DiasInatividadeAD
            $registro.NuncaInventariado = -not $registro.Online
        }

        $registro
    }
}
