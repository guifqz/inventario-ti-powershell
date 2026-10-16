BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\InventarioTI\InventarioTI.psd1') -Force
}

Describe 'Get-ChaveMaquina' {
    It 'normaliza nome curto, FQDN e maiusculas; preserva IP' {
        InModuleScope InventarioTI {
            Get-ChaveMaquina -Nome 'pc-01.contoso.local' | Should -Be 'PC-01'
            Get-ChaveMaquina -Nome ' PC-01 ' | Should -Be 'PC-01'
            Get-ChaveMaquina -Nome '192.0.2.10' | Should -Be '192.0.2.10'
            Get-ChaveMaquina -Nome '' | Should -Be ''
        }
    }
}

Describe 'Merge-InventarioColeta' {
    BeforeAll {
        $script:ref = [datetime]'2026-10-16 12:00'
        $script:novo = { param($Nome, $Fonte, $Dias, $Online = $true, $Status = 'Coletado')
            InModuleScope InventarioTI -Parameters @{ Nome = $Nome; Fonte = $Fonte; Dias = $Dias; Online = $Online; Status = $Status; Ref = [datetime]'2026-10-16 12:00' } {
                $r = Initialize-RegistroMaquina -ComputerName $Nome -StatusColeta $Status
                $r.Online = $Online
                $r.Fonte = $Fonte
                $r.ColetadoEm = $Ref.AddDays(-$Dias)
                if ($Online) { $r.SistemaOperacional = "SO-$Fonte"; $r.ProtocoloUsado = if ($Fonte -eq 'Local') { 'Local' } else { 'WinRM' } }
                $r
            }
        }
        $script:mesclar = { param($Remoto, $Local, $AD)
            InModuleScope InventarioTI -Parameters @{ R = $Remoto; L = $Local; A = $AD } {
                @(Merge-InventarioColeta -Remoto $R -Local $L -AD $A -DataReferencia ([datetime]'2026-10-16 12:00'))
            }
        }
    }

    It 'vence a coleta mais recente (local mais nova que a remota)' {
        $r = @(& $mesclar @(& $novo 'PC-01' 'Remoto' 5) @(& $novo 'PC-01' 'Local' 1) @())
        $r.Count | Should -Be 1
        $r[0].Fonte | Should -Be 'Local'
        $r[0].SistemaOperacional | Should -Be 'SO-Local'
        $r[0].IdadeDadosDias | Should -Be 1
        $r[0].ProtocoloUsado | Should -Be 'Local'
    }

    It 'vence a remota quando e mais nova' {
        $r = @(& $mesclar @(& $novo 'PC-01' 'Remoto' 0.1) @(& $novo 'PC-01' 'Local' 3) @())
        $r[0].Fonte | Should -Be 'Remoto'
        $r[0].SistemaOperacional | Should -Be 'SO-Remoto'
        $r[0].IdadeDadosDias | Should -Be 0.1
    }

    It 'falha remota nao apaga dados locais: fica o local e a mensagem cita a falha' {
        $falha = & $novo 'PC-01' 'Remoto' 0 $false 'Offline'
        $r = @(& $mesclar @($falha) @(& $novo 'PC-01' 'Local' 4) @())
        $r[0].Fonte | Should -Be 'Local'
        $r[0].StatusColeta | Should -Be 'Coletado'
        $r[0].Online | Should -BeTrue
        $r[0].Mensagem | Should -Match 'Offline'
    }

    It 'sem dados em lugar nenhum, mantem o registro de falha remota' {
        $r = @(& $mesclar @(& $novo 'PC-02' 'Remoto' 0 $false 'AcessoNegado') @() @())
        $r[0].Online | Should -BeFalse
        $r[0].StatusColeta | Should -Be 'AcessoNegado'
    }

    It 'casa nome curto com FQDN e nao altera os objetos de entrada' {
        $remoto = & $novo 'pc-01.contoso.local' 'Remoto' 1
        $r = @(& $mesclar @($remoto) @(& $novo 'PC-01' 'Local' 9) @())
        $r.Count | Should -Be 1
        $remoto.IdadeDadosDias | Should -BeNullOrEmpty
    }

    It 'inclui computadores so do AD como NaoInventariado' {
        $ad = [pscustomobject]@{ Nome = 'PC-AD-ONLY'; DNSHostName = 'pc-ad-only.contoso.local'; SistemaOperacionalAD = 'Windows 7 Professional'; VersaoSOAD = '6.1'; UltimoLogonAD = [datetime]'2025-01-10'; CriadoEm = [datetime]'2020-01-01'; Descricao = 'antigo'; OU = 'contoso.local/Velhos'; Habilitado = $true }
        $r = @(& $mesclar @() @() @($ad))
        $r.Count | Should -Be 1
        $r[0].ComputerName | Should -Be 'PC-AD-ONLY'
        $r[0].StatusColeta | Should -Be 'NaoInventariado'
        $r[0].Online | Should -BeFalse
        $r[0].NoAD | Should -BeTrue
        $r[0].NuncaInventariado | Should -BeTrue
        $r[0].PossivelmenteInativo | Should -BeTrue
        $r[0].OU | Should -Be 'contoso.local/Velhos'
        $r[0].DescricaoAD | Should -Be 'antigo'
    }

    It 'anexa o AD a maquina coletada e nao a marca como nunca inventariada' {
        $ad = [pscustomobject]@{ Nome = 'PC-01'; DNSHostName = 'pc-01.contoso.local'; SistemaOperacionalAD = 'Windows 11 Pro'; VersaoSOAD = '10.0'; UltimoLogonAD = [datetime]'2026-10-15'; CriadoEm = [datetime]'2024-01-01'; Descricao = 'Ana'; OU = 'contoso.local/RH'; Habilitado = $true }
        $r = @(& $mesclar @(& $novo 'PC-01' 'Remoto' 0) @() @($ad))
        $r[0].NoAD | Should -BeTrue
        $r[0].NuncaInventariado | Should -BeFalse
        $r[0].PossivelmenteInativo | Should -BeFalse
        $r[0].DNSHostName | Should -Be 'pc-01.contoso.local'
    }

    It 'maquina fora do AD fica com NoAD falso' {
        $r = @(& $mesclar @(& $novo 'PC-FORA' 'Remoto' 0) @() @())
        $r[0].NoAD | Should -BeFalse
        $r[0].NuncaInventariado | Should -BeFalse
    }
}
