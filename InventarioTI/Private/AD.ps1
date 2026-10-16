# Descoberta de computadores no Active Directory sem RSAT, via ADSI (System.DirectoryServices),
# com fallback para Get-ADComputer quando o modulo existir.
# As conversoes sao puras e cobertas por tests/AD.Tests.ps1.

$script:DiasInatividadeADPadrao = 90

function Split-DistinguishedName {
    # Quebra o DN em RDNs respeitando virgula escapada ("OU=Vendas\, Sul"). O texto volta sem a barra de escape.
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)][string]$DistinguishedName
    )

    $partes = [System.Collections.Generic.List[string]]::new()
    $atual = [System.Text.StringBuilder]::new()
    $escapado = $false

    foreach ($c in $DistinguishedName.ToCharArray()) {
        if ($escapado) { [void]$atual.Append($c); $escapado = $false; continue }
        if ($c -eq [char]'\') { $escapado = $true; continue }
        if ($c -eq [char]',') { $partes.Add($atual.ToString().Trim()); [void]$atual.Clear(); continue }
        [void]$atual.Append($c)
    }
    $partes.Add($atual.ToString().Trim())
    $partes.ToArray()
}

function ConvertTo-OuDeDn {
    # 'CN=PC-01,OU=Estacoes,OU=Financeiro,DC=contoso,DC=local' -> 'contoso.local/Financeiro/Estacoes'
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowNull()][AllowEmptyString()][string]$DistinguishedName
    )

    if ([string]::IsNullOrWhiteSpace($DistinguishedName)) { return '' }

    $rdns = @(Split-DistinguishedName -DistinguishedName $DistinguishedName)
    $dominio = [System.Collections.Generic.List[string]]::new()
    $caminho = [System.Collections.Generic.List[string]]::new()

    # O primeiro RDN e o proprio objeto.
    for ($i = 1; $i -lt $rdns.Count; $i++) {
        $posicao = $rdns[$i].IndexOf('=')
        if ($posicao -lt 1) { continue }
        $tipo = $rdns[$i].Substring(0, $posicao).Trim().ToUpperInvariant()
        $valor = $rdns[$i].Substring($posicao + 1).Trim()
        switch ($tipo) {
            'DC' { $dominio.Add($valor) }
            { $_ -in 'OU', 'CN' } { $caminho.Add($valor) }
        }
    }

    $caminho.Reverse()
    $itens = [System.Collections.Generic.List[string]]::new()
    if ($dominio.Count -gt 0) { $itens.Add($dominio -join '.') }
    $itens.AddRange($caminho)
    $itens -join '/'
}

function Test-ContaDesativada {
    # Bit 2 (ACCOUNTDISABLE) do userAccountControl.
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [AllowNull()][object]$UserAccountControl
    )

    if ($null -eq $UserAccountControl) { return $false }
    (([long]$UserAccountControl -band 2) -ne 0)
}

function ConvertFrom-FileTimeAd {
    # lastLogonTimestamp vem em FILETIME (100 ns desde 1601). 0 e Int64.MaxValue significam "nunca".
    [CmdletBinding()]
    [OutputType([datetime])]
    param(
        [AllowNull()][object]$Valor
    )

    if ($null -eq $Valor) { return $null }
    $ticks = [long]$Valor
    if ($ticks -le 0 -or $ticks -eq [long]::MaxValue) { return $null }
    [datetime]::FromFileTimeUtc($ticks).ToLocalTime()
}

function Test-InativoAD {
    # Sem logon ha mais de -Dias dias. Sem nenhum logon registrado, vale a data de criacao da conta.
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [AllowNull()][object]$UltimoLogon,
        [AllowNull()][object]$CriadoEm,
        [datetime]$DataReferencia = (Get-Date),
        [int]$Dias = $script:DiasInatividadeADPadrao
    )

    if ($null -ne $UltimoLogon) {
        return (($DataReferencia - [datetime]$UltimoLogon).TotalDays -gt $Dias)
    }
    if ($null -ne $CriadoEm) {
        return (($DataReferencia - [datetime]$CriadoEm).TotalDays -gt $Dias)
    }
    $false
}

function ConvertTo-ComputadorAD {
    # Propriedades LDAP (chaves em minusculas, como o ADSI devolve) -> objeto do inventario.
    [CmdletBinding()]
    [OutputType('InventarioTI.ComputadorAD')]
    param(
        [Parameter(Mandatory)][hashtable]$Propriedades
    )

    $texto = { param($v) if ($null -eq $v -or [string]::IsNullOrWhiteSpace([string]$v)) { $null } else { ([string]$v).Trim() } }

    $criado = $Propriedades['whencreated']
    if ($criado -is [datetime] -and $criado.Kind -eq [System.DateTimeKind]::Utc) { $criado = $criado.ToLocalTime() }
    if ($null -ne $criado -and $criado -isnot [datetime]) { $criado = $null }

    $dn = & $texto $Propriedades['distinguishedname']

    [pscustomobject]@{
        PSTypeName           = 'InventarioTI.ComputadorAD'
        Nome                 = & $texto $Propriedades['name']
        DNSHostName          = & $texto $Propriedades['dnshostname']
        SistemaOperacionalAD = & $texto $Propriedades['operatingsystem']
        VersaoSOAD           = & $texto $Propriedades['operatingsystemversion']
        UltimoLogonAD        = ConvertFrom-FileTimeAd -Valor $Propriedades['lastlogontimestamp']
        CriadoEm             = $criado
        Descricao            = & $texto $Propriedades['description']
        OU                   = ConvertTo-OuDeDn -DistinguishedName $dn
        Habilitado           = -not (Test-ContaDesativada -UserAccountControl $Propriedades['useraccountcontrol'])
    }
}

function Invoke-BuscaLdap {
    # Unico ponto que toca o LDAP; devolve uma hashtable de propriedades por computador.
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [string]$SearchBase,
        [switch]$IncluirDesativados
    )

    $filtro = '(&(objectCategory=computer)(objectClass=computer)'
    if (-not $IncluirDesativados) { $filtro += '(!(userAccountControl:1.2.840.113556.1.4.803:=2))' }
    $filtro += ')'

    $propriedades = [string[]]@(
        'name', 'dnshostname', 'operatingsystem', 'operatingsystemversion', 'lastlogontimestamp',
        'whencreated', 'description', 'distinguishedname', 'useraccountcontrol'
    )

    $raiz = $null
    $buscador = $null
    $resultados = $null
    try {
        if ($SearchBase) {
            $caminho = if ($SearchBase -like 'LDAP://*') { $SearchBase } else { "LDAP://$SearchBase" }
            $raiz = [System.DirectoryServices.DirectoryEntry]::new($caminho)
        }

        $buscador = [System.DirectoryServices.DirectorySearcher]::new()
        if ($raiz) { $buscador.SearchRoot = $raiz }
        $buscador.Filter = $filtro
        $buscador.PageSize = 1000
        $buscador.ServerTimeLimit = [timespan]::FromSeconds(60)
        $buscador.PropertiesToLoad.AddRange($propriedades)

        $resultados = $buscador.FindAll()
        foreach ($r in $resultados) {
            $p = @{}
            foreach ($nome in $r.Properties.PropertyNames) {
                $valores = $r.Properties[$nome]
                if ($valores.Count -gt 0) { $p[$nome] = $valores[0] }
            }
            $p
        }
    }
    finally {
        if ($resultados) { $resultados.Dispose() }
        if ($buscador) { $buscador.Dispose() }
        if ($raiz) { $raiz.Dispose() }
    }
}

function Get-ComputadoresAD {
    <#
    Lista os computadores do dominio do usuario atual. Usa ADSI (nao precisa de RSAT);
    se falhar e o modulo ActiveDirectory existir, tenta Get-ADComputer.
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [string]$SearchBase,
        [switch]$IncluirDesativados
    )

    $erroAdsi = $null
    try {
        $brutos = @(Invoke-BuscaLdap -SearchBase $SearchBase -IncluirDesativados:$IncluirDesativados)
        return @($brutos | ForEach-Object { ConvertTo-ComputadorAD -Propriedades $_ } | Sort-Object -Property Nome)
    }
    catch {
        $erroAdsi = ($_.Exception.Message -replace '\s+', ' ').Trim()
        Write-Verbose "ADSI falhou: $erroAdsi"
    }

    if (Get-Command -Name Get-ADComputer -ErrorAction SilentlyContinue) {
        try {
            $parametros = @{
                Filter      = if ($IncluirDesativados) { '*' } else { 'Enabled -eq $true' }
                Properties  = @('DNSHostName', 'OperatingSystem', 'OperatingSystemVersion', 'LastLogonTimestamp', 'whenCreated', 'Description', 'userAccountControl')
                ErrorAction = 'Stop'
            }
            if ($SearchBase) { $parametros.SearchBase = $SearchBase }

            return @(Get-ADComputer @parametros | ForEach-Object {
                    ConvertTo-ComputadorAD -Propriedades @{
                        name                   = $_.Name
                        dnshostname            = $_.DNSHostName
                        operatingsystem        = $_.OperatingSystem
                        operatingsystemversion = $_.OperatingSystemVersion
                        lastlogontimestamp     = $_.LastLogonTimestamp
                        whencreated            = $_.whenCreated
                        description            = $_.Description
                        distinguishedname      = $_.DistinguishedName
                        useraccountcontrol     = $_.userAccountControl
                    }
                } | Sort-Object -Property Nome)
        }
        catch {
            $erroAdsi = "$erroAdsi; Get-ADComputer: $($_.Exception.Message.Trim())"
        }
    }

    throw "Nao foi possivel consultar o Active Directory ($erroAdsi). O computador precisa estar em um dominio e alcancar um controlador de dominio. Sem dominio, use -ComputerName ou -Path."
}
