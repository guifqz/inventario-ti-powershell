BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\InventarioTI\InventarioTI.psd1') -Force
    . (Join-Path $PSScriptRoot '..\tools\DadosExemplo.ps1')
}

Describe 'ConvertTo-JsonParaHtml' {
    It 'nunca emite fechamento de script, comentario HTML nem separadores de linha Unicode' {
        InModuleScope InventarioTI {
            $texto = "a</script><!--b" + [char]0x2028 + "c" + [char]0x2029 + "d & e > f"
            $json = ConvertTo-JsonParaHtml -Objeto ([ordered]@{ t = $texto })

            $json | Should -Not -Match '<'
            $json | Should -Not -Match '>'
            $json.Contains([string][char]0x2028) | Should -BeFalse
            $json.Contains([string][char]0x2029) | Should -BeFalse
            ($json | ConvertFrom-Json).t | Should -Be $texto
        }
    }

    It 'preserva listas de um unico item e listas vazias' {
        InModuleScope InventarioTI {
            ConvertTo-JsonParaHtml -Objeto ([object[]]@('x')) | Should -Be '["x"]'
            ConvertTo-JsonParaHtml -Objeto ([object[]]@()) | Should -Be '[]'
        }
    }
}

Describe 'ConvertTo-ModeloRelatorio' {
    It 'traz alertas calculados, discos e software compactos' {
        $m = Get-DadosExemplo | Where-Object ComputerName -eq 'PC-RECEPCAO-01'
        $modelo = InModuleScope InventarioTI -Parameters @{ M = $m } {
            ConvertTo-ModeloRelatorio -Maquina $M -DataReferencia ([datetime]'2026-10-16')
        }
        $modelo.nome | Should -Be 'PC-RECEPCAO-01'
        $modelo.status | Should -Be 'Coletado'
        $modelo.alertas.c | Should -Contain 'AV_AUSENTE'
        $modelo.discos[0].sistema | Should -BeTrue
        $modelo.discos[0].tipo | Should -Be 'HDD'
        $modelo.software[0].n | Should -Not -BeNullOrEmpty
        $modelo.av.Count | Should -Be 0
        $modelo.noAD | Should -BeTrue
    }

    It 'maquina nao coletada nao traz hardware' {
        $m = Get-DadosExemplo | Where-Object ComputerName -eq 'PC-VENDAS-03'
        $modelo = InModuleScope InventarioTI -Parameters @{ M = $m } {
            ConvertTo-ModeloRelatorio -Maquina $M -DataReferencia ([datetime]'2026-10-16')
        }
        $modelo.status | Should -Be 'AcessoNegado'
        $modelo.ramGB | Should -BeNullOrEmpty
        @($modelo.discos).Count | Should -Be 0
        $modelo.av | Should -BeNullOrEmpty
    }
}

Describe 'ConvertTo-RegistroPlano (CSV)' {
    It 'resume antivirus, monitores e alertas em texto' {
        $m = Get-DadosExemplo | Where-Object ComputerName -eq 'PC-RECEPCAO-02'
        $linha = InModuleScope InventarioTI -Parameters @{ M = $m } {
            ConvertTo-RegistroPlano -Maquina $M -DataReferencia ([datetime]'2026-10-16')
        }
        $linha.Antivirus | Should -Match 'desativado'
        $linha.Alertas | Should -Match 'Antivírus desativado'
        $linha.OU | Should -Be 'contoso.local/Recepcao'
    }
}
