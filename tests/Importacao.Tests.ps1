BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\InventarioTI\InventarioTI.psd1') -Force
    . (Join-Path $PSScriptRoot '..\tools\DadosExemplo.ps1')
}

Describe 'Import-InventarioPasta' {
    BeforeAll {
        $script:pasta = Join-Path $TestDrive 'ativos'
        $null = New-Item -Path $pasta -ItemType Directory
        $dados = Get-DadosExemplo | Where-Object ComputerName -in 'PC-RECEPCAO-01', 'SRV-ARQUIVOS-01', 'PC-FINANCEIRO-01'
        foreach ($m in $dados) {
            $null = Export-InventarioRelatorio -InputObject $m -Path $pasta -Formato JSON -NomeBase $m.ComputerName
        }
        $script:lidos = @(Import-InventarioPasta -Path $pasta)
    }

    It 'le um registro por arquivo, no formato de Get-InventarioMaquina' {
        $lidos.Count | Should -Be 3
        $lidos | ForEach-Object { $_.PSObject.TypeNames | Should -Contain 'InventarioTI.Maquina' }
    }

    It 'marca Fonte Local e StatusColeta Coletado' {
        $lidos | ForEach-Object {
            $_.Fonte | Should -Be 'Local'
            $_.ProtocoloUsado | Should -Be 'Local'
            $_.StatusColeta | Should -Be 'Coletado'
            $_.Online | Should -BeTrue
        }
    }

    It 'converte datas para DateTime (5.1 e 7)' {
        $m = $lidos | Where-Object ComputerName -eq 'PC-RECEPCAO-01'
        $m.ColetadoEm | Should -BeOfType [datetime]
        $m.UltimoBoot | Should -BeOfType [datetime]
        $m.BiosData | Should -BeOfType [datetime]
        $m.UltimoLogonAD | Should -BeOfType [datetime]
    }

    It 'preserva listas, antivirus vazio e antivirus nulo (servidor)' {
        $esta = $lidos | Where-Object ComputerName -eq 'PC-RECEPCAO-01'
        @($esta.Discos).Count | Should -Be 1
        $esta.Discos[0].Sistema | Should -BeTrue
        $esta.Discos[0].Tipo | Should -Be 'HDD'
        $null -ne $esta.Antivirus | Should -BeTrue
        @($esta.Antivirus).Count | Should -Be 0
        @($esta.Software).Count | Should -BeGreaterThan 10
        $esta.Adaptadores[0].Gateway | Should -Be '192.0.2.1'

        $srv = $lidos | Where-Object ComputerName -eq 'SRV-ARQUIVOS-01'
        $srv.Antivirus | Should -BeNullOrEmpty
        $null -eq $srv.Antivirus | Should -BeTrue
    }

    It 'o ciclo exportar -> importar -> alertas da o mesmo resultado' {
        $original = Get-DadosExemplo | Where-Object ComputerName -eq 'PC-RECEPCAO-01'
        $lido = $lidos | Where-Object ComputerName -eq 'PC-RECEPCAO-01'
        $codigos = {
            param($m)
            InModuleScope InventarioTI -Parameters @{ M = $m } {
                @(Get-AlertasMaquina -Maquina $M -DataReferencia ([datetime]'2026-10-16') | ForEach-Object { $_.Codigo })
            }
        }
        (& $codigos $lido) | Should -Be (& $codigos $original)
    }

    It 'aceita arquivo com lista de registros' {
        $p = Join-Path $TestDrive 'lista'
        $null = Export-InventarioRelatorio -InputObject (Get-DadosExemplo | Select-Object -First 5) -Path $p -Formato JSON -NomeBase todos
        @(Import-InventarioPasta -Path $p).Count | Should -Be 5
    }

    It 'ignora arquivo invalido com aviso e le os demais' {
        $p = Join-Path $TestDrive 'misto'
        $null = New-Item -Path $p -ItemType Directory
        Set-Content -Path (Join-Path $p 'quebrado.json') -Value '{ nao e json'
        Set-Content -Path (Join-Path $p 'semnome.json') -Value '{ "Online": true }'
        Set-Content -Path (Join-Path $p 'PC-OK.json') -Value '{ "ComputerName": "PC-OK", "Online": true, "RAMGB": 8 }'

        $r = @(Import-InventarioPasta -Path $p -WarningVariable avisos -WarningAction SilentlyContinue)

        $r.Count | Should -Be 1
        $r[0].ComputerName | Should -Be 'PC-OK'
        $r[0].ColetadoEm | Should -BeOfType [datetime]
        @($avisos).Count | Should -Be 2
    }

    It 'falha com mensagem clara quando a pasta nao existe' {
        { Import-InventarioPasta -Path (Join-Path $TestDrive 'nao-existe') } | Should -Throw '*nao encontrada*'
    }
}

Describe 'Coletar-Local.ps1' -Tag 'Integracao' {
    It 'grava <HOSTNAME>.json que o Import-InventarioPasta le de volta' {
        $pasta = Join-Path $TestDrive 'share'
        $null = New-Item -Path $pasta -ItemType Directory

        & (Join-Path $PSScriptRoot '..\tools\Coletar-Local.ps1') -PastaDestino $pasta -SemSoftware

        Test-Path (Join-Path $pasta "$($env:COMPUTERNAME).json") | Should -BeTrue
        Test-Path (Join-Path $pasta "$($env:COMPUTERNAME).json.tmp") | Should -BeFalse
        $r = @(Import-InventarioPasta -Path $pasta)
        $r.Count | Should -Be 1
        $r[0].ComputerName | Should -Be $env:COMPUTERNAME
        $r[0].Fonte | Should -Be 'Local'
    }
}
