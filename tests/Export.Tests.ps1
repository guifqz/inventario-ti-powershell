BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\InventarioTI\InventarioTI.psd1') -Force
    . (Join-Path $PSScriptRoot '..\tools\DadosExemplo.ps1')
    $script:dados = Get-DadosExemplo
    $script:ref = [datetime]'2026-10-16'
}

Describe 'Export-InventarioRelatorio' {
    BeforeEach {
        $script:saida = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
    }

    It 'gera CSV, JSON e HTML por padrao' {
        $arquivos = $dados | Export-InventarioRelatorio -Path $saida -NomeBase teste -DataReferencia $ref

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
            $null = Export-InventarioRelatorio -InputObject $dados -Path $pasta -Formato CSV -NomeBase d -DataReferencia $ref
            $script:linhas = Import-Csv -Path (Join-Path $pasta 'd.csv') -Delimiter ';' -Encoding UTF8
        }

        It 'tem uma linha por maquina' {
            $linhas.Count | Should -Be 40
        }

        It 'marca alerta de disco e suporte do SO' {
            ($linhas | Where-Object Computador -eq 'PC-FINANCEIRO-02').AlertaDisco | Should -Be 'True'
            ($linhas | Where-Object Computador -eq 'PC-FINANCEIRO-01').AlertaDisco | Should -Be 'False'
            ($linhas | Where-Object Computador -eq 'PC-RECEPCAO-01').SuporteSO | Should -Be 'Fora de suporte'
        }

        It 'resume discos e conta software' {
            $l = $linhas | Where-Object Computador -eq 'PC-COMPRAS-01'
            $l.Discos | Should -Match 'C: .*; D: '
            $l.SoftwareQtd | Should -Be 37
        }

        It 'mantem maquinas offline com o motivo' {
            $l = $linhas | Where-Object Computador -eq 'PC-ALMOXARIFADO-01'
            $l.Online | Should -Be 'False'
            $l.Erro | Should -Match 'ping'
            $l.StatusColeta | Should -Be 'Offline'
            $l.Mensagem | Should -Not -BeNullOrEmpty
        }
    }

    Context 'JSON' {
        BeforeAll {
            $script:pasta = Join-Path $TestDrive 'json'
            $null = Export-InventarioRelatorio -InputObject $dados -Path $pasta -Formato JSON -NomeBase d -DataReferencia $ref
            $script:json = Get-Content -Path (Join-Path $pasta 'd.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        }

        It 'e um array valido com todas as maquinas' {
            @($json).Count | Should -Be 40
        }

        It 'preserva discos e software aninhados' {
            $m = $json | Where-Object ComputerName -eq 'PC-COMPRAS-01'
            @($m.Discos).Count | Should -Be 2
            @($m.Software).Count | Should -Be 37
        }

        It 'usa datas ISO 8601' {
            # No PowerShell 7 o ConvertFrom-Json ja converte para DateTime, entao confere o texto bruto
            $bruto = Get-Content -Path (Join-Path $pasta 'd.json') -Raw -Encoding UTF8
            $bruto | Should -Match '"UltimoBoot":\s*"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}"'
        }
    }

    Context 'HTML' {
        BeforeAll {
            $script:pasta = Join-Path $TestDrive 'html'
            $null = Export-InventarioRelatorio -InputObject $dados -Path $pasta -Formato HTML -NomeBase d -DataReferencia $ref
            $script:html = Get-Content -Path (Join-Path $pasta 'd.html') -Raw -Encoding UTF8
            $script:dadosJson = [regex]::Match($html, '<script id="dados-json" type="application/json">(.*?)</script>').Groups[1].Value | ConvertFrom-Json
        }

        It 'e autocontido (sem recursos externos)' {
            $html | Should -Not -Match '(src|href)\s*=\s*"?https?:'
            $html | Should -Not -Match '<link '
            $html | Should -Not -Match '@import'
            $html | Should -Not -Match 'url\(\s*["'']?https?:'
            $html | Should -Not -Match '<script[^>]*\ssrc='
        }

        It 'embute os dados como JSON valido, um registro por maquina' {
            @($dadosJson).Count | Should -Be 40
            ($dadosJson | Where-Object nome -eq 'PC-FINANCEIRO-02').alertas.c | Should -Contain 'DISCO_BAIXO'
        }

        It 'nao deixa marcadores do modelo sem substituir' {
            $html | Should -Not -Match '\{\{[A-Z_]+\}\}'
        }

        It 'traz titulo, tema e filtros do relatorio' {
            $html | Should -Match '<title>Inventário de TI</title>'
            $html | Should -Match 'data-theme="dark"'
            $html | Should -Not -Match 'prefers-color-scheme'
            $html | Should -Match '@media print'
            $html | Should -Match 'Exportar CSV'
        }

        It 'respeita o limite de disco informado' {
            $outra = Join-Path $TestDrive 'html30'
            $null = Export-InventarioRelatorio -InputObject $dados -Path $outra -Formato HTML -NomeBase d -LimiteDisco 30 -DataReferencia $ref
            $h = Get-Content -Path (Join-Path $outra 'd.html') -Raw -Encoding UTF8
            $j = [regex]::Match($h, '<script id="meta-json" type="application/json">(.*?)</script>').Groups[1].Value | ConvertFrom-Json
            $j.limiteDisco | Should -Be 30
        }

        It 'escapa HTML e fechamento de script vindos dos dados' {
            $malicioso = Get-MaquinaExemplo -ComputerName 'PC-X' -Usuario '</script><script>alert(1)</script>' -Descricao "linha$([char]0x2028)separada" -Discos (Get-DiscoExemplo -TamanhoGB 100 -LivreGB 50)
            $p = Join-Path $TestDrive 'xss'
            $null = Export-InventarioRelatorio -InputObject $malicioso -Path $p -Formato HTML -NomeBase d -Titulo '<b>x</b>' -DataReferencia $ref
            $h = Get-Content -Path (Join-Path $p 'd.html') -Raw -Encoding UTF8
            $h | Should -Not -Match 'alert\(1\)</script>'
            $h | Should -Not -Match '<script>alert'
            $h.Contains([string][char]0x2028) | Should -BeFalse
            $h | Should -Match '<title>&lt;b&gt;x&lt;/b&gt;</title>'
            $j = [regex]::Match($h, '<script id="dados-json" type="application/json">(.*?)</script>').Groups[1].Value | ConvertFrom-Json
            @($j)[0].usuario | Should -Be '</script><script>alert(1)</script>'
        }

        It 'gera relatorio valido sem nenhuma maquina' {
            $p = Join-Path $TestDrive 'vazio'
            $null = Export-InventarioRelatorio -InputObject @() -Path $p -Formato HTML -NomeBase d -DataReferencia $ref
            $h = Get-Content -Path (Join-Path $p 'd.html') -Raw -Encoding UTF8
            $h | Should -Match '<script id="dados-json" type="application/json">\[\]</script>'
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
