function Get-MapaTipoDisco {
    # Letra da unidade -> 'SSD' | 'HDD' | 'SCM'. Depende do namespace Storage (Windows 8 / Server 2012 em diante).
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [object]$Sessao
    )

    $mapa = @{}
    try {
        $namespace = 'root\Microsoft\Windows\Storage'
        $fisicos = @{}
        foreach ($f in Get-DadosCim -ClassName MSFT_PhysicalDisk -Namespace $namespace -Sessao $Sessao) {
            $fisicos[[string]$f.DeviceId] = switch ([int]$f.MediaType) {
                3 { 'HDD' }
                4 { 'SSD' }
                5 { 'SCM' }
                default { 'Desconhecido' }
            }
        }

        foreach ($p in Get-DadosCim -ClassName MSFT_Partition -Namespace $namespace -Sessao $Sessao) {
            if ($p.DriveLetter -and $p.DriveLetter -ne [char]0) {
                $tipo = $fisicos[[string]$p.DiskNumber]
                if ($tipo) { $mapa["$($p.DriveLetter):"] = $tipo }
            }
        }
    }
    catch {
        Write-Verbose "Tipo de disco indisponivel: $($_.Exception.Message)"
    }
    $mapa
}

function Get-DiscosMaquina {
    [CmdletBinding()]
    param(
        [object]$Sessao
    )

    $tipos = Get-MapaTipoDisco -Sessao $Sessao

    # DriveType 3 = disco local fixo
    foreach ($d in Get-DadosCim -ClassName Win32_LogicalDisk -Filter 'DriveType = 3' -Sessao $Sessao) {
        $tipo = $tipos[[string]$d.DeviceID]
        if (-not $tipo) { $tipo = 'Desconhecido' }

        [pscustomobject]@{
            Unidade         = $d.DeviceID
            Rotulo          = $d.VolumeName
            TamanhoGB       = Format-TamanhoGB -Bytes $d.Size
            LivreGB         = Format-TamanhoGB -Bytes $d.FreeSpace
            PercentualLivre = Get-PercentualLivre -TamanhoBytes $d.Size -LivreBytes $d.FreeSpace
            Tipo            = $tipo
        }
    }
}

function Get-StatusAtivacao {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [object]$Sessao
    )

    # ApplicationId fixo do Windows no SoftwareLicensingProduct
    $filtro = "ApplicationId = '55c92734-d682-4d71-983e-d6ec3f16059f' AND PartialProductKey IS NOT NULL"
    try {
        $licenca = Get-DadosCim -ClassName SoftwareLicensingProduct -Filter $filtro -Sessao $Sessao | Select-Object -First 1
    }
    catch {
        return 'Indisponivel'
    }

    if (-not $licenca) { return 'Sem licenca' }

    switch ([int]$licenca.LicenseStatus) {
        0 { 'Nao licenciado' }
        1 { 'Ativado' }
        2 { 'Periodo de carencia inicial' }
        3 { 'Periodo de carencia adicional' }
        4 { 'Periodo de carencia (nao genuino)' }
        5 { 'Notificacao' }
        6 { 'Periodo de carencia estendido' }
        default { 'Desconhecido' }
    }
}
