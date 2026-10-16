<#
.SYNOPSIS
    Regenera docs/exemplo-relatorio.html a partir de dados ficticios.
#>
[CmdletBinding()]
param(
    [string]$Destino
)

if (-not $Destino) { $Destino = Join-Path $PSScriptRoot '..\docs' }

. (Join-Path $PSScriptRoot 'DadosExemplo.ps1')
Import-Module (Join-Path $PSScriptRoot '..\InventarioTI\InventarioTI.psd1') -Force

$null = New-Item -Path $Destino -ItemType Directory -Force
Get-DadosExemplo |
    Export-InventarioRelatorio -Path $Destino -Formato HTML -NomeBase 'exemplo-relatorio' -Titulo 'Inventário de TI - exemplo'
