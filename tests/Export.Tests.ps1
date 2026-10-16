BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\InventarioTI\InventarioTI.psd1') -Force
    . (Join-Path $PSScriptRoot '..\tools\DadosExemplo.ps1')
    $script:dados = Get-DadosExemplo
}

Describe 'Export-InventarioRelatorio' {
    BeforeEach {
        $script:saida = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
    }

    It 'gera CSV, JSON e HTML por padrao' {
        $arquivos = $dados | Export-InventarioRelatorio -Path $saida -NomeBase teste

        $arquivos.Name | Should -Be @('teste.csv', 'teste.json', 'teste.html')
        $arquivos | ForEach-Object { $_.Length | Should -BeGreaterThan 0 }
    }

    It 'cria a pasta de destino quando nao existe' {
        $null = Export-InventarioRelatorio -InputObject $dados -Path (Join-Path $saida 'a\b') -Formato JSON
        Test-Path (Join-Path $saida 'a\b') | Should -BeTrue
    }

    Context 'CSV' {
        BeforeAll {
            $script:pasta = Join-Path $TestDrive 'csv'
            $null = Export-InventarioRelatorio -InputObject $dados -Path $pasta -Formato CSV -NomeBase d
            $script:linhas = Import-Csv -Path (Join-Path $pasta 'd.csv') -Delimiter ';' -Encoding UTF8
        }

        It 'tem uma linha por maquina' {
            $linhas.Count | Should -Be 11
        }

        It 'marca alerta de disco e suporte do SO' {
            ($linhas | Where-Object Computador -eq 'PC-FINANCEIRO-02').AlertaDisco | Should -Be 'True'
            ($linhas | Where-Object Computador -eq 'PC-FINANCEIRO-01').AlertaDisco | Should -Be 'False'
            ($linhas | Where-Object Computador -eq 'PC-RECEPCAO-01').SuporteSO | Should -Be 'Fora de suporte'
        }

        It 'resume discos e conta software' {
            $l = $linhas | Where-Object Computador -eq 'PC-COMPRAS-01'
            $l.Discos | Should -Match 'C: .*; D: '
            $l.SoftwareQtd | Should -Be 36
        }

        It 'mantem maquinas offline com o motivo' {
            $l = $linhas | Where-Object Computador -eq 'PC-ALMOXARIFADO-01'
            $l.Online | Should -Be 'False'
            $l.Erro | Should -Match 'ping'
        }
    }

    Context 'JSON' {
        BeforeAll {
            $script:pasta = Join-Path $TestDrive 'json'
            $null = Export-InventarioRelatorio -InputObject $dados -Path $pasta -Formato JSON -NomeBase d
            $script:json = Get-Content -Path (Join-Path $pasta 'd.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        }

        It 'e um array valido com todas as maquinas' {
            @($json).Count | Should -Be 11
        }

        It 'preserva discos e software aninhados' {
            $m = $json | Where-Object ComputerName -eq 'PC-COMPRAS-01'
            @($m.Discos).Count | Should -Be 2
            @($m.Software).Count | Should -Be 36
        }

        It 'usa datas ISO 8601' {
            # No PowerShell 7 o ConvertFrom-Json ja converte para DateTime, entao confere o texto bruto
            $bruto = Get-Content -Path (Join-Path $pasta 'd.json') -Raw -Encoding UTF8
            $bruto | Should -Match '"UltimoBoot":\s*"2026-10-12T07:48:00"'
        }
    }

    Context 'HTML' {
        BeforeAll {
            $script:pasta = Join-Path $TestDrive 'html'
            $null = Export-InventarioRelatorio -InputObject $dados -Path $pasta -Formato HTML -NomeBase d
            $script:html = Get-Content -Path (Join-Path $pasta 'd.html') -Raw -Encoding UTF8
        }

        It 'e autocontido (sem recursos externos nem scripts)' {
            $html | Should -Not -Match '<script'
            $html | Should -Not -Match '(src|href)\s*=\s*"https?:'
            $html | Should -Not -Match '<link '
        }

        It 'mostra os cartoes-resumo corretos' {
            $html | Should -Match '<div class="n">11</div><div class="l">Máquinas'
            $html | Should -Match '<div class="n">2</div><div class="l">Offline'
            $html | Should -Match '<div class="n">3</div><div class="l">Disco &lt; 15% livre'
            $html | Should -Match '<div class="n">3</div><div class="l">SO fora de suporte'
        }

        It 'lista as maquinas e destaca disco baixo' {
            $html | Should -Match 'PC-FINANCEIRO-02'
            $html | Should -Match 'class="disk low"'
            $html | Should -Match 'Windows 7 Professional'
        }

        It 'respeita o limite de disco informado' {
            $outra = Join-Path $TestDrive 'html20'
            $null = Export-InventarioRelatorio -InputObject $dados -Path $outra -Formato HTML -NomeBase d -LimiteDisco 30
            $h = Get-Content -Path (Join-Path $outra 'd.html') -Raw -Encoding UTF8
            $h | Should -Match 'Disco &lt; 30% livre'
        }

        It 'escapa HTML vindo dos dados' {
            $malicioso = Get-MaquinaExemplo -ComputerName 'PC-X' -Usuario '<script>alert(1)</script>' -Discos (Get-DiscoExemplo -TamanhoGB 100 -LivreGB 50)
            $p = Join-Path $TestDrive 'xss'
            $null = Export-InventarioRelatorio -InputObject $malicioso -Path $p -Formato HTML -NomeBase d
            $h = Get-Content -Path (Join-Path $p 'd.html') -Raw -Encoding UTF8
            $h | Should -Not -Match '<script>alert'
            $h | Should -Match '&lt;script&gt;alert\(1\)'
        }

        It 'gera relatorio valido sem nenhuma maquina' {
            $p = Join-Path $TestDrive 'vazio'
            $null = Export-InventarioRelatorio -InputObject @() -Path $p -Formato HTML -NomeBase d
            Get-Content -Path (Join-Path $p 'd.html') -Raw -Encoding UTF8 | Should -Match '<div class="n">0</div>'
        }
    }

    Context 'Excel opcional' {
        It 'avisa e segue com os demais formatos quando ImportExcel nao esta instalado' {
            Mock -ModuleName InventarioTI Get-Module { $null } -ParameterFilter { $Name -eq 'ImportExcel' }

            $arquivos = Export-InventarioRelatorio -InputObject $dados -Path $saida -Formato Excel, JSON -NomeBase d -WarningVariable aviso -WarningAction SilentlyContinue

            $aviso | Should -Not -BeNullOrEmpty
            $aviso[0].Message | Should -Match 'ImportExcel'
            $arquivos.Name | Should -Be @('d.json')
        }
    }

    Context 'WhatIf' {
        It 'nao grava nada' {
            Export-InventarioRelatorio -InputObject $dados -Path $saida -WhatIf *> $null
            Test-Path $saida | Should -BeFalse
        }
    }
}
