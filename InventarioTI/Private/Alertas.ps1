# Regras de alerta: funcoes puras, testadas em tests/Alertas.Tests.ps1.
# Cada alerta sai como objeto { Codigo, Gravidade, Rotulo, Texto, Correcao }.

$script:LimiteRAMGBPadrao = 8
$script:LimiteUptimeDiasPadrao = 30

function Get-DiscoSaudeRuim {
    [CmdletBinding()]
    param(
        [AllowNull()][AllowEmptyCollection()][object[]]$Discos
    )

    foreach ($d in $Discos) {
        if ($null -ne $d -and $d.Saude -in @('Warning', 'Unhealthy')) { $d }
    }
}

function Test-RAMBaixa {
    # Arredonda para cima: 8 GB instalados aparecem como 7,4 a 7,9 GB por causa da memoria de video.
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [AllowNull()][object]$RAMGB,
        [double]$LimiteGB = $script:LimiteRAMGBPadrao
    )

    if ($null -eq $RAMGB) { return $false }
    [math]::Ceiling([double]$RAMGB) -lt $LimiteGB
}

function Test-DiscoSistemaHDD {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [AllowNull()][AllowEmptyCollection()][object[]]$Discos
    )

    $lista = @($Discos | Where-Object { $null -ne $_ })
    $sistema = @($lista | Where-Object { $_.Sistema })
    if ($sistema.Count -eq 0) { $sistema = @($lista | Where-Object { $_.Unidade -eq 'C:' }) }

    @($sistema | Where-Object { $_.Tipo -eq 'HDD' }).Count -gt 0
}

function Get-StatusProtecaoAV {
    # $null = nao coletado ou nao se aplica (servidor). Senao: Ausente, Desativado, Desatualizado ou OK.
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowNull()][AllowEmptyCollection()][object[]]$Antivirus
    )

    if ($null -eq $Antivirus) { return $null }

    $lista = @($Antivirus | Where-Object { $null -ne $_ })
    if ($lista.Count -eq 0) { return 'Ausente' }

    $ativos = @($lista | Where-Object { $_.Ativo })
    if ($ativos.Count -eq 0) { return 'Desativado' }
    if (@($ativos | Where-Object { $_.Atualizado }).Count -eq 0) { return 'Desatualizado' }
    'OK'
}

function Test-NaoAtivado {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [AllowNull()][AllowEmptyString()][string]$Ativacao
    )

    if ([string]::IsNullOrWhiteSpace($Ativacao)) { return $false }
    $Ativacao -eq 'Não licenciado' -or $Ativacao -eq 'Notificação' -or $Ativacao -like 'Período de carência*'
}

function Test-UptimeAlto {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [AllowNull()][object]$UptimeDias,
        [double]$LimiteDias = $script:LimiteUptimeDiasPadrao
    )

    if ($null -eq $UptimeDias) { return $false }
    [double]$UptimeDias -gt $LimiteDias
}

function Get-AlertasMaquina {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Maquina,
        [double]$LimiteDisco = $script:LimiteDiscoPadrao,
        [double]$LimiteRAMGB = $script:LimiteRAMGBPadrao,
        [double]$LimiteUptimeDias = $script:LimiteUptimeDiasPadrao,
        [int]$DiasInatividadeAD = $script:DiasInatividadeADPadrao,
        [datetime]$DataReferencia = (Get-Date)
    )

    $br = [cultureinfo]'pt-BR'
    $novo = {
        param($Codigo, $Gravidade, $Rotulo, $Texto, $Correcao)
        [pscustomobject]@{ Codigo = $Codigo; Gravidade = $Gravidade; Rotulo = $Rotulo; Texto = $Texto; Correcao = $Correcao }
    }

    if ($Maquina.Online) {
        foreach ($d in (Get-DiscoEmAlerta -Discos $Maquina.Discos -Limite $LimiteDisco)) {
            & $novo 'DISCO_BAIXO' 'Critico' 'Disco baixo' `
            ([string]::Format($br, 'Disco {0} com {1:N1}% livre ({2:N1} GB)', $d.Unidade, $d.PercentualLivre, $d.LivreGB)) `
                'Rode a Limpeza de Disco, remova arquivos grandes ou temporários, mova dados para o servidor ou amplie o disco.'
        }

        if ((Get-StatusSuporteSO -Nome $Maquina.SistemaOperacional -DataReferencia $DataReferencia) -eq 'Fora de suporte') {
            & $novo 'SO_FORA_SUPORTE' 'Critico' 'SO sem suporte' `
                "$($Maquina.SistemaOperacional) não recebe mais atualizações de segurança." `
                'Atualize para um Windows suportado (ou substitua o equipamento se o hardware não permitir) ou isole a máquina da rede.'
        }

        if (Test-RAMBaixa -RAMGB $Maquina.RAMGB -LimiteGB $LimiteRAMGB) {
            & $novo 'RAM_BAIXA' 'Aviso' 'RAM baixa' `
            ([string]::Format($br, '{0:N1} GB de RAM (recomendado: {1:N0} GB ou mais)', [double]$Maquina.RAMGB, $LimiteRAMGB)) `
                'Veja no detalhe os slots livres e instale mais memória, ou substitua o equipamento.'
        }

        if (Test-DiscoSistemaHDD -Discos $Maquina.Discos) {
            & $novo 'DISCO_SISTEMA_HDD' 'Aviso' 'HDD no sistema' `
                'O Windows está instalado em disco mecânico (HDD).' `
                'Troque por SSD e clone ou reinstale o sistema: é a melhoria de desempenho mais barata.'
        }

        foreach ($d in (Get-DiscoSaudeRuim -Discos $Maquina.Discos)) {
            & $novo 'DISCO_SAUDE' 'Critico' 'Disco com falha' `
                "Disco $($d.Unidade) informa saúde '$($d.Saude)'." `
                'Faça backup agora e substitua o disco.'
        }

        switch (Get-StatusProtecaoAV -Antivirus $Maquina.Antivirus) {
            'Ausente' {
                & $novo 'AV_AUSENTE' 'Critico' 'Sem antivírus' `
                    'Nenhum antivírus registrado no Windows Security Center.' `
                    'Instale o antivírus corporativo ou habilite o Microsoft Defender.'
            }
            'Desativado' {
                & $novo 'AV_DESATIVADO' 'Critico' 'Antivírus desativado' `
                    'Há antivírus instalado, mas nenhum está ativo.' `
                    'Reative a proteção em tempo real ou o serviço do antivírus.'
            }
            'Desatualizado' {
                & $novo 'AV_DESATUALIZADO' 'Aviso' 'Antivírus desatualizado' `
                    'As assinaturas do antivírus ativo estão desatualizadas.' `
                    'Force a atualização de definições e verifique a conectividade com o servidor de atualização.'
            }
        }

        if (Test-NaoAtivado -Ativacao $Maquina.Ativacao) {
            & $novo 'NAO_ATIVADO' 'Aviso' 'Não ativado' `
                "Windows com ativação: $($Maquina.Ativacao)." `
                'Ative com a licença corporativa (KMS/MAK) ou regularize a licença.'
        }

        if (Test-UptimeAlto -UptimeDias $Maquina.UptimeDias -LimiteDias $LimiteUptimeDias) {
            & $novo 'UPTIME_ALTO' 'Aviso' 'Sem reiniciar' `
            ([string]::Format($br, 'Ligado há {0:N0} dias sem reiniciar.', [double]$Maquina.UptimeDias)) `
                'Reinicie a máquina para aplicar atualizações pendentes.'
        }
    }

    if ($Maquina.NoAD -and $Maquina.HabilitadoAD -ne $false) {
        if (Test-InativoAD -UltimoLogon $Maquina.UltimoLogonAD -CriadoEm $Maquina.CriadoEmAD -DataReferencia $DataReferencia -Dias $DiasInatividadeAD) {
            $texto = if ($null -eq $Maquina.UltimoLogonAD) {
                'Nenhum logon registrado no AD.'
            }
            else {
                [string]::Format($br, 'Último logon no AD há {0:N0} dias.', ($DataReferencia - [datetime]$Maquina.UltimoLogonAD).TotalDays)
            }
            & $novo 'AD_INATIVO' 'Aviso' 'Possivelmente inativo' $texto `
                'Confirme se o equipamento ainda existe; se foi descartado, desative e remova a conta do AD.'
        }

        if ($Maquina.NuncaInventariado) {
            & $novo 'NUNCA_INVENTARIADO' 'Aviso' 'Nunca inventariado' `
                'Consta no AD, mas nenhuma coleta (remota ou local) trouxe dados.' `
                'Veja o status da coleta: habilite WinRM/WMI por GPO ou implante o coletor local.'
        }
    }
}
