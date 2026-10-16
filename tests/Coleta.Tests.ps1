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
                'Win32_BIOS' { [pscustomobject]@{ SerialNumber = 'ABC1234' } }
                'Win32_OperatingSystem' {
                    [pscustomobject]@{
                        Caption = 'Microsoft Windows 11 Pro '; Version = '10.0.22631'; BuildNumber = '22631'
                        InstallDate = [datetime]'2023-03-14'; LastBootUpTime = [datetime]'2026-10-12 07:48'
                    }
                }
                'Win32_Processor' {
                    [pscustomobject]@{ Name = 'Intel(R) Core(TM) i5-10500 '; NumberOfCores = 6 }
                }
                'Win32_LogicalDisk' {
                    [pscustomobject]@{ DeviceID = 'C:'; VolumeName = 'Sistema'; Size = 500GB; FreeSpace = 50GB }
                    [pscustomobject]@{ DeviceID = 'D:'; VolumeName = 'Dados'; Size = 1000GB; FreeSpace = 700GB }
                }
                'MSFT_PhysicalDisk' {
                    [pscustomobject]@{ DeviceId = '0'; MediaType = 4 }
                    [pscustomobject]@{ DeviceId = '1'; MediaType = 3 }
                }
                'MSFT_Partition' {
                    [pscustomobject]@{ DriveLetter = [char]'C'; DiskNumber = 0 }
                    [pscustomobject]@{ DriveLetter = [char]'D'; DiskNumber = 1 }
                }
                'Win32_NetworkAdapterConfiguration' {
                    [pscustomobject]@{ IPAddress = @('fe80::1', '192.0.2.11'); MACAddress = '00:50:56:AA:00:11' }
                }
                'SoftwareLicensingProduct' { [pscustomobject]@{ LicenseStatus = 1 } }
                default { throw "Classe nao simulada: $ClassName" }
            }
        }

        Mock -ModuleName InventarioTI Get-SoftwareInstalado {
            [pscustomobject]@{ Nome = 'Zeta Reader'; Versao = '2.0'; Fabricante = 'Exemplo'; Arquitetura = 'x64' }
            [pscustomobject]@{ Nome = 'Alfa Editor'; Versao = '1.5'; Fabricante = 'Exemplo'; Arquitetura = 'x86' }
        }
        Mock -ModuleName InventarioTI New-SessaoCim { 'sessao-simulada' }
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
            Mock -ModuleName InventarioTI Test-Connection { $true }
            $cred = [pscredential]::new('EMPRESA\svc', [securestring]::new())

            $r = Get-InventarioMaquina -ComputerName 'PC-FINANCEIRO-01' -Credential $cred -SemSoftware

            $r.Online | Should -BeTrue
            Should -Invoke New-SessaoCim -ModuleName InventarioTI -Times 1 -Exactly -ParameterFilter { $Credential -and $ComputerName -eq 'PC-FINANCEIRO-01' }
            Should -Invoke Remove-SessaoCim -ModuleName InventarioTI -Times 1 -Exactly
        }
    }

    Context 'host offline ou com falha' {
        It 'marca offline sem lancar excecao quando nao responde ao ping' {
            Mock -ModuleName InventarioTI Test-Connection { $false }

            $r = Get-InventarioMaquina -ComputerName 'PC-ALMOXARIFADO-01'

            $r.Online | Should -BeFalse
            $r.Erro | Should -Match 'ping'
            $r.ComputerName | Should -Be 'PC-ALMOXARIFADO-01'
        }

        It 'captura erro de CIM e devolve o motivo' {
            Mock -ModuleName InventarioTI Test-Connection { $true }
            Mock -ModuleName InventarioTI New-SessaoCim { throw 'Acesso negado' }

            $r = Get-InventarioMaquina -ComputerName 'PC-VENDAS-03'

            $r.Online | Should -BeFalse
            $r.Erro | Should -Be 'Acesso negado'
        }
    }

    Context 'pipeline' {
        It 'processa varias maquinas' {
            Mock -ModuleName InventarioTI Test-Connection { $false }
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
