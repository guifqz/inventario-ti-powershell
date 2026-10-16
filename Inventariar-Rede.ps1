<#
.SYNOPSIS
    Inventario completo da rede em um comando: descobre no AD, coleta, mescla e gera CSV, JSON e HTML.

.DESCRIPTION
    Sem -ComputerName nem -Path, descobre os computadores no Active Directory (sem precisar de RSAT),
    sonda a rede, coleta por WinRM com fallback para DCOM, mescla as coletas locais (opcional, de
    -PastaColetaLocal) e grava os relatorios em -Saida. Ao final abre o HTML e mostra um resumo.

.PARAMETER Saida
    Pasta onde CSV, JSON e HTML serao gravados (criada se nao existir).

.PARAMETER PastaColetaLocal
    Pasta com os JSON de tools\Coletar-Local.ps1, ex.: \\srv01\Ativos.

.PARAMETER SearchBase
    DN de uma OU para limitar a busca no AD, ex.: 'OU=Estacoes,DC=contoso,DC=local'.

.PARAMETER ComputerName
    Lista explicita de computadores (em vez de descobrir no AD).

.PARAMETER Path
    Arquivo texto com um computador por linha (em vez de descobrir no AD).

.PARAMETER Credential
    Credencial para as sessoes remotas. Padrao: o usuario atual.

.PARAMETER ThrottleLimit
    Maquinas coletadas ao mesmo tempo. Padrao: 24.

.PARAMETER SemSoftware
    Nao lista software instalado (bem mais rapido; Office e acesso remoto ficam vazios).

.PARAMETER IncluirDesativados
    Inclui contas de computador desativadas no AD.

.PARAMETER LimiteDisco
    Percentual livre abaixo do qual o disco alerta. Padrao: 15.

.PARAMETER Titulo
    Titulo do relatorio HTML.

.PARAMETER NaoAbrir
    Nao abre o HTML ao terminar.

.PARAMETER PassThru
    Devolve os objetos do inventario no pipeline.

.EXAMPLE
    .\Inventariar-Rede.ps1 -Saida C:\Inventario

.EXAMPLE
    .\Inventariar-Rede.ps1 -Saida C:\Inventario -PastaColetaLocal \\srv01\Ativos -SearchBase 'OU=Estacoes,DC=contoso,DC=local' -ThrottleLimit 32
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Saida,

    [string]$PastaColetaLocal,

    [string]$SearchBase,

    [string[]]$ComputerName,

    [string]$Path,

    [pscredential]$Credential,

    [ValidateRange(1, 128)]
    [int]$ThrottleLimit = 24,

    [switch]$SemSoftware,

    [switch]$IncluirDesativados,

    [ValidateRange(1, 99)]
    [double]$LimiteDisco = 15,

    [string]$Titulo = 'Inventário de TI',

    [switch]$NaoAbrir,

    [switch]$PassThru
)

$ErrorActionPreference = 'Stop'
$InformationPreference = 'Continue'

Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'InventarioTI\InventarioTI.psd1') -Force

$parametros = @{
    ThrottleLimit   = $ThrottleLimit
    IncluirAtivacao = $true
}
if ($ComputerName) { $parametros.ComputerName = $ComputerName }
if ($Path) { $parametros.Path = $Path }
if (-not $ComputerName -and -not $Path) { $parametros.DoAD = $true }
if ($SearchBase) { $parametros.OrganizationalUnit = $SearchBase }
if ($PastaColetaLocal) { $parametros.PastaColetaLocal = $PastaColetaLocal }
if ($Credential) { $parametros.Credential = $Credential }
if ($SemSoftware) { $parametros.SemSoftware = $true }
if ($IncluirDesativados) { $parametros.IncluirDesativados = $true }

$inicio = Get-Date
try {
    $inventario = @(Invoke-InventarioRede @parametros)
}
catch {
    Write-Error "Inventário interrompido: $($_.Exception.Message)" -ErrorAction Continue
    exit 1
}
$duracao = (Get-Date) - $inicio

$arquivos = @($inventario | Export-InventarioRelatorio -Path $Saida -LimiteDisco $LimiteDisco -Titulo $Titulo)
$html = $arquivos | Where-Object Extension -eq '.html' | Select-Object -First 1

$resumo = & (Get-Module -Name InventarioTI) { param($Dados, $Limite) Get-ResumoInventario -Maquinas $Dados -LimiteDisco $Limite } $inventario $LimiteDisco
$porStatus = $inventario | Group-Object -Property StatusColeta | Sort-Object -Property Count -Descending
$locais = @($inventario | Where-Object { $_.Online -and $_.Fonte -eq 'Local' }).Count

Write-Information ''
Write-Information ('Inventário concluído em {0:N0} s' -f $duracao.TotalSeconds)
Write-Information ('  Máquinas:            {0} ({1} no AD)' -f $resumo.Total, $resumo.NoAD)
Write-Information ('  Inventariadas:       {0} ({1} via coletor local)' -f $resumo.Online, $locais)
foreach ($g in $porStatus) {
    if ($g.Name -ne 'Coletado') { Write-Information ('  {0,-20} {1}' -f ($g.Name + ':'), $g.Count) }
}
Write-Information ('  SO fora de suporte:  {0}' -f $resumo.SOForaSuporte)
Write-Information ('  Disco < {0}% livre:   {1}' -f $LimiteDisco, $resumo.DiscoBaixo)
Write-Information ('  Sem antivírus ativo: {0}' -f $resumo.SemAntivirus)
Write-Information ('  Windows não ativado: {0}' -f $resumo.NaoAtivado)
Write-Information ('  RAM baixa / HDD:     {0} / {1}' -f $resumo.RAMBaixa, $resumo.HDDSistema)
Write-Information ('  Possivelmente inativos no AD: {0}' -f $resumo.PossivelmenteInativo)
Write-Information ''
$arquivos | ForEach-Object { Write-Information "  $($_.FullName)" }

if ($html -and -not $NaoAbrir) { Invoke-Item -LiteralPath $html.FullName }
if ($PassThru) { $inventario }
