function Import-InventarioPasta {
    <#
    .SYNOPSIS
        Le os JSON gravados pelo coletor local e devolve objetos no mesmo formato de Get-InventarioMaquina.

    .DESCRIPTION
        Cada arquivo .json da pasta pode ter um objeto (tools/Coletar-Local.ps1) ou uma lista
        (saida JSON de Export-InventarioRelatorio). Os registros voltam com Fonte = 'Local',
        datas como DateTime e ProtocoloUsado = 'Local'. Arquivos invalidos geram aviso e sao
        ignorados, sem interromper a leitura dos demais.

    .PARAMETER Path
        Pasta com os arquivos .json (local ou compartilhamento de rede).

    .EXAMPLE
        Import-InventarioPasta -Path \\srv01\Ativos | Where-Object IdadeDadosDias -gt 7

    .OUTPUTS
        InventarioTI.Maquina
    #>
    [CmdletBinding()]
    [OutputType('InventarioTI.Maquina')]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        throw "Pasta de coleta local nao encontrada: $Path"
    }

    foreach ($arquivo in Get-ChildItem -LiteralPath $Path -Filter '*.json' -File) {
        try {
            $bruto = Get-Content -LiteralPath $arquivo.FullName -Raw -Encoding UTF8
            $dados = ConvertFrom-Json -InputObject $bruto

            foreach ($item in @($dados)) {
                $registro = ConvertFrom-RegistroJson -Objeto $item -DataArquivo $arquivo.LastWriteTime
                $registro.ProtocoloUsado = 'Local'
                if ($registro.Online) {
                    $registro.StatusColeta = 'Coletado'
                    $registro.Mensagem = Get-MensagemStatus -StatusColeta 'Coletado'
                }
                $registro
            }
        }
        catch {
            Write-Warning "Arquivo ignorado ($($arquivo.Name)): $($_.Exception.Message)"
        }
    }
}
