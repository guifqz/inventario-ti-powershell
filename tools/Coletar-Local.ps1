<#
.SYNOPSIS
    Coleta o inventario da propria maquina e grava <HOSTNAME>.json em uma pasta (normalmente um compartilhamento).

.DESCRIPTION
    Pensado para rodar como script de inicializacao de computador (GPO) na conta SYSTEM, ou manualmente.
    Importa o modulo InventarioTI de -CaminhoModulo, coleta a maquina local (com ativacao e software)
    e grava o JSON de forma atomica (arquivo temporario + renomeacao), para o leitor nunca pegar um
    arquivo pela metade. Import-InventarioPasta / Invoke-InventarioRede -PastaColetaLocal le esses arquivos.

    Se o arquivo de destino for mais novo que -IntervaloHoras, a coleta e pulada (evita regravar a
    cada boot); use -Forcar para ignorar.

.PARAMETER PastaDestino
    Pasta onde o JSON sera gravado, ex.: \\srv01\Ativos. A conta de computador precisa de permissao de gravacao.

.PARAMETER CaminhoModulo
    Pasta do modulo InventarioTI (a que contem InventarioTI.psd1). Padrao: .\InventarioTI ao lado do
    script ou ..\InventarioTI (quando o script roda de dentro de tools\).

.PARAMETER IntervaloHoras
    Nao recoleta se o JSON da maquina for mais novo que isso. Padrao: 12. Use 0 para sempre coletar.

.PARAMETER SemSoftware
    Nao lista o software instalado.

.PARAMETER Forcar
    Coleta mesmo que o arquivo de destino seja recente.

.EXAMPLE
    .\Coletar-Local.ps1 -PastaDestino \\srv01\Ativos -CaminhoModulo \\srv01\Ativos\Coletor\InventarioTI

.EXAMPLE
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File \\srv01\Ativos\Coletor\Coletar-Local.ps1 -PastaDestino \\srv01\Ativos
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$PastaDestino,

    [string]$CaminhoModulo,

    [ValidateRange(0, 720)]
    [int]$IntervaloHoras = 12,

    [switch]$SemSoftware,

    [switch]$Forcar
)

$ErrorActionPreference = 'Stop'

if (-not $CaminhoModulo) {
    $candidatos = @(
        (Join-Path -Path $PSScriptRoot -ChildPath 'InventarioTI')
        (Join-Path -Path $PSScriptRoot -ChildPath '..\InventarioTI')
    )
    $CaminhoModulo = $candidatos | Where-Object { Test-Path -LiteralPath (Join-Path $_ 'InventarioTI.psd1') } | Select-Object -First 1
    if (-not $CaminhoModulo) { throw "Modulo InventarioTI nao encontrado ao lado do script. Informe -CaminhoModulo." }
}

$manifesto = if ($CaminhoModulo -like '*.psd1') { $CaminhoModulo } else { Join-Path -Path $CaminhoModulo -ChildPath 'InventarioTI.psd1' }
if (-not (Test-Path -LiteralPath $manifesto)) { throw "Manifesto nao encontrado: $manifesto" }
Import-Module -Name $manifesto -Force

if (-not (Test-Path -LiteralPath $PastaDestino -PathType Container)) { throw "Pasta de destino inacessivel: $PastaDestino" }

$destino = Join-Path -Path $PastaDestino -ChildPath "$($env:COMPUTERNAME).json"
if (-not $Forcar -and $IntervaloHoras -gt 0 -and (Test-Path -LiteralPath $destino)) {
    $idade = (Get-Date) - (Get-Item -LiteralPath $destino).LastWriteTime
    if ($idade.TotalHours -lt $IntervaloHoras) {
        Write-Verbose "Arquivo com $([math]::Round($idade.TotalHours, 1)) h; coleta pulada."
        return
    }
}

$opcoes = @{ IncluirAtivacao = $true }
if ($SemSoftware) { $opcoes.SemSoftware = $true }
$maquina = Get-InventarioMaquina @opcoes
if (-not $maquina.Online) { throw "Coleta local falhou: $($maquina.Erro)" }

$temporario = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "inventario-$([guid]::NewGuid().ToString('N'))"
try {
    $null = Export-InventarioRelatorio -InputObject $maquina -Path $temporario -Formato JSON -NomeBase $env:COMPUTERNAME
    $gerado = Join-Path -Path $temporario -ChildPath "$($env:COMPUTERNAME).json"

    $parcial = "$destino.tmp"
    Copy-Item -LiteralPath $gerado -Destination $parcial -Force
    Move-Item -LiteralPath $parcial -Destination $destino -Force
}
finally {
    Remove-Item -LiteralPath $temporario -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Verbose "Gravado: $destino"
