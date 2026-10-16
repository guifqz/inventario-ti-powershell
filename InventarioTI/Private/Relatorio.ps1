$script:DiretorioTemplates = Join-Path -Path $PSScriptRoot -ChildPath 'Templates'
$script:CamposData = @('ColetadoEm', 'InstaladoEm', 'UltimoBoot', 'BiosData', 'UltimoLogonAD', 'CriadoEmAD')

function Format-DataHora {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowNull()][object]$Data
    )

    if ($null -eq $Data) { return '' }
    ([datetime]$Data).ToString('yyyy-MM-dd HH:mm')
}

function Format-Nulo {
    # Texto para CSV: $null vira vazio, booleanos e listas viram texto legivel.
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowNull()][object]$Valor
    )

    if ($null -eq $Valor) { return '' }
    if ($Valor -is [array]) { return (@($Valor) -join ', ') }
    [string]$Valor
}

function ConvertTo-RegistroPlano {
    # Uma linha por maquina, para CSV/Excel: colecoes viram texto.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)][object]$Maquina,
        [double]$LimiteDisco = $script:LimiteDiscoPadrao,
        [datetime]$DataReferencia = (Get-Date)
    )

    process {
        $alertas = @(Get-AlertasMaquina -Maquina $Maquina -LimiteDisco $LimiteDisco -DataReferencia $DataReferencia)
        $antivirus = @($Maquina.Antivirus | Where-Object { $null -ne $_ } | ForEach-Object {
                '{0}{1}' -f $_.Nome, $(if (-not $_.Ativo) { ' (desativado)' } elseif (-not $_.Atualizado) { ' (desatualizado)' } else { '' })
            })
        $monitores = @($Maquina.Monitores | Where-Object { $null -ne $_ } | ForEach-Object { ('{0} {1}' -f $_.Fabricante, $_.Modelo).Trim() })

        [pscustomobject][ordered]@{
            Computador         = $Maquina.ComputerName
            Online             = $Maquina.Online
            StatusColeta       = $Maquina.StatusColeta
            Mensagem           = $Maquina.Mensagem
            Erro               = $Maquina.Erro
            Fonte              = $Maquina.Fonte
            Protocolo          = $Maquina.ProtocoloUsado
            IdadeDadosDias     = Format-Nulo $Maquina.IdadeDadosDias
            Usuario            = $Maquina.Usuario
            Fabricante         = $Maquina.Fabricante
            Modelo             = $Maquina.Modelo
            Serial             = $Maquina.Serial
            BIOS               = Format-Nulo $Maquina.BiosVersao
            CPU                = $Maquina.CPU
            Threads            = Format-Nulo $Maquina.CPUThreads
            RAMGB              = if ($null -ne $Maquina.RAMGB) { ([double]$Maquina.RAMGB).ToString('N1', [cultureinfo]'pt-BR') } else { '' }
            RAMSlots           = if ($null -ne $Maquina.RAMSlotsTotal) { "$($Maquina.RAMSlotsUsados)/$($Maquina.RAMSlotsTotal)" } else { '' }
            RAMTipo            = Format-Nulo $Maquina.RAMTipo
            Discos             = Format-DiscoResumo -Discos $Maquina.Discos
            AlertaDisco        = @(Get-DiscoEmAlerta -Discos $Maquina.Discos -Limite $LimiteDisco).Count -gt 0
            SistemaOperacional = $Maquina.SistemaOperacional
            VersaoSO           = $Maquina.VersaoSO
            BuildSO            = $Maquina.BuildSO
            SuporteSO          = if ($Maquina.Online) { Get-StatusSuporteSO -Nome $Maquina.SistemaOperacional -DataReferencia $DataReferencia } else { '' }
            InstaladoEm        = Format-DataHora -Data $Maquina.InstaladoEm
            UltimoBoot         = Format-DataHora -Data $Maquina.UltimoBoot
            UptimeDias         = Format-Nulo $Maquina.UptimeDias
            RebootPendente     = Format-Nulo $Maquina.RebootPendente
            IP                 = $Maquina.IP
            MAC                = $Maquina.MAC
            Ativacao           = $Maquina.Ativacao
            Antivirus          = $antivirus -join '; '
            Monitores          = $monitores -join '; '
            Office             = $Maquina.Office
            AcessoRemoto       = Format-Nulo $Maquina.AcessoRemoto
            SoftwareQtd        = @($Maquina.Software).Count
            NoAD               = $Maquina.NoAD
            OU                 = $Maquina.OU
            DescricaoAD        = $Maquina.DescricaoAD
            UltimoLogonAD      = Format-DataHora -Data $Maquina.UltimoLogonAD
            Alertas            = ($alertas | ForEach-Object { $_.Rotulo }) -join '; '
            ColetadoEm         = Format-DataHora -Data $Maquina.ColetadoEm
        }
    }
}

function ConvertTo-RegistroJson {
    # Mantem a estrutura aninhada (discos, software...); datas em ISO 8601 porque o
    # ConvertTo-Json do 5.1 serializa DateTime no formato /Date(...)/.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)][object]$Maquina
    )

    process {
        $saida = [ordered]@{}
        foreach ($p in $Maquina.PSObject.Properties) {
            $valor = $p.Value
            if ($valor -is [datetime]) { $valor = $valor.ToString('s') }
            elseif ($p.Name -in @('Discos', 'Software', 'Adaptadores', 'AcessoRemoto')) { $valor = @($valor | Where-Object { $null -ne $_ }) }
            $saida[$p.Name] = $valor
        }
        [pscustomobject]$saida
    }
}

function ConvertTo-DataSegura {
    # No PowerShell 7 o ConvertFrom-Json ja devolve DateTime; no 5.1 vem texto ISO.
    [CmdletBinding()]
    [OutputType([datetime])]
    param(
        [AllowNull()][object]$Valor
    )

    if ($null -eq $Valor -or "$Valor" -eq '') { return $null }
    if ($Valor -is [datetime]) { return $Valor }

    $data = [datetime]::MinValue
    if ([datetime]::TryParse([string]$Valor, [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$data)) { return $data }
    $null
}

function ConvertFrom-RegistroJson {
    # Reconstroi o registro a partir do JSON gravado; campos ausentes (versao antiga do coletor) ficam no padrao.
    [CmdletBinding()]
    [OutputType('InventarioTI.Maquina')]
    param(
        [Parameter(Mandatory)][object]$Objeto,
        [datetime]$DataArquivo = (Get-Date)
    )

    $nome = [string]$Objeto.ComputerName
    if ([string]::IsNullOrWhiteSpace($nome)) { throw 'JSON sem ComputerName' }

    $registro = Initialize-RegistroMaquina -ComputerName $nome
    $listasSempre = @('Discos', 'Software', 'Adaptadores', 'AcessoRemoto')
    $listasOpcionais = @('Antivirus', 'Monitores')

    foreach ($campo in @($registro.PSObject.Properties.Name)) {
        $origem = $Objeto.PSObject.Properties[$campo]
        if (-not $origem) { continue }
        $valor = $origem.Value

        if ($campo -in $script:CamposData) { $valor = ConvertTo-DataSegura -Valor $valor }
        elseif ($campo -in $listasSempre) { $valor = @($valor | Where-Object { $null -ne $_ }) }
        elseif ($campo -in $listasOpcionais) { if ($null -ne $valor) { $valor = @($valor | Where-Object { $null -ne $_ }) } }

        $registro.$campo = $valor
    }

    if ($null -eq $registro.ColetadoEm) { $registro.ColetadoEm = $DataArquivo }
    $registro.Online = [bool]$registro.Online
    $registro.Fonte = 'Local'
    $registro
}

function ConvertTo-ModeloRelatorio {
    # Visao enxuta de uma maquina para o JSON embutido no HTML (alertas ja calculados).
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][object]$Maquina,
        [double]$LimiteDisco = $script:LimiteDiscoPadrao,
        [datetime]$DataReferencia = (Get-Date)
    )

    $iso = { param($d) if ($null -eq $d) { $null } else { ([datetime]$d).ToString('s') } }
    $alertas = @(Get-AlertasMaquina -Maquina $Maquina -LimiteDisco $LimiteDisco -DataReferencia $DataReferencia)

    $temAntivirus = $null -ne $Maquina.Antivirus
    $temMonitores = $null -ne $Maquina.Monitores

    [pscustomobject][ordered]@{
        nome        = $Maquina.ComputerName
        status      = if ($Maquina.StatusColeta) { $Maquina.StatusColeta } elseif ($Maquina.Online) { 'Coletado' } else { 'Erro' }
        mensagem    = $Maquina.Mensagem
        erro        = $Maquina.Erro
        protocolo   = $Maquina.ProtocoloUsado
        fonte       = $Maquina.Fonte
        idadeDias   = $Maquina.IdadeDadosDias
        coletadoEm  = & $iso $Maquina.ColetadoEm
        usuario     = $Maquina.Usuario
        fabricante  = $Maquina.Fabricante
        modelo      = $Maquina.Modelo
        serial      = $Maquina.Serial
        biosVersao  = $Maquina.BiosVersao
        biosData    = & $iso $Maquina.BiosData
        cpu         = $Maquina.CPU
        cpuNucleos  = $Maquina.CPUNucleos
        cpuThreads  = $Maquina.CPUThreads
        ramGB       = $Maquina.RAMGB
        ramUsados   = $Maquina.RAMSlotsUsados
        ramSlots    = $Maquina.RAMSlotsTotal
        ramMHz      = $Maquina.RAMVelocidadeMHz
        ramTipo     = $Maquina.RAMTipo
        discos      = @($Maquina.Discos | Where-Object { $null -ne $_ } | ForEach-Object {
                [ordered]@{ u = $_.Unidade; rotulo = $_.Rotulo; tamGB = $_.TamanhoGB; livreGB = $_.LivreGB; pct = $_.PercentualLivre; tipo = $_.Tipo; saude = $_.Saude; sistema = [bool]$_.Sistema }
            })
        so          = $Maquina.SistemaOperacional
        soBuild     = $Maquina.BuildSO
        soArq       = $Maquina.Arquitetura
        soInstalado = & $iso $Maquina.InstaladoEm
        ativacao    = $Maquina.Ativacao
        boot        = & $iso $Maquina.UltimoBoot
        uptimeDias  = $Maquina.UptimeDias
        reboot      = $Maquina.RebootPendente
        rede        = @($Maquina.Adaptadores | Where-Object { $null -ne $_ } | ForEach-Object {
                [ordered]@{ nome = $_.Nome; ip = $_.IP; mac = $_.MAC; dhcp = $_.DHCP; gw = $_.Gateway }
            })
        ip          = $Maquina.IP
        av          = if ($temAntivirus) {
            @($Maquina.Antivirus | Where-Object { $null -ne $_ } | ForEach-Object { [ordered]@{ nome = $_.Nome; ativo = [bool]$_.Ativo; atualizado = [bool]$_.Atualizado } })
        }
        else { $null }
        monitores   = if ($temMonitores) {
            @($Maquina.Monitores | Where-Object { $null -ne $_ } | ForEach-Object { [ordered]@{ fab = $_.Fabricante; modelo = $_.Modelo; serial = $_.Serial } })
        }
        else { $null }
        office      = $Maquina.Office
        remoto      = @($Maquina.AcessoRemoto | Where-Object { $null -ne $_ })
        software    = @($Maquina.Software | Where-Object { $null -ne $_ } | ForEach-Object { [ordered]@{ n = $_.Nome; v = $_.Versao; f = $_.Fabricante } })
        noAD        = [bool]$Maquina.NoAD
        dns         = $Maquina.DNSHostName
        ou          = $Maquina.OU
        descricaoAD = $Maquina.DescricaoAD
        soAD        = $Maquina.SistemaOperacionalAD
        logonAD     = & $iso $Maquina.UltimoLogonAD
        criadoAD    = & $iso $Maquina.CriadoEmAD
        habilitado  = $Maquina.HabilitadoAD
        alertas     = @($alertas | ForEach-Object { [ordered]@{ c = $_.Codigo; g = $_.Gravidade; r = $_.Rotulo; t = $_.Texto; f = $_.Correcao } })
    }
}

function ConvertTo-JsonParaHtml {
    # JSON seguro dentro de <script type="application/json">: sem "</script>", "<!--" nem separadores de linha Unicode.
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowNull()][object]$Objeto
    )

    $json = ConvertTo-Json -InputObject $Objeto -Depth 8 -Compress
    # O 5.1 ja escapa < > & sozinho, o 7 nao; eles so aparecem dentro de strings JSON, entao \uXXXX e seguro.
    $json.Replace('<', '\u003c').Replace('>', '\u003e').Replace('&', '\u0026').
    Replace([string][char]0x2028, '\u2028').Replace([string][char]0x2029, '\u2029')
}

function ConvertTo-RelatorioHtml {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowNull()][AllowEmptyCollection()][object[]]$Maquinas,
        [string]$Titulo = 'Inventário de TI',
        [double]$LimiteDisco = $script:LimiteDiscoPadrao,
        [datetime]$DataReferencia = (Get-Date)
    )

    $lista = @($Maquinas | Where-Object { $null -ne $_ } | Sort-Object -Property ComputerName)
    $modelos = [object[]]@($lista | ForEach-Object { ConvertTo-ModeloRelatorio -Maquina $_ -LimiteDisco $LimiteDisco -DataReferencia $DataReferencia })

    $meta = [ordered]@{
        titulo            = $Titulo
        geradoEm          = $DataReferencia.ToString('s')
        limiteDisco       = $LimiteDisco
        limiteRAMGB       = $script:LimiteRAMGBPadrao
        limiteUptimeDias  = $script:LimiteUptimeDiasPadrao
        diasInatividadeAD = $script:DiasInatividadeADPadrao
    }

    $caminho = Join-Path -Path $script:DiretorioTemplates -ChildPath 'relatorio.html'
    $modelo = [System.IO.File]::ReadAllText($caminho, [System.Text.Encoding]::UTF8)

    # Os dados entram por ultimo: nenhum texto vindo deles pode ser tratado como marcador.
    $modelo.Replace('{{TITULO}}', (ConvertTo-HtmlSeguro -Texto $Titulo)).
    Replace('{{GERADO_EM}}', $DataReferencia.ToString('dd/MM/yyyy HH:mm')).
    Replace('{{META_JSON}}', (ConvertTo-JsonParaHtml -Objeto $meta)).
    Replace('{{DADOS_JSON}}', (ConvertTo-JsonParaHtml -Objeto $modelos))
}
