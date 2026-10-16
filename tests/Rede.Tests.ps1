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
            Resolve-AlvoInventario -OrganizationalUnit 'OU=Estacoes,DC=contoso,DC=local' | Should -Be @('PC-AD-01', 'PC-AD-02')
            Should -Invoke Get-NomesDoAD -Times 1 -ParameterFilter { $OrganizationalUnit -eq 'OU=Estacoes,DC=contoso,DC=local' }
        }
    }

    It 'Get-NomesDoAD prefere o nome DNS e cai para o nome curto' {
        InModuleScope InventarioTI {
            Mock Get-ComputadoresAD {
                [pscustomobject]@{ Nome = 'PC-A'; DNSHostName = 'pc-a.contoso.local' }
                [pscustomobject]@{ Nome = 'PC-B'; DNSHostName = $null }
            }
            Get-NomesDoAD -OrganizationalUnit 'OU=X' | Should -Be @('pc-a.contoso.local', 'PC-B')
        }
    }

    It 'explica quando nao ha como consultar o AD' {
        InModuleScope InventarioTI {
            Mock Invoke-BuscaLdap { throw 'dominio inacessivel' }
            Mock Get-Command { $null } -ParameterFilter { $Name -eq 'Get-ADComputer' }
            { Get-NomesDoAD -OrganizationalUnit 'OU=X' } | Should -Throw '*Active Directory*'
        }
    }
}

Describe 'Test-AlvoLocal' {
    It 'reconhece a maquina local e rejeita as outras' {
        InModuleScope InventarioTI {
            Test-AlvoLocal -Nome 'localhost' | Should -BeTrue
            Test-AlvoLocal -Nome '.' | Should -BeTrue
            Test-AlvoLocal -Nome $env:COMPUTERNAME | Should -BeTrue
            Test-AlvoLocal -Nome 'OUTRO-PC-01' | Should -BeFalse
        }
    }
}

Describe 'Test-HostAtivoParalelo' {
    It 'responde para o loopback e marca host inexistente como offline' {
        InModuleScope InventarioTI {
            $r = @(Test-HostAtivoParalelo -ComputerName '127.0.0.1', 'host-fantasma.invalid' -TimeoutMs 1000)
            $r.Count | Should -Be 2
            ($r | Where-Object Nome -eq '127.0.0.1').Respondeu | Should -BeTrue
            ($r | Where-Object Nome -eq '127.0.0.1').Via | Should -Be 'Ping'
            $off = $r | Where-Object Nome -eq 'host-fantasma.invalid'
            $off.Respondeu | Should -BeFalse
            $off.Via | Should -BeNullOrEmpty
            $off.WinRM | Should -BeFalse
        }
    }

    It 'sonda varios hosts em tempo proximo ao timeout, nao a soma' {
        InModuleScope InventarioTI {
            $nomes = 1..8 | ForEach-Object { "host-fantasma-$_.invalid" }
            $tempo = Measure-Command { $null = @(Test-HostAtivoParalelo -ComputerName $nomes -TimeoutMs 1000) }
            $tempo.TotalSeconds | Should -BeLessThan 8
        }
    }
}

Describe 'Get-ClasseErro' {
    It 'classifica "<Mensagem>" como <Classe>' -TestCases @(
        @{ Mensagem = 'Access is denied.';                                        Classe = 'AcessoNegado' }
        @{ Mensagem = 'Acesso negado';                                            Classe = 'AcessoNegado' }
        @{ Mensagem = 'Acesso é negado. 0x80070005';                              Classe = 'AcessoNegado' }
        @{ Mensagem = 'The RPC server is unavailable. 0x800706BA';                Classe = 'Rpc' }
        @{ Mensagem = 'O servidor RPC não está disponível';                       Classe = 'Rpc' }
        @{ Mensagem = 'WinRM cannot process the request.';                        Classe = 'WinRM' }
        @{ Mensagem = 'Falha na conexão do cliente WS-Management com o destino'; Classe = 'WinRM' }
        @{ Mensagem = 'Qualquer outra coisa';                                     Classe = 'Outro' }
        @{ Mensagem = '';                                                         Classe = $null }
    ) {
        param($Mensagem, $Classe)
        InModuleScope InventarioTI -Parameters @{ Mensagem = $Mensagem; Classe = $Classe } {
            Get-ClasseErro -Mensagem $Mensagem | Should -Be $Classe
        }
    }
}

Describe 'Resolve-StatusColeta' {
    It 'acesso negado em qualquer protocolo vira AcessoNegado' {
        InModuleScope InventarioTI {
            $r = Resolve-StatusColeta -ErroWsman 'Acesso negado'
            $r.StatusColeta | Should -Be 'AcessoNegado'
            $r.Mensagem | Should -Match 'Credential'
        }
    }

    It 'WinRM e DCOM indisponiveis (RPC) viram SemWinRMeDcom com dica de GPO e firewall' {
        InModuleScope InventarioTI {
            $r = Resolve-StatusColeta -ErroWsman 'WinRM cannot process the request' -ErroDcom 'The RPC server is unavailable.'
            $r.StatusColeta | Should -Be 'SemWinRMeDcom'
            $r.Mensagem | Should -Match 'WinRM via GPO'
            $r.Mensagem | Should -Match 'WMI-In'
            $r.Erro | Should -Match 'WinRM:.*DCOM:'
        }
    }

    It 'outros erros viram Erro e mantem o detalhe' {
        InModuleScope InventarioTI {
            $r = Resolve-StatusColeta -ErroGenerico 'Tempo limite excedido'
            $r.StatusColeta | Should -Be 'Erro'
            $r.Mensagem | Should -Match 'Tempo limite excedido'
        }
    }

    It 'erro WinRM com protocolo explicito sugere Auto' {
        InModuleScope InventarioTI {
            (Resolve-StatusColeta -ErroWsman 'WinRM cannot process the request').Mensagem | Should -Match 'Auto'
        }
    }

    It 'mensagem unica quando os dois protocolos falham igual' {
        InModuleScope InventarioTI {
            (Resolve-StatusColeta -ErroWsman 'Acesso negado' -ErroDcom 'Acesso negado').Erro | Should -Be 'Acesso negado'
        }
    }
}

Describe 'Open-SessaoCim (protocolo Auto)' {
    BeforeEach {
        Mock -ModuleName InventarioTI Get-DadosCim { [pscustomobject]@{ Name = 'PC' } }
        Mock -ModuleName InventarioTI Remove-SessaoCim { }
    }

    It 'usa WinRM quando funciona e nao tenta DCOM' {
        Mock -ModuleName InventarioTI New-SessaoCim { 'sessao-wsman' }
        $r = InModuleScope InventarioTI { Open-SessaoCim -ComputerName 'PC-01' }
        $r.ProtocoloUsado | Should -Be 'WinRM'
        $r.Sessao | Should -Be 'sessao-wsman'
        Should -Invoke New-SessaoCim -ModuleName InventarioTI -Times 1 -Exactly
    }

    It 'cai para DCOM quando o WSMan falha por indisponibilidade' {
        Mock -ModuleName InventarioTI New-SessaoCim {
            if ($Protocolo -eq 'Wsman') { throw 'WinRM cannot process the request. The WinRM client cannot connect to the destination.' }
            'sessao-dcom'
        }
        $r = InModuleScope InventarioTI { Open-SessaoCim -ComputerName 'PC-01' }
        $r.ProtocoloUsado | Should -Be 'DCOM'
        $r.Sessao | Should -Be 'sessao-dcom'
        $r.ErroWsman | Should -Match 'WinRM'
        Should -Invoke New-SessaoCim -ModuleName InventarioTI -Times 1 -Exactly -ParameterFilter { $Protocolo -eq 'Wsman' }
        Should -Invoke New-SessaoCim -ModuleName InventarioTI -Times 1 -Exactly -ParameterFilter { $Protocolo -eq 'Dcom' }
    }

    It 'cai para DCOM quando a sessao WSMan abre mas a primeira consulta falha' {
        Mock -ModuleName InventarioTI New-SessaoCim { "sessao-$Protocolo" }
        Mock -ModuleName InventarioTI Get-DadosCim {
            if ($Sessao -eq 'sessao-Wsman') { throw 'WS-Management service cannot process the request' }
            [pscustomobject]@{ Name = 'PC' }
        }
        $r = InModuleScope InventarioTI { Open-SessaoCim -ComputerName 'PC-01' }
        $r.ProtocoloUsado | Should -Be 'DCOM'
        Should -Invoke Remove-SessaoCim -ModuleName InventarioTI -Times 1 -Exactly
    }

    It 'nao tenta DCOM quando o WSMan negou acesso' {
        Mock -ModuleName InventarioTI New-SessaoCim { throw 'Access is denied.' }
        $r = InModuleScope InventarioTI { Open-SessaoCim -ComputerName 'PC-01' }
        $r.Sessao | Should -BeNullOrEmpty
        $r.ErroDcom | Should -BeNullOrEmpty
        Should -Invoke New-SessaoCim -ModuleName InventarioTI -Times 1 -Exactly
    }

    It 'pula o WinRM quando a porta 5985 esta fechada' {
        Mock -ModuleName InventarioTI New-SessaoCim { 'sessao-dcom' }
        $r = InModuleScope InventarioTI { Open-SessaoCim -ComputerName 'PC-01' -WinRMAberto $false }
        $r.ProtocoloUsado | Should -Be 'DCOM'
        Should -Invoke New-SessaoCim -ModuleName InventarioTI -Times 1 -Exactly -ParameterFilter { $Protocolo -eq 'Dcom' }
    }

    It 'sem WinRM nem RPC devolve os dois erros sem abrir sessao' {
        Mock -ModuleName InventarioTI New-SessaoCim { 'x' }
        $r = InModuleScope InventarioTI { Open-SessaoCim -ComputerName 'PC-01' -WinRMAberto $false -RpcAberto $false }
        $r.Sessao | Should -BeNullOrEmpty
        $r.ErroWsman | Should -Not -BeNullOrEmpty
        $r.ErroDcom | Should -Not -BeNullOrEmpty
        Should -Invoke New-SessaoCim -ModuleName InventarioTI -Times 0 -Exactly
    }

    It 'Wsman explicito nao cai para DCOM' {
        Mock -ModuleName InventarioTI New-SessaoCim { throw 'WinRM cannot process the request' }
        $r = InModuleScope InventarioTI { Open-SessaoCim -ComputerName 'PC-01' -Protocolo Wsman }
        $r.Sessao | Should -BeNullOrEmpty
        Should -Invoke New-SessaoCim -ModuleName InventarioTI -Times 1 -Exactly
    }
}

Describe 'Get-InventarioMaquina: falhas de protocolo' {
    BeforeEach {
        Mock -ModuleName InventarioTI Remove-SessaoCim { }
        Mock -ModuleName InventarioTI Test-HostAtivoParalelo {
            [pscustomobject]@{ Nome = $ComputerName[0]; Respondeu = $true; Via = 'TCP'; WinRM = $true; Rpc = $true }
        }
    }

    It 'sem WinRM e sem RPC marca SemWinRMeDcom com mensagem de correcao' {
        Mock -ModuleName InventarioTI New-SessaoCim {
            if ($Protocolo -eq 'Wsman') { throw 'WinRM cannot process the request.' }
            throw 'The RPC server is unavailable. (0x800706BA)'
        }
        $r = Get-InventarioMaquina -ComputerName 'PC-VENDAS-04' -SemSoftware
        $r.Online | Should -BeFalse
        $r.StatusColeta | Should -Be 'SemWinRMeDcom'
        $r.Mensagem | Should -Match 'GPO'
    }

    It 'WinRM ausente com DCOM funcionando coleta e registra o protocolo' {
        Mock -ModuleName InventarioTI New-SessaoCim {
            if ($Protocolo -eq 'Wsman') { throw 'WinRM cannot process the request.' }
            'sessao-dcom'
        }
        Mock -ModuleName InventarioTI Get-DadosCim {
            switch ($ClassName) {
                'Win32_ComputerSystem' { [pscustomobject]@{ Name = 'PC-VENDAS-04'; Manufacturer = 'Dell'; Model = 'X'; TotalPhysicalMemory = 8GB } }
                'Win32_OperatingSystem' { [pscustomobject]@{ Caption = 'Microsoft Windows 10 Pro'; Version = '10.0.19045'; BuildNumber = '19045'; LastBootUpTime = (Get-Date).AddDays(-2) } }
                default { throw 'nao simulada' }
            }
        }
        $r = Get-InventarioMaquina -ComputerName 'PC-VENDAS-04' -SemSoftware
        $r.Online | Should -BeTrue
        $r.ProtocoloUsado | Should -Be 'DCOM'
        $r.StatusColeta | Should -Be 'Coletado'
        $r.Antivirus | Should -BeNullOrEmpty
        $r.Monitores | Should -BeNullOrEmpty
        $r.Discos.Count | Should -Be 0
    }
}

Describe 'Invoke-InventarioRede' {
    It 'exige ao menos um computador' {
        { Invoke-InventarioRede } | Should -Throw '*Nenhum computador*'
    }

    It 'coleta varias maquinas e devolve um objeto por nome, offline incluso, sem esperar timeout de CIM' {
        $inicio = Get-Date
        $r = Invoke-InventarioRede -ComputerName 'host-inexistente-01.invalid', 'host-inexistente-02.invalid' -ThrottleLimit 2
        $tempo = (Get-Date) - $inicio

        @($r).Count | Should -Be 2
        $r | ForEach-Object {
            $_.PSObject.TypeNames | Should -Contain 'InventarioTI.Maquina'
            $_.Online | Should -BeFalse
            $_.StatusColeta | Should -Be 'Offline'
            $_.Erro | Should -Not -BeNullOrEmpty
            $_.Mensagem | Should -Not -BeNullOrEmpty
        }
        $tempo.TotalSeconds | Should -BeLessThan 15
    }

    It '-DoAD inclui todos os computadores do AD, mesmo os que nunca foram coletados' {
        Mock -ModuleName InventarioTI Get-ComputadoresAD {
            [pscustomobject]@{ Nome = 'PC-FANTASMA-01'; DNSHostName = 'pc-fantasma-01.invalid'; SistemaOperacionalAD = 'Windows 10 Pro'; VersaoSOAD = '10.0'; UltimoLogonAD = (Get-Date).AddDays(-200); CriadoEm = (Get-Date).AddDays(-900); Descricao = 'Teste'; OU = 'contoso.local/TI'; Habilitado = $true }
            [pscustomobject]@{ Nome = 'PC-FANTASMA-02'; DNSHostName = 'pc-fantasma-02.invalid'; SistemaOperacionalAD = 'Windows 11 Pro'; VersaoSOAD = '10.0'; UltimoLogonAD = (Get-Date).AddDays(-2); CriadoEm = (Get-Date).AddDays(-30); Descricao = $null; OU = 'contoso.local/TI'; Habilitado = $true }
        }

        $r = @(Invoke-InventarioRede -DoAD)

        $r.Count | Should -Be 2
        $r.NoAD | Should -Be @($true, $true)
        $a = $r | Where-Object ComputerName -eq 'PC-FANTASMA-01'
        $a.StatusColeta | Should -Be 'Offline'
        $a.PossivelmenteInativo | Should -BeTrue
        $a.NuncaInventariado | Should -BeTrue
        $a.OU | Should -Be 'contoso.local/TI'
        ($r | Where-Object ComputerName -eq 'PC-FANTASMA-02').PossivelmenteInativo | Should -BeFalse
    }

    It '-OrganizationalUnit (alias SearchBase) repassa a base ao AD' {
        Mock -ModuleName InventarioTI Get-ComputadoresAD {
            [pscustomobject]@{ Nome = 'PC-FANTASMA-03'; DNSHostName = 'pc-fantasma-03.invalid'; SistemaOperacionalAD = $null; VersaoSOAD = $null; UltimoLogonAD = $null; CriadoEm = $null; Descricao = $null; OU = ''; Habilitado = $true }
        }
        $null = Invoke-InventarioRede -SearchBase 'OU=Estacoes,DC=contoso,DC=local'
        Should -Invoke Get-ComputadoresAD -ModuleName InventarioTI -Times 1 -Exactly -ParameterFilter { $SearchBase -eq 'OU=Estacoes,DC=contoso,DC=local' }
    }

    It 'mescla coletas locais da pasta, mesmo sem alvos remotos' {
        $pasta = Join-Path $TestDrive 'ativos'
        $null = New-Item -Path $pasta -ItemType Directory
        $json = [ordered]@{ ComputerName = 'PC-LOCAL-01'; Online = $true; ColetadoEm = (Get-Date).AddDays(-1).ToString('s'); SistemaOperacional = 'Microsoft Windows 11 Pro'; RAMGB = 16 } | ConvertTo-Json
        Set-Content -Path (Join-Path $pasta 'PC-LOCAL-01.json') -Value $json -Encoding UTF8

        $r = @(Invoke-InventarioRede -PastaColetaLocal $pasta)

        $r.Count | Should -Be 1
        $r[0].Fonte | Should -Be 'Local'
        $r[0].StatusColeta | Should -Be 'Coletado'
        $r[0].IdadeDadosDias | Should -BeGreaterThan 0.9
    }

    It 'inventaria a maquina local sem software' -Tag 'Integracao' {
        $r = Invoke-InventarioRede -ComputerName $env:COMPUTERNAME -SemSoftware

        @($r).Count | Should -Be 1
        $r.Online | Should -BeTrue
        $r.StatusColeta | Should -Be 'Coletado'
        $r.SistemaOperacional | Should -Match 'Windows'
        $r.Discos.Count | Should -BeGreaterThan 0
    }
}
