function Get-NomesDeArquivo {
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)][string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Arquivo de computadores nao encontrado: $Path"
    }

    Get-Content -LiteralPath $Path |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ -and -not $_.StartsWith('#') }
}

function Get-NomesDoAD {
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)][string]$OrganizationalUnit
    )

    if (-not (Get-Command -Name Get-ADComputer -ErrorAction SilentlyContinue)) {
        throw 'O modulo ActiveDirectory (RSAT) nao esta disponivel. Instale o RSAT ou use -ComputerName / -Path.'
    }

    Get-ADComputer -SearchBase $OrganizationalUnit -Filter 'Enabled -eq $true' |
        Select-Object -ExpandProperty Name
}

function Resolve-AlvoInventario {
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [string[]]$ComputerName,
        [string]$Path,
        [string]$OrganizationalUnit
    )

    $nomes = @()
    if ($ComputerName) { $nomes += $ComputerName }
    if ($Path) { $nomes += Get-NomesDeArquivo -Path $Path }
    if ($OrganizationalUnit) { $nomes += Get-NomesDoAD -OrganizationalUnit $OrganizationalUnit }

    $nomes |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        ForEach-Object { $_.Trim() } |
        Sort-Object -Unique
}
