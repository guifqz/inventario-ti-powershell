# Funcoes puras de decodificacao e deteccao a partir dos dados coletados.
# Sem acesso a CIM, disco ou rede. Cobertas por tests/Decodificacao.Tests.ps1.

$script:FabricantesMonitor = @{
    ACI = 'Asus'; ACR = 'Acer'; AOC = 'AOC'; AUS = 'Asus'; AUO = 'AU Optronics'; BNQ = 'BenQ'
    CMN = 'Chimei Innolux'; DEL = 'Dell'; GSM = 'LG'; HPN = 'HP'; HWP = 'HP'; IVM = 'Iiyama'
    LEN = 'Lenovo'; LGD = 'LG Display'; MSI = 'MSI'; NEC = 'NEC'; PHL = 'Philips'; SAM = 'Samsung'
    SEC = 'Samsung'; SNY = 'Sony'; VSC = 'ViewSonic'; BOE = 'BOE'
}

# Padrao de nome no Uninstall -> nome exibido. Ordem nao importa, cada item e avaliado.
$script:FerramentasAcessoRemoto = @(
    @{ Nome = 'AnyDesk';                 Padrao = 'AnyDesk' }
    @{ Nome = 'TeamViewer';              Padrao = 'TeamViewer' }
    @{ Nome = 'RustDesk';                Padrao = 'RustDesk' }
    @{ Nome = 'UltraViewer';             Padrao = 'UltraViewer' }
    @{ Nome = 'VNC';                     Padrao = 'VNC (Server|Viewer|Connect)|TightVNC|UltraVNC|RealVNC' }
    @{ Nome = 'Chrome Remote Desktop';   Padrao = 'Chrome Remote Desktop' }
    @{ Nome = 'LogMeIn';                 Padrao = 'LogMeIn' }
    @{ Nome = 'Splashtop';               Padrao = 'Splashtop' }
    @{ Nome = 'Ammyy';                   Padrao = 'Ammyy' }
    @{ Nome = 'Radmin';                  Padrao = 'Radmin' }
    @{ Nome = 'ScreenConnect';           Padrao = 'ScreenConnect|ConnectWise Control' }
    @{ Nome = 'Supremo';                 Padrao = 'Supremo' }
    @{ Nome = 'Zoho Assist';             Padrao = 'Zoho Assist' }
    @{ Nome = 'DWService';               Padrao = 'DWAgent|DWService' }
    @{ Nome = 'RemotePC';                Padrao = 'RemotePC' }
    @{ Nome = 'NoMachine';               Padrao = 'NoMachine' }
)

function ConvertFrom-ProductState {
    # productState do SecurityCenter2: bit 0x1000 = scanner ligado, bit 0x10 = assinaturas desatualizadas.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][uint32]$Estado
    )

    [pscustomobject]@{
        Ativo      = (($Estado -band 0x1000) -ne 0)
        Atualizado = (($Estado -band 0x10) -eq 0)
    }
}

function ConvertFrom-ArrayUInt16 {
    # WmiMonitorID devolve textos como uint16[] terminado em 0.
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowNull()][object]$Valor
    )

    if ($null -eq $Valor) { return $null }

    $texto = [System.Text.StringBuilder]::new()
    foreach ($v in @($Valor)) {
        if ([int]$v -eq 0) { break }
        [void]$texto.Append([char][int]$v)
    }
    $resultado = $texto.ToString().Trim()
    if ($resultado) { $resultado } else { $null }
}

function Get-NomeFabricanteMonitor {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowNull()][AllowEmptyString()][string]$Codigo
    )

    if ([string]::IsNullOrWhiteSpace($Codigo)) { return $null }
    $nome = $script:FabricantesMonitor[$Codigo.Trim().ToUpperInvariant()]
    if ($nome) { $nome } else { $Codigo.Trim() }
}

function ConvertTo-TipoMemoria {
    # SMBIOSMemoryType de Win32_PhysicalMemory.
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowNull()][object]$Codigo
    )

    if ($null -eq $Codigo) { return $null }
    switch ([int]$Codigo) {
        17 { 'SDRAM' }
        20 { 'DDR' }
        21 { 'DDR2' }
        24 { 'DDR3' }
        26 { 'DDR4' }
        27 { 'LPDDR' }
        28 { 'LPDDR2' }
        29 { 'LPDDR3' }
        30 { 'LPDDR4' }
        34 { 'DDR5' }
        35 { 'LPDDR5' }
        default { $null }
    }
}

function ConvertTo-TipoDisco {
    # MediaType de MSFT_PhysicalDisk.
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowNull()][object]$MediaType
    )

    if ($null -eq $MediaType) { return 'Desconhecido' }
    switch ([int]$MediaType) {
        3 { 'HDD' }
        4 { 'SSD' }
        5 { 'SCM' }
        default { 'Desconhecido' }
    }
}

function ConvertTo-SaudeDisco {
    # HealthStatus de MSFT_PhysicalDisk. Devolve $null quando o Windows nao informa.
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowNull()][object]$HealthStatus
    )

    if ($null -eq $HealthStatus) { return $null }
    switch ([int]$HealthStatus) {
        0 { 'Healthy' }
        1 { 'Warning' }
        2 { 'Unhealthy' }
        default { 'Unknown' }
    }
}

function Get-DiasLigado {
    [CmdletBinding()]
    [OutputType([double])]
    param(
        [AllowNull()][object]$UltimoBoot,
        [datetime]$DataReferencia = (Get-Date)
    )

    if ($null -eq $UltimoBoot) { return $null }
    [math]::Round(($DataReferencia - [datetime]$UltimoBoot).TotalDays, 1)
}

function Get-VersaoOffice {
    # Procura o produto Office na lista de software, ignorando componentes (idioma, MUI, licenciamento...).
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowNull()][AllowEmptyCollection()][object[]]$Software
    )

    $exclui = 'MUI|Shared|Proofing|Language|Update|Licensing|Visio|Project|Teams|OneDrive|Component|Runtime|Interop|Viewer|Compatibility|Connector|Add-?in|Services|Redistributable|Setup Metadata'
    $candidatos = @($Software | Where-Object {
            $null -ne $_ -and $_.Nome -match '^Microsoft (Office|365)' -and $_.Nome -notmatch $exclui
        } | ForEach-Object { $_.Nome.Trim() })

    if ($candidatos.Count -eq 0) { return $null }

    $preferido = $candidatos | Where-Object { $_ -match '365|20\d\d' } | Select-Object -First 1
    if ($preferido) { $preferido } else { $candidatos[0] }
}

function Get-FerramentasAcessoRemoto {
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [AllowNull()][AllowEmptyCollection()][object[]]$Software
    )

    $nomes = @($Software | Where-Object { $null -ne $_ } | ForEach-Object { [string]$_.Nome })
    foreach ($ferramenta in $script:FerramentasAcessoRemoto) {
        if (@($nomes | Where-Object { $_ -match $ferramenta.Padrao }).Count -gt 0) { $ferramenta.Nome }
    }
}
