function Invoke-ColetaSegura {
    # Cada consulta opcional falha sozinha: devolve $null e segue a coleta.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][scriptblock]$Bloco,
        [string]$Rotulo = 'consulta'
    )

    try { & $Bloco }
    catch { Write-Verbose "${Rotulo} indisponivel: $($_.Exception.Message.Trim())" }
}

function Get-MapaDiscoFisico {
    # Letra da unidade -> @{ Tipo; Saude }. Depende do namespace Storage (Windows 8 / Server 2012 em diante).
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
            $fisicos[[string]$f.DeviceId] = @{
                Tipo  = ConvertTo-TipoDisco -MediaType $f.MediaType
                Saude = ConvertTo-SaudeDisco -HealthStatus $f.HealthStatus
            }
        }

        foreach ($p in Get-DadosCim -ClassName MSFT_Partition -Namespace $namespace -Sessao $Sessao) {
            if ($p.DriveLetter -and $p.DriveLetter -ne [char]0) {
                $fisico = $fisicos[[string]$p.DiskNumber]
                if ($fisico) { $mapa["$($p.DriveLetter):"] = $fisico }
            }
        }
    }
    catch {
        Write-Verbose "Tipo e saude dos discos indisponiveis: $($_.Exception.Message)"
    }
    $mapa
}

function Get-DiscosMaquina {
    [CmdletBinding()]
    param(
        [object]$Sessao,
        [string]$UnidadeSistema
    )

    $fisicos = Get-MapaDiscoFisico -Sessao $Sessao

    # DriveType 3 = disco local fixo
    foreach ($d in Get-DadosCim -ClassName Win32_LogicalDisk -Filter 'DriveType = 3' -Sessao $Sessao) {
        $fisico = $fisicos[[string]$d.DeviceID]

        [pscustomobject]@{
            Unidade         = $d.DeviceID
            Rotulo          = $d.VolumeName
            TamanhoGB       = Format-TamanhoGB -Bytes $d.Size
            LivreGB         = Format-TamanhoGB -Bytes $d.FreeSpace
            PercentualLivre = Get-PercentualLivre -TamanhoBytes $d.Size -LivreBytes $d.FreeSpace
            Tipo            = if ($fisico) { $fisico.Tipo } else { 'Desconhecido' }
            Saude           = if ($fisico) { $fisico.Saude } else { $null }
            Sistema         = ($UnidadeSistema -and $d.DeviceID -eq $UnidadeSistema)
        }
    }
}

function Get-MemoriaMaquina {
    [CmdletBinding()]
    param(
        [object]$Sessao
    )

    $modulos = @(Get-DadosCim -ClassName Win32_PhysicalMemory -Sessao $Sessao)
    $matrizes = @(Get-DadosCim -ClassName Win32_PhysicalMemoryArray -Sessao $Sessao | Where-Object { $null -eq $_.Use -or $_.Use -eq 3 })

    $velocidade = $modulos | ForEach-Object { if ($_.ConfiguredClockSpeed) { $_.ConfiguredClockSpeed } else { $_.Speed } } |
        Where-Object { $_ } | Measure-Object -Maximum
    $codigoTipo = $modulos | ForEach-Object { if ($_.SMBIOSMemoryType) { $_.SMBIOSMemoryType } else { $_.MemoryType } } |
        Where-Object { $_ } | Select-Object -First 1
    $totalSlots = ($matrizes | Measure-Object -Property MemoryDevices -Sum).Sum

    [pscustomobject]@{
        SlotsUsados   = $modulos.Count
        SlotsTotal    = if ($totalSlots) { [int]$totalSlots } else { $null }
        VelocidadeMHz = if ($velocidade.Count -gt 0) { [int]$velocidade.Maximum } else { $null }
        Tipo          = ConvertTo-TipoMemoria -Codigo $codigoTipo
    }
}

function Get-AntivirusMaquina {
    # $null = SecurityCenter2 indisponivel (servidor, Windows antigo). Lista vazia = nenhum antivirus registrado.
    [CmdletBinding()]
    [OutputType([System.Array])]
    param(
        [object]$Sessao
    )

    $produtos = @(Get-DadosCim -ClassName AntiVirusProduct -Namespace 'root\SecurityCenter2' -Sessao $Sessao)
    $itens = @(foreach ($p in $produtos) {
        $estado = ConvertFrom-ProductState -Estado ([uint32]$p.productState)
        [pscustomobject]@{ Nome = $p.displayName; Ativo = $estado.Ativo; Atualizado = $estado.Atualizado }
    })
    , $itens
}

function Get-MonitoresMaquina {
    [CmdletBinding()]
    [OutputType([System.Array])]
    param(
        [object]$Sessao
    )

    $monitores = @(foreach ($m in Get-DadosCim -ClassName WmiMonitorID -Namespace 'root\wmi' -Sessao $Sessao) {
        $codigo = ConvertFrom-ArrayUInt16 -Valor $m.ManufacturerName
        $modelo = ConvertFrom-ArrayUInt16 -Valor $m.UserFriendlyName
        if (-not $modelo) { $modelo = ConvertFrom-ArrayUInt16 -Valor $m.ProductCodeID }

        [pscustomobject]@{
            Fabricante = Get-NomeFabricanteMonitor -Codigo $codigo
            Modelo     = $modelo
            Serial     = ConvertFrom-ArrayUInt16 -Valor $m.SerialNumberID
        }
    })
    , $monitores
}

function Get-AdaptadoresRede {
    [CmdletBinding()]
    param(
        [object]$Sessao
    )

    $ipv4 = '^\d{1,3}(\.\d{1,3}){3}$'
    foreach ($a in Get-DadosCim -ClassName Win32_NetworkAdapterConfiguration -Filter 'IPEnabled = TRUE' -Sessao $Sessao) {
        $ips = @($a.IPAddress | Where-Object { $_ -match $ipv4 })
        if ($ips.Count -eq 0) { continue }

        [pscustomobject]@{
            Nome    = $a.Description
            IP      = $ips -join ', '
            MAC     = $a.MACAddress
            DHCP    = [bool]$a.DHCPEnabled
            Gateway = $a.DefaultIPGateway | Where-Object { $_ -match $ipv4 } | Select-Object -First 1
        }
    }
}

function Get-RebootPendente {
    # Chaves de "reinicio pendente" do Windows Update e do servicing, lidas via StdRegProv.
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [object]$Sessao
    )

    $verificacoes = @(
        @{ Pai = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing'; Chave = 'RebootPending' }
        @{ Pai = 'SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update'; Chave = 'RebootRequired' }
    )

    $pendente = $false
    $consultou = $false
    foreach ($v in $verificacoes) {
        try {
            $filhos = (Invoke-RegistroCim -Metodo EnumKey -SubChave $v.Pai -Sessao $Sessao).sNames
            $consultou = $true
            if ($filhos -contains $v.Chave) { $pendente = $true }
        }
        catch { Write-Verbose "Reboot pendente: $($_.Exception.Message)" }
    }

    if (-not $consultou) { throw 'Registro indisponivel' }
    $pendente
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
        0 { 'Não licenciado' }
        1 { 'Ativado' }
        2 { 'Período de carência inicial' }
        3 { 'Período de carência adicional' }
        4 { 'Período de carência (não genuíno)' }
        5 { 'Notificação' }
        6 { 'Período de carência estendido' }
        default { 'Desconhecido' }
    }
}

function Invoke-ColetaMaquina {
    # Preenche o registro com todos os dados. CS e SO sao obrigatorios (falha aqui vira erro da maquina);
    # o restante falha de forma independente e fica $null.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Maquina,
        [object]$Sessao,
        [switch]$SemSoftware,
        [switch]$IncluirAtivacao
    )

    $sistema = Get-DadosCim -ClassName Win32_ComputerSystem -Sessao $Sessao | Select-Object -First 1
    $os = Get-DadosCim -ClassName Win32_OperatingSystem -Sessao $Sessao | Select-Object -First 1

    $Maquina.Online = $true
    $Maquina.Erro = $null
    $Maquina.StatusColeta = 'Coletado'
    $Maquina.Mensagem = Get-MensagemStatus -StatusColeta 'Coletado'
    $Maquina.Hostname = $sistema.Name
    $Maquina.Usuario = $sistema.UserName
    $Maquina.Fabricante = $sistema.Manufacturer
    $Maquina.Modelo = $sistema.Model
    $Maquina.RAMGB = [math]::Round($sistema.TotalPhysicalMemory / 1GB, 1)
    $Maquina.SistemaOperacional = $os.Caption.Trim()
    $Maquina.VersaoSO = $os.Version
    $Maquina.BuildSO = $os.BuildNumber
    $Maquina.Arquitetura = $os.OSArchitecture
    $Maquina.InstaladoEm = $os.InstallDate
    $Maquina.UltimoBoot = $os.LastBootUpTime
    $Maquina.UptimeDias = Get-DiasLigado -UltimoBoot $os.LastBootUpTime

    $bios = Invoke-ColetaSegura -Rotulo 'BIOS' -Bloco { Get-DadosCim -ClassName Win32_BIOS -Sessao $Sessao | Select-Object -First 1 }
    if ($bios) {
        $Maquina.Serial = $bios.SerialNumber
        $Maquina.BiosVersao = $bios.SMBIOSBIOSVersion
        $Maquina.BiosData = $bios.ReleaseDate
    }

    $processadores = @(Invoke-ColetaSegura -Rotulo 'CPU' -Bloco { Get-DadosCim -ClassName Win32_Processor -Sessao $Sessao })
    if ($processadores.Count -gt 0) {
        $Maquina.CPU = ([string]$processadores[0].Name).Trim()
        $Maquina.CPUNucleos = ($processadores | Measure-Object -Property NumberOfCores -Sum).Sum
        $Maquina.CPUThreads = ($processadores | Measure-Object -Property NumberOfLogicalProcessors -Sum).Sum
    }

    $memoria = Invoke-ColetaSegura -Rotulo 'Memoria' -Bloco { Get-MemoriaMaquina -Sessao $Sessao }
    if ($memoria) {
        $Maquina.RAMSlotsUsados = $memoria.SlotsUsados
        $Maquina.RAMSlotsTotal = $memoria.SlotsTotal
        $Maquina.RAMVelocidadeMHz = $memoria.VelocidadeMHz
        $Maquina.RAMTipo = $memoria.Tipo
    }

    $discos = @(Invoke-ColetaSegura -Rotulo 'Discos' -Bloco { Get-DiscosMaquina -Sessao $Sessao -UnidadeSistema $os.SystemDrive })
    $Maquina.Discos = $discos

    $adaptadores = @(Invoke-ColetaSegura -Rotulo 'Rede' -Bloco { Get-AdaptadoresRede -Sessao $Sessao })
    $Maquina.Adaptadores = $adaptadores
    $principal = @($adaptadores | Where-Object { $_.Gateway }) + $adaptadores | Select-Object -First 1
    if ($principal) {
        $Maquina.IP = ($principal.IP -split ', ')[0]
        $Maquina.MAC = $principal.MAC
    }

    $Maquina.Monitores = Invoke-ColetaSegura -Rotulo 'Monitores' -Bloco { Get-MonitoresMaquina -Sessao $Sessao }
    $Maquina.RebootPendente = Invoke-ColetaSegura -Rotulo 'Reboot pendente' -Bloco { Get-RebootPendente -Sessao $Sessao }

    if ($null -eq $os.ProductType -or $os.ProductType -eq 1) {
        $Maquina.Antivirus = Invoke-ColetaSegura -Rotulo 'Antivirus' -Bloco { Get-AntivirusMaquina -Sessao $Sessao }
    }

    if ($IncluirAtivacao) {
        $Maquina.Ativacao = Get-StatusAtivacao -Sessao $Sessao
    }

    if (-not $SemSoftware) {
        $software = @(Invoke-ColetaSegura -Rotulo 'Software' -Bloco { Get-SoftwareInstalado -Sessao $Sessao | Sort-Object -Property Nome })
        $Maquina.Software = $software
        $Maquina.Office = Get-VersaoOffice -Software $Maquina.Software
        $Maquina.AcessoRemoto = @(Get-FerramentasAcessoRemoto -Software $Maquina.Software)
    }
}
