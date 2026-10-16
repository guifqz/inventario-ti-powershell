BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\InventarioTI\InventarioTI.psd1') -Force
}

Describe 'Resolve-AlvoInventario' {
    It 'le arquivo ignorando vazias, comentarios e espacos' {
        $arq = Join-Path $TestDrive 'pcs.txt'
        Set-Content -Path $arq -Value @('# estacoes', 'PC-A', '', '  PC-B  ', '#PC-C')

        InModuleScope InventarioTI -Parameters @{ Arq = $arq } {
            Resolve-AlvoInventario -Path $Arq | Should -Be @('PC-A', 'PC-B')
        }
    }

    It 'combina fontes e remove duplicados sem diferenciar maiusculas' {
        $arq = Join-Path $TestDrive 'pcs2.txt'
        Set-Content -Path $arq -Value @('pc-a', 'PC-B')

        InModuleScope InventarioTI -Parameters @{ Arq = $arq } {
            $lista = Resolve-AlvoInventario -ComputerName 'PC-A', 'PC-C' -Path $Arq
            $lista.Count | Should -Be 3
        }
    }

    It 'falha com mensagem clara quando o arquivo nao existe' {
        InModuleScope InventarioTI {
            { Resolve-AlvoInventario -Path 'C:\nao\existe.txt' } | Should -Throw '*nao encontrado*'
        }
    }

    It 'usa o Active Directory quando uma OU e informada' {
        InModuleScope InventarioTI {
            Mock Get-NomesDoAD { 'PC-AD-01', 'PC-AD-02' }
            Resolve-AlvoInventario -OrganizationalUnit 'OU=Estacoes,DC=exemplo,DC=local' | Should -Be @('PC-AD-01', 'PC-AD-02')
            Should -Invoke Get-NomesDoAD -Times 1 -ParameterFilter { $OrganizationalUnit -eq 'OU=Estacoes,DC=exemplo,DC=local' }
        }
    }

    It 'explica quando o modulo ActiveDirectory nao existe' {
        InModuleScope InventarioTI {
            Mock Get-Command { $null } -ParameterFilter { $Name -eq 'Get-ADComputer' }
            { Get-NomesDoAD -OrganizationalUnit 'OU=X' } | Should -Throw '*ActiveDirectory*'
        }
    }
}

Describe 'Invoke-InventarioRede' {
    It 'exige ao menos um computador' {
        { Invoke-InventarioRede } | Should -Throw '*Nenhum computador*'
    }

    It 'coleta varias maquinas em paralelo e devolve um objeto por nome, offline incluso' {
        $r = Invoke-InventarioRede -ComputerName 'host-inexistente-01.invalid', 'host-inexistente-02.invalid' -ThrottleLimit 2

        @($r).Count | Should -Be 2
        $r | ForEach-Object {
            $_.PSObject.TypeNames | Should -Contain 'InventarioTI.Maquina'
            $_.Online | Should -BeFalse
            $_.Erro | Should -Not -BeNullOrEmpty
        }
    }

    It 'inventaria a maquina local sem software' -Tag 'Integracao' {
        $r = Invoke-InventarioRede -ComputerName $env:COMPUTERNAME -SemSoftware

        @($r).Count | Should -Be 1
        $r.Online | Should -BeTrue
        $r.SistemaOperacional | Should -Match 'Windows'
        $r.Discos.Count | Should -BeGreaterThan 0
    }
}
