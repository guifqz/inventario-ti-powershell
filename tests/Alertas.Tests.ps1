BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\InventarioTI\InventarioTI.psd1') -Force
    . (Join-Path $PSScriptRoot '..\tools\DadosExemplo.ps1')
    $script:ref = [datetime]'2026-10-16'
}

Describe 'Test-RAMBaixa' {
    It 'considera <Ram> GB com limite 8 como baixa: <Esperado>' -TestCases @(
        @{ Ram = 4;    Esperado = $true }
        @{ Ram = 7.4;  Esperado = $false }
        @{ Ram = 6.4;  Esperado = $true }
        @{ Ram = 8;    Esperado = $false }
        @{ Ram = 16;   Esperado = $false }
        @{ Ram = $null; Esperado = $false }
    ) {
        param($Ram, $Esperado)
        InModuleScope InventarioTI -Parameters @{ Ram = $Ram; Esperado = $Esperado } {
            Test-RAMBaixa -RAMGB $Ram | Should -Be $Esperado
        }
    }
}

Describe 'Test-DiscoSistemaHDD' {
    It 'detecta HDD no disco do sistema' {
        InModuleScope InventarioTI {
            Test-DiscoSistemaHDD -Discos @([pscustomobject]@{ Unidade = 'C:'; Tipo = 'HDD'; Sistema = $true }) | Should -BeTrue
            Test-DiscoSistemaHDD -Discos @(
                [pscustomobject]@{ Unidade = 'C:'; Tipo = 'SSD'; Sistema = $true }
                [pscustomobject]@{ Unidade = 'D:'; Tipo = 'HDD'; Sistema = $false }
            ) | Should -BeFalse
        }
    }

    It 'sem marca de sistema, usa C:' {
        InModuleScope InventarioTI {
            Test-DiscoSistemaHDD -Discos @([pscustomobject]@{ Unidade = 'C:'; Tipo = 'HDD' }) | Should -BeTrue
            Test-DiscoSistemaHDD -Discos @() | Should -BeFalse
        }
    }

    It 'nao alerta tipo desconhecido' {
        InModuleScope InventarioTI {
            Test-DiscoSistemaHDD -Discos @([pscustomobject]@{ Unidade = 'C:'; Tipo = 'Desconhecido'; Sistema = $true }) | Should -BeFalse
        }
    }
}

Describe 'Get-DiscoSaudeRuim' {
    It 'devolve discos com Warning ou Unhealthy e ignora Healthy, Unknown e nulo' {
        InModuleScope InventarioTI {
            $discos = @(
                [pscustomobject]@{ Unidade = 'C:'; Saude = 'Healthy' }
                [pscustomobject]@{ Unidade = 'D:'; Saude = 'Warning' }
                [pscustomobject]@{ Unidade = 'E:'; Saude = 'Unhealthy' }
                [pscustomobject]@{ Unidade = 'F:'; Saude = 'Unknown' }
                [pscustomobject]@{ Unidade = 'G:'; Saude = $null }
            )
            @(Get-DiscoSaudeRuim -Discos $discos).Unidade | Should -Be @('D:', 'E:')
        }
    }
}

Describe 'Get-StatusProtecaoAV' {
    It 'classifica os cenarios' {
        InModuleScope InventarioTI {
            Get-StatusProtecaoAV -Antivirus $null | Should -BeNullOrEmpty
            Get-StatusProtecaoAV -Antivirus @() | Should -Be 'Ausente'
            Get-StatusProtecaoAV -Antivirus @([pscustomobject]@{ Ativo = $false; Atualizado = $true }) | Should -Be 'Desativado'
            Get-StatusProtecaoAV -Antivirus @([pscustomobject]@{ Ativo = $true; Atualizado = $false }) | Should -Be 'Desatualizado'
            Get-StatusProtecaoAV -Antivirus @([pscustomobject]@{ Ativo = $true; Atualizado = $true }) | Should -Be 'OK'
        }
    }

    It 'considera OK quando o Defender esta inativo mas outro produto esta ativo e atualizado' {
        InModuleScope InventarioTI {
            $av = @(
                [pscustomobject]@{ Nome = 'Windows Defender'; Ativo = $false; Atualizado = $true }
                [pscustomobject]@{ Nome = 'Corporativo'; Ativo = $true; Atualizado = $true }
            )
            Get-StatusProtecaoAV -Antivirus $av | Should -Be 'OK'
        }
    }
}

Describe 'Test-NaoAtivado e Test-UptimeAlto' {
    It 'identifica ativacao pendente' -TestCases @(
        @{ Texto = 'Ativado';                      Esperado = $false }
        @{ Texto = 'Nao licenciado';               Esperado = $true }
        @{ Texto = 'Notificacao';                  Esperado = $true }
        @{ Texto = 'Periodo de carencia inicial';  Esperado = $true }
        @{ Texto = 'Indisponivel';                 Esperado = $false }
        @{ Texto = $null;                          Esperado = $false }
    ) {
        param($Texto, $Esperado)
        InModuleScope InventarioTI -Parameters @{ Texto = $Texto; Esperado = $Esperado } {
            Test-NaoAtivado -Ativacao $Texto | Should -Be $Esperado
        }
    }

    It 'uptime acima de 30 dias' {
        InModuleScope InventarioTI {
            Test-UptimeAlto -UptimeDias 31 | Should -BeTrue
            Test-UptimeAlto -UptimeDias 30 | Should -BeFalse
            Test-UptimeAlto -UptimeDias $null | Should -BeFalse
        }
    }
}

Describe 'Get-AlertasMaquina' {
    BeforeAll {
        $script:dados = Get-DadosExemplo
        function script:Codigos([string]$Nome) {
            $m = $script:dados | Where-Object ComputerName -eq $Nome
            InModuleScope InventarioTI -Parameters @{ M = $m } {
                @(Get-AlertasMaquina -Maquina $M -DataReferencia ([datetime]'2026-10-16') | ForEach-Object { $_.Codigo })
            }
        }
    }

    It 'maquina saudavel nao tem alertas' {
        script:Codigos 'PC-FINANCEIRO-01' | Should -BeNullOrEmpty
        script:Codigos 'SRV-APP-01' | Should -BeNullOrEmpty
    }

    It 'dispara cada regra na maquina certa' -TestCases @(
        @{ Nome = 'PC-FINANCEIRO-02'; Codigo = 'DISCO_BAIXO' }
        @{ Nome = 'PC-RH-01'; Codigo = 'SO_FORA_SUPORTE' }
        @{ Nome = 'PC-RH-02'; Codigo = 'RAM_BAIXA' }
        @{ Nome = 'PC-RH-01'; Codigo = 'DISCO_SISTEMA_HDD' }
        @{ Nome = 'NB-DIRETORIA-02'; Codigo = 'DISCO_SAUDE' }
        @{ Nome = 'PC-PRODUCAO-03'; Codigo = 'AV_AUSENTE' }
        @{ Nome = 'PC-RECEPCAO-02'; Codigo = 'AV_DESATIVADO' }
        @{ Nome = 'PC-COMPRAS-02'; Codigo = 'AV_DESATUALIZADO' }
        @{ Nome = 'PC-PRODUCAO-03'; Codigo = 'NAO_ATIVADO' }
        @{ Nome = 'PC-TI-02'; Codigo = 'UPTIME_ALTO' }
        @{ Nome = 'PC-ALMOXARIFADO-02'; Codigo = 'AD_INATIVO' }
        @{ Nome = 'PC-VENDAS-03'; Codigo = 'NUNCA_INVENTARIADO' }
    ) {
        param($Nome, $Codigo)
        script:Codigos $Nome | Should -Contain $Codigo
    }

    It 'servidor nao recebe alerta de antivirus (nao coletado)' {
        script:Codigos 'SRV-ARQUIVOS-01' | Should -Not -Contain 'AV_AUSENTE'
        script:Codigos 'SRV-ARQUIVOS-01' | Should -Contain 'DISCO_BAIXO'
    }

    It 'maquina nao coletada so tem alertas do AD' {
        script:Codigos 'PC-VENDAS-04' | Should -Be @('NUNCA_INVENTARIADO')
        script:Codigos 'PC-ANTIGO-02' | Should -Contain 'AD_INATIVO'
    }

    It 'maquina fora do AD nao gera alertas do AD' {
        script:Codigos 'PC-VISITANTE-01' | Should -Not -Contain 'AD_INATIVO'
    }

    It 'sempre traz texto e correcao sugerida' {
        $m = $dados | Where-Object ComputerName -eq 'PC-RECEPCAO-01'
        $alertas = InModuleScope InventarioTI -Parameters @{ M = $m } { @(Get-AlertasMaquina -Maquina $M -DataReferencia ([datetime]'2026-10-16')) }
        $alertas.Count | Should -BeGreaterThan 3
        foreach ($a in $alertas) {
            $a.Texto | Should -Not -BeNullOrEmpty
            $a.Correcao | Should -Not -BeNullOrEmpty
            $a.Gravidade | Should -BeIn @('Critico', 'Aviso', 'Info')
        }
    }
}
