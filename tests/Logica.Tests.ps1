BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\InventarioTI\InventarioTI.psd1') -Force
}

Describe 'Get-PercentualLivre' {
    It 'calcula o percentual com uma casa decimal' {
        InModuleScope InventarioTI {
            Get-PercentualLivre -TamanhoBytes 200GB -LivreBytes 50GB | Should -Be 25
            Get-PercentualLivre -TamanhoBytes 300 -LivreBytes 100 | Should -Be 33.3
        }
    }

    It 'devolve 0 quando o tamanho e zero' {
        InModuleScope InventarioTI {
            Get-PercentualLivre -TamanhoBytes 0 -LivreBytes 0 | Should -Be 0
        }
    }
}

Describe 'Format-TamanhoGB' {
    It 'converte bytes para GB com duas casas' {
        InModuleScope InventarioTI {
            Format-TamanhoGB -Bytes 1GB | Should -Be 1
            Format-TamanhoGB -Bytes 1.5GB | Should -Be 1.5
            Format-TamanhoGB -Bytes 1234567890 | Should -Be 1.15
        }
    }
}

Describe 'Test-DiscoBaixo' {
    It 'considera baixo o que esta abaixo do limite' -TestCases @(
        @{ Livre = 14.9; Esperado = $true }
        @{ Livre = 0;    Esperado = $true }
        @{ Livre = 15;   Esperado = $false }
        @{ Livre = 60;   Esperado = $false }
    ) {
        param($Livre, $Esperado)
        InModuleScope InventarioTI -Parameters @{ Livre = $Livre; Esperado = $Esperado } {
            Test-DiscoBaixo -PercentualLivre $Livre | Should -Be $Esperado
        }
    }

    It 'respeita um limite customizado' {
        InModuleScope InventarioTI {
            Test-DiscoBaixo -PercentualLivre 18 -Limite 20 | Should -BeTrue
            Test-DiscoBaixo -PercentualLivre 18 -Limite 10 | Should -BeFalse
        }
    }
}

Describe 'Get-DiscoEmAlerta' {
    It 'devolve apenas os discos abaixo do limite' {
        InModuleScope InventarioTI {
            $discos = @(
                [pscustomobject]@{ Unidade = 'C:'; PercentualLivre = 8.2 }
                [pscustomobject]@{ Unidade = 'D:'; PercentualLivre = 55 }
            )
            $alerta = @(Get-DiscoEmAlerta -Discos $discos)
            $alerta.Count | Should -Be 1
            $alerta[0].Unidade | Should -Be 'C:'
        }
    }

    It 'aceita lista vazia ou nula' {
        InModuleScope InventarioTI {
            @(Get-DiscoEmAlerta -Discos @()).Count | Should -Be 0
            @(Get-DiscoEmAlerta -Discos $null).Count | Should -Be 0
        }
    }
}

Describe 'Get-StatusSuporteSO' {
    It 'classifica <Nome> como <Esperado>' -TestCases @(
        @{ Nome = 'Microsoft Windows XP Professional';          Esperado = 'Fora de suporte' }
        @{ Nome = 'Microsoft Windows 7 Professional';           Esperado = 'Fora de suporte' }
        @{ Nome = 'Microsoft Windows 8 Pro';                    Esperado = 'Fora de suporte' }
        @{ Nome = 'Microsoft Windows 8.1 Pro';                  Esperado = 'Fora de suporte' }
        @{ Nome = 'Microsoft Windows 10 Pro';                   Esperado = 'Fora de suporte' }
        @{ Nome = 'Microsoft Windows 11 Pro';                   Esperado = 'Suportado' }
        @{ Nome = 'Microsoft Windows Server 2008 R2 Standard';  Esperado = 'Fora de suporte' }
        @{ Nome = 'Microsoft Windows Server 2012 R2 Standard';  Esperado = 'Fora de suporte' }
        @{ Nome = 'Microsoft Windows Server 2016 Standard';     Esperado = 'Suportado' }
        @{ Nome = 'Microsoft Windows Server 2022 Standard';     Esperado = 'Suportado' }
        @{ Nome = 'Linux Qualquer';                             Esperado = 'Desconhecido' }
        @{ Nome = '';                                           Esperado = 'Desconhecido' }
    ) {
        param($Nome, $Esperado)
        InModuleScope InventarioTI -Parameters @{ Nome = $Nome; Esperado = $Esperado } {
            Get-StatusSuporteSO -Nome $Nome -DataReferencia ([datetime]'2026-10-16') | Should -Be $Esperado
        }
    }

    It 'leva a data de referencia em conta (Windows 10 antes do fim do suporte)' {
        InModuleScope InventarioTI {
            Get-StatusSuporteSO -Nome 'Microsoft Windows 10 Pro' -DataReferencia ([datetime]'2025-06-01') | Should -Be 'Suportado'
            Get-StatusSuporteSO -Nome 'Microsoft Windows 10 Pro' -DataReferencia ([datetime]'2025-10-15') | Should -Be 'Fora de suporte'
        }
    }

    It 'aceita nome nulo' {
        InModuleScope InventarioTI {
            Get-StatusSuporteSO -Nome $null | Should -Be 'Desconhecido'
        }
    }
}

Describe 'ConvertTo-HtmlSeguro' {
    It 'escapa caracteres especiais' {
        InModuleScope InventarioTI {
            ConvertTo-HtmlSeguro -Texto '<b>"A" & B</b>' | Should -Be '&lt;b&gt;&quot;A&quot; &amp; B&lt;/b&gt;'
        }
    }

    It 'devolve texto vazio para nulo' {
        InModuleScope InventarioTI {
            ConvertTo-HtmlSeguro -Texto $null | Should -Be ''
        }
    }
}

Describe 'Format-DiscoResumo' {
    It 'junta os discos em uma unica linha' {
        InModuleScope InventarioTI {
            $discos = @(
                [pscustomobject]@{ Unidade = 'C:'; TamanhoGB = 100; PercentualLivre = 50; Tipo = 'SSD' }
                [pscustomobject]@{ Unidade = 'D:'; TamanhoGB = 500; PercentualLivre = 10; Tipo = 'HDD' }
            )
            $texto = Format-DiscoResumo -Discos $discos
            $texto | Should -Match '^C: '
            $texto | Should -Match '; D: '
            ($texto -split ';').Count | Should -Be 2
        }
    }
}

Describe 'Get-ResumoInventario' {
    BeforeAll {
        . (Join-Path $PSScriptRoot '..\tools\DadosExemplo.ps1')
    }

    It 'conta totais, offline, discos baixos e SO fora de suporte' {
        $dados = Get-DadosExemplo
        $resumo = InModuleScope InventarioTI -Parameters @{ Dados = $dados } {
            Get-ResumoInventario -Maquinas $Dados -DataReferencia ([datetime]'2026-10-16')
        }

        $resumo.Total | Should -Be 11
        $resumo.Offline | Should -Be 2
        $resumo.Online | Should -Be 9
        # PC-FINANCEIRO-02 (8,0%), PC-COMPRAS-01 (9,2%) e SRV-ARQUIVOS-01 (E: 8,3%)
        $resumo.DiscoBaixo | Should -Be 3
        # Windows 10, Windows 7 e Server 2012 R2
        $resumo.SOForaSuporte | Should -Be 3
    }

    It 'ignora maquinas offline nos alertas' {
        InModuleScope InventarioTI {
            $offline = [pscustomobject]@{ Online = $false; Discos = @(); SistemaOperacional = $null }
            $resumo = Get-ResumoInventario -Maquinas @($offline)
            $resumo.Total | Should -Be 1
            $resumo.Offline | Should -Be 1
            $resumo.DiscoBaixo | Should -Be 0
            $resumo.SOForaSuporte | Should -Be 0
        }
    }

    It 'funciona com lista vazia' {
        InModuleScope InventarioTI {
            $resumo = Get-ResumoInventario -Maquinas @()
            $resumo.Total | Should -Be 0
        }
    }
}
