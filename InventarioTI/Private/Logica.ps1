# Funcoes puras: sem acesso a CIM, disco ou rede. Cobertas por tests/Logica.Tests.ps1.

$script:LimiteDiscoPadrao = 15

# Fim do suporte por familia de SO. Ordem importa: padroes mais especificos primeiro.
# FimSuporte $null = ainda suportado, sem data de encerramento publicada.
$script:TabelaSuporteSO = @(
    @{ Padrao = 'Windows XP';            FimSuporte = [datetime]'2014-04-08' }
    @{ Padrao = 'Windows Vista';         FimSuporte = [datetime]'2017-04-11' }
    @{ Padrao = 'Windows 7';             FimSuporte = [datetime]'2020-01-14' }
    @{ Padrao = 'Windows 8\.1';          FimSuporte = [datetime]'2023-01-10' }
    @{ Padrao = 'Windows 8(?!\.)';       FimSuporte = [datetime]'2016-01-12' }
    @{ Padrao = 'Windows 10';            FimSuporte = [datetime]'2025-10-14' }
    @{ Padrao = 'Windows 11';            FimSuporte = $null }
    @{ Padrao = 'Server 2003';           FimSuporte = [datetime]'2015-07-14' }
    @{ Padrao = 'Server 2008';           FimSuporte = [datetime]'2020-01-14' }
    @{ Padrao = 'Server 2012';           FimSuporte = [datetime]'2023-10-10' }
    @{ Padrao = 'Server 2016';           FimSuporte = [datetime]'2027-01-12' }
    @{ Padrao = 'Server 2019';           FimSuporte = [datetime]'2029-01-09' }
    @{ Padrao = 'Server 2022';           FimSuporte = [datetime]'2031-10-14' }
    @{ Padrao = 'Server 2025';           FimSuporte = $null }
)

function Get-PercentualLivre {
    [CmdletBinding()]
    [OutputType([double])]
    param(
        [Parameter(Mandatory)][double]$TamanhoBytes,
        [Parameter(Mandatory)][double]$LivreBytes
    )

    if ($TamanhoBytes -le 0) { return [double]0 }
    [math]::Round(($LivreBytes / $TamanhoBytes) * 100, 1)
}

function Format-TamanhoGB {
    [CmdletBinding()]
    [OutputType([double])]
    param(
        [Parameter(Mandatory)][double]$Bytes
    )

    [math]::Round($Bytes / 1GB, 2)
}

function Test-DiscoBaixo {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)][double]$PercentualLivre,
        [double]$Limite = $script:LimiteDiscoPadrao
    )

    $PercentualLivre -lt $Limite
}

function Get-DiscoEmAlerta {
    [CmdletBinding()]
    param(
        [AllowNull()][AllowEmptyCollection()][object[]]$Discos,
        [double]$Limite = $script:LimiteDiscoPadrao
    )

    foreach ($disco in $Discos) {
        if ($null -ne $disco -and (Test-DiscoBaixo -PercentualLivre $disco.PercentualLivre -Limite $Limite)) {
            $disco
        }
    }
}

# Devolve 'Suportado', 'Fora de suporte' ou 'Desconhecido' para o nome do SO.
function Get-StatusSuporteSO {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowNull()][AllowEmptyString()][string]$Nome,
        [datetime]$DataReferencia = (Get-Date)
    )

    if ([string]::IsNullOrWhiteSpace($Nome)) { return 'Desconhecido' }

    foreach ($entrada in $script:TabelaSuporteSO) {
        if ($Nome -match $entrada.Padrao) {
            if ($null -eq $entrada.FimSuporte -or $DataReferencia -le $entrada.FimSuporte) {
                return 'Suportado'
            }
            return 'Fora de suporte'
        }
    }
    'Desconhecido'
}

function ConvertTo-HtmlSeguro {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowNull()][AllowEmptyString()][object]$Texto
    )

    if ($null -eq $Texto) { return '' }
    ([string]$Texto).Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;').Replace('"', '&quot;').Replace("'", '&#39;')
}

function Format-DiscoResumo {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowNull()][AllowEmptyCollection()][object[]]$Discos
    )

    $itens = foreach ($d in $Discos) {
        if ($null -eq $d) { continue }
        [string]::Format([cultureinfo]'pt-BR', '{0} {1:N1} GB ({2:N1}% livre, {3})', $d.Unidade, $d.TamanhoGB, $d.PercentualLivre, $d.Tipo)
    }
    $itens -join '; '
}

function Get-ResumoInventario {
    [CmdletBinding()]
    param(
        [AllowNull()][AllowEmptyCollection()][object[]]$Maquinas,
        [double]$LimiteDisco = $script:LimiteDiscoPadrao,
        [datetime]$DataReferencia = (Get-Date)
    )

    $lista = @($Maquinas | Where-Object { $null -ne $_ })
    $online = @($lista | Where-Object { $_.Online })

    $comAlerta = foreach ($m in $lista) {
        [pscustomobject]@{
            Maquina = $m
            Codigos = @(Get-AlertasMaquina -Maquina $m -LimiteDisco $LimiteDisco -DataReferencia $DataReferencia | ForEach-Object { $_.Codigo })
        }
    }
    $com = { param($Codigos) @($comAlerta | Where-Object { @($_.Codigos | Where-Object { $_ -in $Codigos }).Count -gt 0 } | ForEach-Object { $_.Maquina }) }

    $comDiscoBaixo = @(& $com @('DISCO_BAIXO'))
    $soForaSuporte = @(& $com @('SO_FORA_SUPORTE'))
    $semAcesso = @($lista | Where-Object { $_.StatusColeta -in 'AcessoNegado', 'SemWinRMeDcom', 'Erro' })

    [pscustomobject]@{
        Total                 = $lista.Count
        NoAD                  = @($lista | Where-Object { $_.NoAD }).Count
        Online                = $online.Count
        Offline               = $lista.Count - $online.Count
        SemAcesso             = $semAcesso.Count
        DiscoBaixo            = $comDiscoBaixo.Count
        SOForaSuporte         = $soForaSuporte.Count
        SemAntivirus          = @(& $com @('AV_AUSENTE', 'AV_DESATIVADO')).Count
        NaoAtivado            = @(& $com @('NAO_ATIVADO')).Count
        RAMBaixa              = @(& $com @('RAM_BAIXA')).Count
        HDDSistema            = @(& $com @('DISCO_SISTEMA_HDD')).Count
        PossivelmenteInativo  = @(& $com @('AD_INATIVO')).Count
        NuncaInventariado     = @(& $com @('NUNCA_INVENTARIADO')).Count
        LimiteDisco           = $LimiteDisco
        MaquinasDiscoBaixo    = $comDiscoBaixo
        MaquinasSOForaSuporte = $soForaSuporte
    }
}