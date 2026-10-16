BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\InventarioTI\InventarioTI.psd1') -Force
}

Describe 'Split-DistinguishedName' {
    It 'respeita virgula escapada' {
        InModuleScope InventarioTI {
            $partes = Split-DistinguishedName -DistinguishedName 'CN=PC-01,OU=Vendas\, Sul,DC=contoso,DC=local'
            $partes | Should -Be @('CN=PC-01', 'OU=Vendas, Sul', 'DC=contoso', 'DC=local')
        }
    }
}

Describe 'ConvertTo-OuDeDn' {
    It 'monta o caminho do dominio ate a OU, sem o proprio objeto' {
        InModuleScope InventarioTI {
            ConvertTo-OuDeDn -DistinguishedName 'CN=PC-FINANCEIRO-01,OU=Estacoes,OU=Financeiro,DC=contoso,DC=local' |
                Should -Be 'contoso.local/Financeiro/Estacoes'
        }
    }

    It 'trata o container padrao Computers' {
        InModuleScope InventarioTI {
            ConvertTo-OuDeDn -DistinguishedName 'CN=PC-01,CN=Computers,DC=contoso,DC=local' | Should -Be 'contoso.local/Computers'
        }
    }

    It 'trata virgula escapada e valores vazios' {
        InModuleScope InventarioTI {
            ConvertTo-OuDeDn -DistinguishedName 'CN=PC-01,OU=Vendas\, Sul,DC=contoso,DC=local' | Should -Be 'contoso.local/Vendas, Sul'
            ConvertTo-OuDeDn -DistinguishedName '' | Should -Be ''
            ConvertTo-OuDeDn -DistinguishedName $null | Should -Be ''
        }
    }
}

Describe 'Test-ContaDesativada' {
    It 'le o bit 2 do userAccountControl: <Uac>' -TestCases @(
        @{ Uac = 4096;   Esperado = $false }
        @{ Uac = 4098;   Esperado = $true }
        @{ Uac = 546;    Esperado = $true }
        @{ Uac = 8192;   Esperado = $false }
        @{ Uac = $null;  Esperado = $false }
    ) {
        param($Uac, $Esperado)
        InModuleScope InventarioTI -Parameters @{ Uac = $Uac; Esperado = $Esperado } {
            Test-ContaDesativada -UserAccountControl $Uac | Should -Be $Esperado
        }
    }
}

Describe 'ConvertFrom-FileTimeAd' {
    It 'converte FILETIME para data local' {
        InModuleScope InventarioTI {
            $esperado = [datetime]::new(2026, 10, 1, 12, 0, 0, [System.DateTimeKind]::Utc)
            $r = ConvertFrom-FileTimeAd -Valor $esperado.ToFileTimeUtc()
            $r.ToUniversalTime() | Should -Be $esperado
        }
    }

    It 'devolve nulo para nunca, zero e nulo' {
        InModuleScope InventarioTI {
            ConvertFrom-FileTimeAd -Valor 0 | Should -BeNullOrEmpty
            ConvertFrom-FileTimeAd -Valor ([long]::MaxValue) | Should -BeNullOrEmpty
            ConvertFrom-FileTimeAd -Valor $null | Should -BeNullOrEmpty
        }
    }
}

Describe 'Test-InativoAD' {
    BeforeAll { $script:ref = [datetime]'2026-10-16' }

    It 'marca inativo acima de 90 dias e ativo no limite' {
        InModuleScope InventarioTI -Parameters @{ Ref = $ref } {
            Test-InativoAD -UltimoLogon $Ref.AddDays(-91) -CriadoEm $null -DataReferencia $Ref | Should -BeTrue
            Test-InativoAD -UltimoLogon $Ref.AddDays(-90) -CriadoEm $null -DataReferencia $Ref | Should -BeFalse
            Test-InativoAD -UltimoLogon $Ref.AddDays(-5) -CriadoEm $null -DataReferencia $Ref | Should -BeFalse
        }
    }

    It 'sem logon usa a data de criacao' {
        InModuleScope InventarioTI -Parameters @{ Ref = $ref } {
            Test-InativoAD -UltimoLogon $null -CriadoEm $Ref.AddDays(-400) -DataReferencia $Ref | Should -BeTrue
            Test-InativoAD -UltimoLogon $null -CriadoEm $Ref.AddDays(-10) -DataReferencia $Ref | Should -BeFalse
            Test-InativoAD -UltimoLogon $null -CriadoEm $null -DataReferencia $Ref | Should -BeFalse
        }
    }

    It 'aceita limite customizado' {
        InModuleScope InventarioTI -Parameters @{ Ref = $ref } {
            Test-InativoAD -UltimoLogon $Ref.AddDays(-40) -CriadoEm $null -DataReferencia $Ref -Dias 30 | Should -BeTrue
        }
    }
}

Describe 'ConvertTo-ComputadorAD' {
    It 'converte as propriedades LDAP no objeto do inventario' {
        InModuleScope InventarioTI {
            $logon = [datetime]::new(2026, 10, 14, 10, 0, 0, [System.DateTimeKind]::Utc)
            $c = ConvertTo-ComputadorAD -Propriedades @{
                name                   = 'PC-FINANCEIRO-01'
                dnshostname            = 'pc-financeiro-01.contoso.local'
                operatingsystem        = 'Windows 11 Pro'
                operatingsystemversion = '10.0 (22631)'
                lastlogontimestamp     = $logon.ToFileTimeUtc()
                whencreated            = [datetime]::new(2023, 3, 10, 12, 0, 0, [System.DateTimeKind]::Utc)
                description            = ' Ana Souza '
                distinguishedname      = 'CN=PC-FINANCEIRO-01,OU=Financeiro,DC=contoso,DC=local'
                useraccountcontrol     = 4096
            }
            $c.Nome | Should -Be 'PC-FINANCEIRO-01'
            $c.DNSHostName | Should -Be 'pc-financeiro-01.contoso.local'
            $c.SistemaOperacionalAD | Should -Be 'Windows 11 Pro'
            $c.VersaoSOAD | Should -Be '10.0 (22631)'
            $c.UltimoLogonAD.ToUniversalTime() | Should -Be $logon
            $c.Descricao | Should -Be 'Ana Souza'
            $c.OU | Should -Be 'contoso.local/Financeiro'
            $c.Habilitado | Should -BeTrue
            $c.CriadoEm | Should -BeOfType [datetime]
        }
    }

    It 'marca conta desativada e tolera campos ausentes' {
        InModuleScope InventarioTI {
            $c = ConvertTo-ComputadorAD -Propriedades @{ name = 'PC-X'; useraccountcontrol = 4098 }
            $c.Habilitado | Should -BeFalse
            $c.UltimoLogonAD | Should -BeNullOrEmpty
            $c.CriadoEm | Should -BeNullOrEmpty
            $c.OU | Should -Be ''
        }
    }
}

Describe 'Get-ComputadoresAD' {
    It 'usa ADSI e ordena por nome' {
        InModuleScope InventarioTI {
            Mock Invoke-BuscaLdap {
                @{ name = 'PC-B'; useraccountcontrol = 4096 }
                @{ name = 'PC-A'; useraccountcontrol = 4096 }
            }
            $r = @(Get-ComputadoresAD -SearchBase 'OU=Estacoes,DC=contoso,DC=local')
            $r.Nome | Should -Be @('PC-A', 'PC-B')
            Should -Invoke Invoke-BuscaLdap -Times 1 -ParameterFilter { $SearchBase -eq 'OU=Estacoes,DC=contoso,DC=local' }
        }
    }

    It 'explica quando nao ha dominio e nao existe o modulo ActiveDirectory' {
        InModuleScope InventarioTI {
            Mock Invoke-BuscaLdap { throw 'The specified domain either does not exist or could not be contacted.' }
            Mock Get-Command { $null } -ParameterFilter { $Name -eq 'Get-ADComputer' }
            { Get-ComputadoresAD } | Should -Throw '*Active Directory*'
            { Get-ComputadoresAD } | Should -Throw '*-ComputerName*'
        }
    }

    It 'cai para Get-ADComputer quando o ADSI falha e o modulo existe' {
        InModuleScope InventarioTI {
            Mock Invoke-BuscaLdap { throw 'falha ldap' }
            Set-Item -Path 'Function:global:Get-ADComputer' -Value {
                [pscustomobject]@{
                    Name = 'PC-RSAT'; DNSHostName = 'pc-rsat.contoso.local'; OperatingSystem = 'Windows 10 Pro'
                    OperatingSystemVersion = '10.0 (19045)'; LastLogonTimestamp = ([datetime]'2026-10-01').ToFileTimeUtc()
                    whenCreated = [datetime]'2024-01-01'; Description = $null
                    DistinguishedName = 'CN=PC-RSAT,OU=TI,DC=contoso,DC=local'; userAccountControl = 4096
                }
            }
            try {
                $r = @(Get-ComputadoresAD)
                $r.Count | Should -Be 1
                $r[0].Nome | Should -Be 'PC-RSAT'
                $r[0].OU | Should -Be 'contoso.local/TI'
            }
            finally {
                Remove-Item -Path 'Function:global:Get-ADComputer' -ErrorAction SilentlyContinue
            }
        }
    }
}
