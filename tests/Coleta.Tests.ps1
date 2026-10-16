BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\InventarioTI\InventarioTI.psd1') -Force
}

Describe 'Get-InventarioMaquina' {
    BeforeAll {
        Mock -ModuleName InventarioTI Get-DadosCim {
            switch ($ClassName) {
                'Win32_ComputerSystem' {
                    [pscustomobject]@{ Name = 'PC-FINANCEIRO-01'; UserName = 'EMPRESA\ana.souza'; Manufacturer = 'Dell Inc.'; Model = 'OptiPlex 3080'; TotalPhysicalMemory = 17179869184 }
                }
                'Win32_BIOS' { [pscustomobject]@{ SerialNumber = 'ABC1234'; SMBIOSBIOSVersion = 'A12'; ReleaseDate = [datetime]'2022-05-10' } }
                'Win32_OperatingSystem' {
                    [pscustomobject]@{
                        Caption = 'Microsoft Windows 11 Pro '; Version = '10.0.22631'; BuildNumber = '22631'
                        InstallDate = [datetime]'2023-03-14'; LastBootUpTime = [datetime]'2026-10-12 07:48'; OSArchitecture = '64-bit'; SystemDrive = 'C:'; ProductType = 1
                    }
                }
                'Win32_Processor' {
                    [pscustomobject]@{ Name = 'Intel(R) Core(TM) i5-10500 '; NumberOfCores = 6; NumberOfLogicalProcessors = 12 }
                }
                'Win32_LogicalDisk' {
                    [pscustomobject]@{ DeviceID = 'C:'; VolumeName = 'Sistema'; Size = 500GB; FreeSpace = 50GB }
                    [pscustomobject]@{ DeviceID = 'D:'; VolumeName = 'Dados'; Size = 1000GB; FreeSpace = 700GB }
                }
                'MSFT_PhysicalDisk' {
                    [pscustomobject]@{ DeviceId = '0'; MediaType = 4; HealthStatus = 0 }
                    [pscustomobject]@{ DeviceId = '1'; MediaType = 3; HealthStatus = 1 }
                }
                'MSFT_Partition' {
                    [pscustomobject]@{ DriveLetter = [char]'C'; DiskNumber = 0 }
                    [pscustomobject]@{ DriveLetter = [char]'D'; DiskNumber = 1 }
                }
                'Win32_NetworkAdapterConfiguration' {
                    [pscustomobject]@{ IPAddress = @('fe80::1', '192.0.2.11'); MACAddress = '00:50:56:AA:00:11'; Description = 'Intel Ethernet'; DHCPEnabled = $true; DefaultIPGateway = @('192.0.2.1') }
                }
                'SoftwareLicensingProduct' { [pscustomobject]@{ LicenseStatus = 1 } }
                'Win32_PhysicalMemory' {
                    [pscustomobject]@{ Capacity = 8GB; ConfiguredClockSpeed = 2666; SMBIOSMemoryType = 26 }
                    [pscustomobject]@{ Capacity = 8GB; ConfiguredClockSpeed = 2666; SMBIOSMemoryType = 26 }
                }
                'Win32_PhysicalMemoryArray' { [pscustomobject]@{ MemoryDevices = 4; Use = 3 } }
                'AntiVirusProduct' { [pscustomobject]@{ displayName = 'Windows Defender'; productState = 397568 } }
                'WmiMonitorID' {
                    [pscustomobject]@{ ManufacturerName = [uint16[]](68, 69, 76, 0); UserFriendlyName = [uint16[]](80, 50, 52, 50, 50, 72, 0, 0); SerialNumberID = [uint16[]](65, 66, 49, 50, 0); ProductCodeID = [uint16[]](52, 49, 0) }
                }
                default { throw "Classe nao simulada: $ClassName" }
            }
        }

        Mock -ModuleName InventarioTI Get-SoftwareInstalado {
            [pscustomobject]@{ Nome = 'Zeta Reader'; Versao = '2.0'; Fabricante = 'Exemplo'; Arquitetura = 'x64' }
            [pscustomobject]@{ Nome = 'Alfa Editor'; Versao = '1.5'; Fabricante = 'Exemplo'; Arquitetura = 'x86' }
        }
        Mock -ModuleName InventarioTI Invoke-RegistroCim {
            [pscustomobject]@{ sNames = @('RebootPending', 'Outra') }
        }
        Mock -ModuleName InventarioTI New-SessaoCim { 'sessao-simulada' }
        Mock -ModuleName InventarioTI Test-HostAtivoParalelo {
            [pscustomobject]@{ Nome = $ComputerName[0]; Respondeu = $true; Via = 'Ping'; WinRM = $true; Rpc = $true }
        }
        Mock -ModuleName InventarioTI Remove-SessaoCim { }
    }

    Context 'maquina local' {
        BeforeAll {
            $script:r = Get-InventarioMaquina -ComputerName $env:COMPUTERNAME -IncluirAtivacao
        }

        It 'devolve um objeto online sem erro' {
            $r.PSObject.TypeNames | Should -Contain 'InventarioTI.Maquina'
            $r.Online | Should -BeTrue
            $r.Erro | Should -BeNullOrEmpty
        }

        It 'preenche hardware e SO' {
            $r.Hostname | Should -Be 'PC-FINANCEIRO-01'
            $r.Usuario | Should -Be 'EMPRESA\ana.souza'
            $r.Serial | Should -Be 'ABC1234'
            $r.CPU | Should -Be 'Intel(R) Core(TM) i5-10500'
            $r.RAMGB | Should -Be 16
            $r.SistemaOperacional | Should -Be 'Microsoft Windows 11 Pro'
            $r.BuildSO | Should -Be '22631'
        }

        It 'calcula discos e tipo SSD/HDD' {
            $r.Discos.Count | Should -Be 2
            $c = $r.Discos | Where-Object Unidade -eq 'C:'
            $c.Tipo | Should -Be 'SSD'
            $c.PercentualLivre | Should -Be 10
            ($r.Discos | Where-Object Unidade -eq 'D:').Tipo | Should -Be 'HDD'
        }

        It 'escolhe o IPv4 e o MAC' {
            $r.IP | Should -Be '192.0.2.11'
            $r.MAC | Should -Be '00:50:56:AA:00:11'
        }

        It 'coleta BIOS, CPU, memoria, uptime e reboot pendente' {
            $r.BiosVersao | Should -Be 'A12'
            $r.CPUThreads | Should -Be 12
            $r.RAMSlotsUsados | Should -Be 2
            $r.RAMSlotsTotal | Should -Be 4
            $r.RAMTipo | Should -Be 'DDR4'
            $r.RAMVelocidadeMHz | Should -Be 2666
            $r.UptimeDias | Should -BeGreaterThan 0
            $r.RebootPendente | Should -BeTrue
            $r.Arquitetura | Should -Be '64-bit'
        }

        It 'marca disco do sistema e saude' {
            $c = $r.Discos | Where-Object Unidade -eq 'C:'
            $c.Sistema | Should -BeTrue
            $c.Saude | Should -Be 'Healthy'
            ($r.Discos | Where-Object Unidade -eq 'D:').Saude | Should -Be 'Warning'
        }

        It 'decodifica antivirus, monitores e adaptadores' {
            $r.Antivirus[0].Nome | Should -Be 'Windows Defender'
            $r.Antivirus[0].Ativo | Should -BeTrue
            $r.Antivirus[0].Atualizado | Should -BeTrue
            $r.Monitores[0].Fabricante | Should -Be 'Dell'
            $r.Monitores[0].Modelo | Should -Be 'P2422H'
            $r.Monitores[0].Serial | Should -Be 'AB12'
            $r.Adaptadores[0].Gateway | Should -Be '192.0.2.1'
            $r.Adaptadores[0].DHCP | Should -BeTrue
        }

        It 'indica status e protocolo' {
            $r.StatusColeta | Should -Be 'Coletado'
            $r.ProtocoloUsado | Should -Be 'Local'
        }

        It 'traz ativacao e software ordenado' {
            $r.Ativacao | Should -Be 'Ativado'
            $r.Software.Nome | Should -Be @('Alfa Editor', 'Zeta Reader')
        }

        It 'nao abre sessao CIM nem faz ping na maquina local' {
            Should -Invoke New-SessaoCim -ModuleName InventarioTI -Times 0 -Exactly
        }
    }

    Context 'opcoes' {
        It 'pula o software com -SemSoftware' {
            $r = Get-InventarioMaquina -ComputerName $env:COMPUTERNAME -SemSoftware
            $r.Software.Count | Should -Be 0
            $r.Ativacao | Should -BeNullOrEmpty
        }
    }

    Context 'maquina remota' {
        It 'abre e fecha a sessao CIM, repassando a credencial' {
            $cred = [pscredential]::new('EMPRESA\svc', [securestring]::new())

            $r = Get-InventarioMaquina -ComputerName 'PC-FINANCEIRO-01' -Credential $cred -SemSoftware

            $r.Online | Should -BeTrue
            $r.ProtocoloUsado | Should -Be 'WinRM'
            Should -Invoke New-SessaoCim -ModuleName InventarioTI -Times 1 -Exactly -ParameterFilter { $Credential -and $ComputerName -eq 'PC-FINANCEIRO-01' }
            Should -Invoke Remove-SessaoCim -ModuleName InventarioTI -Times 1 -Exactly
        }
    }

    Context 'host offline ou com falha' {
        It 'marca offline sem lancar excecao quando nao responde ao ping' {
            Mock -ModuleName InventarioTI Test-HostAtivoParalelo {
                [pscustomobject]@{ Nome = $ComputerName[0]; Respondeu = $false; Via = $null; WinRM = $false; Rpc = $false }
            }

            $r = Get-InventarioMaquina -ComputerName 'PC-ALMOXARIFADO-01'

            $r.Online | Should -BeFalse
            $r.StatusColeta | Should -Be 'Offline'
            $r.Mensagem | Should -Not -BeNullOrEmpty
            $r.Erro | Should -Match 'ping'
            $r.ComputerName | Should -Be 'PC-ALMOXARIFADO-01'
        }

        It 'captura erro de CIM e devolve o motivo' {
            Mock -ModuleName InventarioTI New-SessaoCim { throw 'Acesso negado' }

            $r = Get-InventarioMaquina -ComputerName 'PC-VENDAS-03'

            $r.Online | Should -BeFalse
            $r.Erro | Should -Be 'Acesso negado'
            $r.StatusColeta | Should -Be 'AcessoNegado'
        }
    }

    Context 'pipeline' {
        It 'processa varias maquinas' {
            Mock -ModuleName InventarioTI Test-HostAtivoParalelo {
                [pscustomobject]@{ Nome = $ComputerName[0]; Respondeu = $false; Via = $null; WinRM = $false; Rpc = $false }
            }
            $r = 'PC-A', 'PC-B', 'PC-C' | Get-InventarioMaquina
            $r.Count | Should -Be 3
            $r.ComputerName | Should -Be @('PC-A', 'PC-B', 'PC-C')
        }
    }
}

Describe 'Get-StatusAtivacao' {
    It 'traduz o LicenseStatus' -TestCases @(
        @{ Codigo = 0; Texto = 'Nao licenciado' }
        @{ Codigo = 1; Texto = 'Ativado' }
        @{ Codigo = 5; Texto = 'Notificacao' }
    ) {
        param($Codigo, $Texto)
        InModuleScope InventarioTI -Parameters @{ Codigo = $Codigo; Texto = $Texto } {
            Mock Get-DadosCim { [pscustomobject]@{ LicenseStatus = $Codigo } }
            Get-StatusAtivacao | Should -Be $Texto
        }
    }

    It 'devolve Indisponivel quando a consulta falha' {
        Mock -ModuleName InventarioTI Get-DadosCim { throw 'falha' }
        InModuleScope InventarioTI {
            Get-StatusAtivacao | Should -Be 'Indisponivel'
        }
    }
}

Describe 'Get-SoftwareInstalado' {
    It 'le as chaves Uninstall, ignora componentes de sistema e duplicatas' {
        Mock -ModuleName InventarioTI Invoke-RegistroCim {
            switch ($Metodo) {
                'EnumKey' {
                    if ($SubChave -like '*WOW6432Node*') { [pscustomobject]@{ sNames = @('app-a', 'sem-nome') } }
                    else { [pscustomobject]@{ sNames = @('app-a', 'componente') } }
                }
                'GetStringValue' {
                    $mapa = @{
                        'app-a|DisplayName' = 'Aplicativo A'; 'app-a|DisplayVersion' = '1.0'; 'app-a|Publisher' = 'Exemplo'
                        'componente|DisplayName' = 'Componente interno'
                    }
                    $chave = ($SubChave -split '\\')[-1]
                    [pscustomobject]@{ sValue = $mapa["$chave|$Valor"] }
                }
                'GetDWORDValue' {
                    $chave = ($SubChave -split '\\')[-1]
                    [pscustomobject]@{ uValue = if ($chave -eq 'componente') { 1 } else { $null } }
                }
            }
        }

        InModuleScope InventarioTI {
            $itens = @(Get-SoftwareInstalado)
            $itens.Count | Should -Be 1
            $itens[0].Nome | Should -Be 'Aplicativo A'
            $itens[0].Versao | Should -Be '1.0'
            $itens[0].Arquitetura | Should -Be 'x64'
        }
    }
}
