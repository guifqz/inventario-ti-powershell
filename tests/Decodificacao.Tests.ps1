BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\InventarioTI\InventarioTI.psd1') -Force
}

Describe 'ConvertFrom-ProductState' {
    It 'decodifica <Estado>: ativo=<Ativo> atualizado=<Atualizado>' -TestCases @(
        @{ Estado = 266240; Ativo = $true;  Atualizado = $true }
        @{ Estado = 262144; Ativo = $false; Atualizado = $true }
        @{ Estado = 397568; Ativo = $true;  Atualizado = $true }
        @{ Estado = 393472; Ativo = $false; Atualizado = $true }
        @{ Estado = 397584; Ativo = $true;  Atualizado = $false }
        @{ Estado = 266256; Ativo = $true;  Atualizado = $false }
    ) {
        param($Estado, $Ativo, $Atualizado)
        InModuleScope InventarioTI -Parameters @{ Estado = $Estado; Ativo = $Ativo; Atualizado = $Atualizado } {
            $r = ConvertFrom-ProductState -Estado $Estado
            $r.Ativo | Should -Be $Ativo
            $r.Atualizado | Should -Be $Atualizado
        }
    }
}

Describe 'ConvertFrom-ArrayUInt16' {
    It 'decodifica o texto ate o primeiro zero' {
        InModuleScope InventarioTI {
            ConvertFrom-ArrayUInt16 -Valor ([uint16[]](68, 69, 76, 0, 0, 0)) | Should -Be 'DEL'
            ConvertFrom-ArrayUInt16 -Valor ([uint16[]](80, 50, 52, 50, 50, 72, 0)) | Should -Be 'P2422H'
        }
    }

    It 'devolve nulo para vazio ou nulo' {
        InModuleScope InventarioTI {
            ConvertFrom-ArrayUInt16 -Valor $null | Should -BeNullOrEmpty
            ConvertFrom-ArrayUInt16 -Valor ([uint16[]](0, 0, 0)) | Should -BeNullOrEmpty
        }
    }
}

Describe 'Get-NomeFabricanteMonitor' {
    It 'traduz codigos PnP conhecidos e preserva os desconhecidos' {
        InModuleScope InventarioTI {
            Get-NomeFabricanteMonitor -Codigo 'DEL' | Should -Be 'Dell'
            Get-NomeFabricanteMonitor -Codigo 'gsm' | Should -Be 'LG'
            Get-NomeFabricanteMonitor -Codigo 'ZZZ' | Should -Be 'ZZZ'
            Get-NomeFabricanteMonitor -Codigo $null | Should -BeNullOrEmpty
        }
    }
}

Describe 'ConvertTo-TipoMemoria, ConvertTo-TipoDisco e ConvertTo-SaudeDisco' {
    It 'traduz os codigos' {
        InModuleScope InventarioTI {
            ConvertTo-TipoMemoria -Codigo 26 | Should -Be 'DDR4'
            ConvertTo-TipoMemoria -Codigo 34 | Should -Be 'DDR5'
            ConvertTo-TipoMemoria -Codigo 0 | Should -BeNullOrEmpty
            ConvertTo-TipoDisco -MediaType 4 | Should -Be 'SSD'
            ConvertTo-TipoDisco -MediaType 3 | Should -Be 'HDD'
            ConvertTo-TipoDisco -MediaType 0 | Should -Be 'Desconhecido'
            ConvertTo-SaudeDisco -HealthStatus 0 | Should -Be 'Healthy'
            ConvertTo-SaudeDisco -HealthStatus 1 | Should -Be 'Warning'
            ConvertTo-SaudeDisco -HealthStatus 2 | Should -Be 'Unhealthy'
            ConvertTo-SaudeDisco -HealthStatus 5 | Should -Be 'Unknown'
            ConvertTo-SaudeDisco -HealthStatus $null | Should -BeNullOrEmpty
        }
    }
}

Describe 'Get-DiasLigado' {
    It 'calcula dias desde o boot' {
        InModuleScope InventarioTI {
            Get-DiasLigado -UltimoBoot ([datetime]'2026-09-01 12:00') -DataReferencia ([datetime]'2026-10-16 00:00') | Should -Be 44.5
            Get-DiasLigado -UltimoBoot $null | Should -BeNullOrEmpty
        }
    }
}

Describe 'Get-VersaoOffice' {
    It 'escolhe o produto e ignora componentes' {
        InModuleScope InventarioTI {
            $sw = @(
                [pscustomobject]@{ Nome = 'Microsoft Office Shared MUI (Portuguese) 2016' }
                [pscustomobject]@{ Nome = 'Microsoft Office Professional Plus 2016' }
                [pscustomobject]@{ Nome = 'Microsoft Visio Standard 2016' }
                [pscustomobject]@{ Nome = 'Microsoft OneDrive' }
            )
            Get-VersaoOffice -Software $sw | Should -Be 'Microsoft Office Professional Plus 2016'
        }
    }

    It 'reconhece Microsoft 365 e devolve nulo sem Office' {
        InModuleScope InventarioTI {
            Get-VersaoOffice -Software @([pscustomobject]@{ Nome = 'Microsoft 365 Apps for enterprise - pt-br' }) | Should -Be 'Microsoft 365 Apps for enterprise - pt-br'
            Get-VersaoOffice -Software @([pscustomobject]@{ Nome = 'LibreOffice 7' }) | Should -BeNullOrEmpty
            Get-VersaoOffice -Software @() | Should -BeNullOrEmpty
        }
    }
}

Describe 'Get-FerramentasAcessoRemoto' {
    It 'detecta ferramentas conhecidas' {
        InModuleScope InventarioTI {
            $sw = @(
                [pscustomobject]@{ Nome = 'AnyDesk' }
                [pscustomobject]@{ Nome = 'TeamViewer 15' }
                [pscustomobject]@{ Nome = 'TightVNC' }
                [pscustomobject]@{ Nome = '7-Zip' }
            )
            Get-FerramentasAcessoRemoto -Software $sw | Should -Be @('AnyDesk', 'TeamViewer', 'VNC')
            @(Get-FerramentasAcessoRemoto -Software @()).Count | Should -Be 0
        }
    }
}
