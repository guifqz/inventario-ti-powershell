function Export-InventarioRelatorio {
    <#
    .SYNOPSIS
        Exporta o inventario para CSV, JSON, HTML e, opcionalmente, Excel.

    .DESCRIPTION
        Recebe os objetos de Get-InventarioMaquina / Invoke-InventarioRede (pipeline ou
        -InputObject) e grava os arquivos na pasta indicada. O HTML e autocontido (CSS
        embutido, JavaScript puro, sem CDN nem fontes externas: funciona offline) e traz cartoes
        clicaveis, graficos, tabela com busca/ordenacao/filtros, exportacao CSV da visao filtrada e
        uma gaveta de detalhes por maquina (link direto: arquivo.html#NOME-DO-PC).

        O formato Excel exige o modulo ImportExcel (Install-Module ImportExcel). Sem ele,
        o formato e ignorado com um aviso e os demais seguem normalmente.

        O CSV usa ponto e virgula e UTF-8 com BOM, para abrir direto no Excel em pt-BR.

    .PARAMETER InputObject
        Objetos InventarioTI.Maquina. Aceita pipeline.

    .PARAMETER Path
        Pasta de destino. E criada se nao existir.

    .PARAMETER Formato
        CSV, JSON, HTML, Excel ou All (CSV, JSON e HTML). Padrao: All.

    .PARAMETER NomeBase
        Nome dos arquivos, sem extensao. Padrao: inventario-AAAAMMDD-HHmm.

    .PARAMETER LimiteDisco
        Percentual de espaco livre abaixo do qual o disco entra em alerta. Padrao: 15.

    .PARAMETER Titulo
        Titulo do relatorio HTML.

    .PARAMETER DataReferencia
        Data usada nas regras de suporte do SO, inatividade no AD e no carimbo do relatorio. Padrao: agora.

    .EXAMPLE
        Invoke-InventarioRede -Path .\computadores.txt | Export-InventarioRelatorio -Path .\saida

    .EXAMPLE
        Export-InventarioRelatorio -InputObject $inventario -Path C:\Relatorios -Formato HTML, Excel -LimiteDisco 20

    .OUTPUTS
        System.IO.FileInfo
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([System.IO.FileInfo])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [AllowEmptyCollection()]
        [object[]]$InputObject,

        [Parameter(Mandatory)]
        [string]$Path,

        [ValidateSet('All', 'CSV', 'JSON', 'HTML', 'Excel')]
        [string[]]$Formato = 'All',

        [string]$NomeBase = ('inventario-{0:yyyyMMdd-HHmm}' -f (Get-Date)),

        [ValidateRange(1, 99)]
        [double]$LimiteDisco = 15,

        [string]$Titulo = 'Inventário de TI',

        [datetime]$DataReferencia = (Get-Date)
    )

    begin {
        $maquinas = [System.Collections.Generic.List[object]]::new()
    }

    process {
        foreach ($item in $InputObject) {
            if ($null -ne $item) { $maquinas.Add($item) }
        }
    }

    end {
        $formatos = if ($Formato -contains 'All') { @('CSV', 'JSON', 'HTML') + @($Formato | Where-Object { $_ -eq 'Excel' }) } else { $Formato }
        $formatos = $formatos | Select-Object -Unique

        if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
            if ($PSCmdlet.ShouldProcess($Path, 'Criar pasta de saida')) {
                [void](New-Item -Path $Path -ItemType Directory -Force)
            }
        }

        $destino = if (Test-Path -LiteralPath $Path) { (Resolve-Path -LiteralPath $Path).ProviderPath } else { $Path }
        $semBom = [System.Text.UTF8Encoding]::new($false)
        $comBom = [System.Text.UTF8Encoding]::new($true)
        $agora = $DataReferencia

        foreach ($f in $formatos) {
            $arquivo = Join-Path -Path $destino -ChildPath ("$NomeBase." + @{ CSV = 'csv'; JSON = 'json'; HTML = 'html'; Excel = 'xlsx' }[$f])

            if (-not $PSCmdlet.ShouldProcess($arquivo, "Exportar $f")) { continue }

            switch ($f) {
                'CSV' {
                    $linhas = @($maquinas | ConvertTo-RegistroPlano -LimiteDisco $LimiteDisco -DataReferencia $agora)
                    $csv = ($linhas | ConvertTo-Csv -NoTypeInformation -Delimiter ';') -join [Environment]::NewLine
                    [System.IO.File]::WriteAllText($arquivo, $csv + [Environment]::NewLine, $comBom)
                }
                'JSON' {
                    $registros = @($maquinas | ConvertTo-RegistroJson)
                    $json = ConvertTo-Json -InputObject $registros -Depth 6
                    [System.IO.File]::WriteAllText($arquivo, $json, $semBom)
                }
                'HTML' {
                    $html = ConvertTo-RelatorioHtml -Maquinas $maquinas.ToArray() -Titulo $Titulo -LimiteDisco $LimiteDisco -DataReferencia $agora
                    [System.IO.File]::WriteAllText($arquivo, $html, $semBom)
                }
                'Excel' {
                    if (-not (Get-Module -ListAvailable -Name ImportExcel)) {
                        Write-Warning 'Modulo ImportExcel nao encontrado: formato Excel ignorado. Instale com: Install-Module ImportExcel -Scope CurrentUser'
                        continue
                    }
                    $linhas = @($maquinas | ConvertTo-RegistroPlano -LimiteDisco $LimiteDisco -DataReferencia $agora)
                    $linhas | Export-Excel -Path $arquivo -WorksheetName 'Inventario' -AutoSize -FreezeTopRow -AutoFilter -ClearSheet
                }
            }

            if (Test-Path -LiteralPath $arquivo) { Get-Item -LiteralPath $arquivo }
        }
    }
}
