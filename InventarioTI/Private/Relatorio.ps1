function Format-DataHora {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowNull()][object]$Data
    )

    if ($null -eq $Data) { return '' }
    ([datetime]$Data).ToString('yyyy-MM-dd HH:mm')
}

function ConvertTo-RegistroPlano {
    # Uma linha por maquina, para CSV/Excel: colecoes viram texto.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)][object]$Maquina,
        [double]$LimiteDisco = $script:LimiteDiscoPadrao,
        [datetime]$DataReferencia = (Get-Date)
    )

    process {
        [pscustomobject][ordered]@{
            Computador      = $Maquina.ComputerName
            Online          = $Maquina.Online
            Erro            = $Maquina.Erro
            Usuario         = $Maquina.Usuario
            Fabricante      = $Maquina.Fabricante
            Modelo          = $Maquina.Modelo
            Serial          = $Maquina.Serial
            CPU             = $Maquina.CPU
            RAMGB           = if ($null -ne $Maquina.RAMGB) { ([double]$Maquina.RAMGB).ToString('N1', [cultureinfo]'pt-BR') } else { '' }
            Discos         = Format-DiscoResumo -Discos $Maquina.Discos
            AlertaDisco     = @(Get-DiscoEmAlerta -Discos $Maquina.Discos -Limite $LimiteDisco).Count -gt 0
            SistemaOperacional = $Maquina.SistemaOperacional
            VersaoSO        = $Maquina.VersaoSO
            BuildSO         = $Maquina.BuildSO
            SuporteSO       = if ($Maquina.Online) { Get-StatusSuporteSO -Nome $Maquina.SistemaOperacional -DataReferencia $DataReferencia } else { '' }
            InstaladoEm     = Format-DataHora -Data $Maquina.InstaladoEm
            UltimoBoot      = Format-DataHora -Data $Maquina.UltimoBoot
            IP              = $Maquina.IP
            MAC             = $Maquina.MAC
            Ativacao        = $Maquina.Ativacao
            SoftwareQtd     = @($Maquina.Software).Count
            ColetadoEm      = Format-DataHora -Data $Maquina.ColetadoEm
        }
    }
}

function ConvertTo-RegistroJson {
    # Mantem a estrutura aninhada (discos, software); datas em ISO 8601 porque o
    # ConvertTo-Json do 5.1 serializa DateTime no formato /Date(...)/.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)][object]$Maquina
    )

    process {
        $iso = { param($d) if ($null -eq $d) { $null } else { ([datetime]$d).ToString('s') } }

        [pscustomobject][ordered]@{
            ComputerName       = $Maquina.ComputerName
            Online             = $Maquina.Online
            Erro               = $Maquina.Erro
            Hostname           = $Maquina.Hostname
            Usuario            = $Maquina.Usuario
            Fabricante         = $Maquina.Fabricante
            Modelo             = $Maquina.Modelo
            Serial             = $Maquina.Serial
            CPU                = $Maquina.CPU
            CPUNucleos         = $Maquina.CPUNucleos
            RAMGB              = $Maquina.RAMGB
            Discos             = @($Maquina.Discos)
            SistemaOperacional = $Maquina.SistemaOperacional
            VersaoSO           = $Maquina.VersaoSO
            BuildSO            = $Maquina.BuildSO
            InstaladoEm        = & $iso $Maquina.InstaladoEm
            UltimoBoot         = & $iso $Maquina.UltimoBoot
            IP                 = $Maquina.IP
            MAC                = $Maquina.MAC
            Ativacao           = $Maquina.Ativacao
            Software           = @($Maquina.Software)
            ColetadoEm         = & $iso $Maquina.ColetadoEm
        }
    }
}

function ConvertTo-RelatorioHtml {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowNull()][AllowEmptyCollection()][object[]]$Maquinas,
        [string]$Titulo = 'Inventário de TI',
        [double]$LimiteDisco = $script:LimiteDiscoPadrao,
        [datetime]$DataReferencia = (Get-Date)
    )

    $h = { param($t) ConvertTo-HtmlSeguro -Texto $t }
    $lista = @($Maquinas | Where-Object { $null -ne $_ })
    $resumo = Get-ResumoInventario -Maquinas $lista -LimiteDisco $LimiteDisco -DataReferencia $DataReferencia

    $linhas = foreach ($m in ($lista | Sort-Object -Property @{ Expression = { -not $_.Online } }, ComputerName)) {
        if (-not $m.Online) {
            $motivo = & $h $m.Erro
            "<tr class=""off""><td>$(& $h $m.ComputerName)</td><td><span class=""tag tag-off"">Offline</span></td><td colspan=""7"" class=""muted"">$motivo</td></tr>"
            continue
        }

        $alertas = @(Get-DiscoEmAlerta -Discos $m.Discos -Limite $LimiteDisco)
        $discos = foreach ($d in $m.Discos) {
            $baixo = Test-DiscoBaixo -PercentualLivre $d.PercentualLivre -Limite $LimiteDisco
            $classe = if ($baixo) { 'disk low' } else { 'disk' }
            "<span class=""$classe"">$(& $h $d.Unidade) $(& $h $d.Tipo) $($d.LivreGB.ToString('N1', [cultureinfo]'pt-BR')) / $($d.TamanhoGB.ToString('N0', [cultureinfo]'pt-BR')) GB ($($d.PercentualLivre.ToString('N1', [cultureinfo]'pt-BR'))% livre)</span>"
        }

        $suporte = Get-StatusSuporteSO -Nome $m.SistemaOperacional -DataReferencia $DataReferencia
        $tagSO = switch ($suporte) {
            'Fora de suporte' { '<span class="tag tag-warn">Fora de suporte</span>' }
            'Suportado' { '<span class="tag tag-ok">Suportado</span>' }
            default { '<span class="tag tag-off">Desconhecido</span>' }
        }
        $classeLinha = if ($alertas.Count -gt 0 -or $suporte -eq 'Fora de suporte') { 'attn' } else { '' }

        "<tr class=""$classeLinha""><td><strong>$(& $h $m.ComputerName)</strong><div class=""muted"">$(& $h $m.Fabricante) $(& $h $m.Modelo)</div></td>" +
        "<td><span class=""tag tag-ok"">Online</span></td>" +
        "<td>$(& $h $m.Usuario)</td>" +
        "<td>$(& $h $m.SistemaOperacional)<div class=""muted"">build $(& $h $m.BuildSO)</div>$tagSO</td>" +
        "<td>$(& $h $m.CPU)<div class=""muted"">$(& $h $m.RAMGB) GB RAM</div></td>" +
        "<td>$($discos -join '<br>')</td>" +
        "<td>$(& $h $m.IP)<div class=""muted"">$(& $h $m.MAC)</div></td>" +
        "<td>$(& $h (Format-DataHora -Data $m.UltimoBoot))</td>" +
        "<td class=""num"">$(@($m.Software).Count)</td></tr>"
    }

    $alertasDisco = foreach ($m in $resumo.MaquinasDiscoBaixo) {
        foreach ($d in (Get-DiscoEmAlerta -Discos $m.Discos -Limite $LimiteDisco)) {
            "<li><strong>$(& $h $m.ComputerName)</strong> $(& $h $d.Unidade) $($d.PercentualLivre.ToString('N1', [cultureinfo]'pt-BR'))% livre, restam $($d.LivreGB.ToString('N1', [cultureinfo]'pt-BR')) GB</li>"
        }
    }
    $alertasSO = foreach ($m in $resumo.MaquinasSOForaSuporte) {
        "<li><strong>$(& $h $m.ComputerName)</strong>: $(& $h $m.SistemaOperacional)</li>"
    }

    $blocoAlertas = ''
    if ($alertasDisco -or $alertasSO) {
        $blocoAlertas = '<section class="alerts"><h2>Alertas</h2>'
        if ($alertasDisco) { $blocoAlertas += "<h3>Disco com menos de $LimiteDisco% livre</h3><ul>$($alertasDisco -join '')</ul>" }
        if ($alertasSO) { $blocoAlertas += "<h3>Sistema operacional fora de suporte</h3><ul>$($alertasSO -join '')</ul>" }
        $blocoAlertas += '</section>'
    }

    $geradoEm = (Get-Date).ToString('dd/MM/yyyy HH:mm')

    @"
<!DOCTYPE html>
<html lang="pt-BR">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>$(& $h $Titulo)</title>
<style>
:root { --bg:#f4f6f8; --card:#fff; --text:#1d2733; --muted:#6b7785; --line:#e1e6eb; --ok:#1a7f4b; --warn:#b45309; --bad:#b42318; --accent:#1f4e79; }
@media (prefers-color-scheme: dark) {
  :root { --bg:#10151b; --card:#19212a; --text:#e6ebf0; --muted:#8c98a5; --line:#2a3541; --ok:#4ac08a; --warn:#f0a35e; --bad:#f28b82; --accent:#7fb2e5; }
}
* { box-sizing: border-box; }
body { margin:0; padding:32px 24px 48px; background:var(--bg); color:var(--text); font:14px/1.45 "Segoe UI", system-ui, sans-serif; }
main { max-width:1280px; margin:0 auto; }
h1 { margin:0 0 4px; font-size:24px; color:var(--accent); }
h2 { font-size:17px; margin:28px 0 10px; }
h3 { font-size:14px; margin:14px 0 6px; }
.sub { color:var(--muted); margin-bottom:24px; }
.cards { display:grid; grid-template-columns:repeat(auto-fit, minmax(170px, 1fr)); gap:12px; }
.card { background:var(--card); border:1px solid var(--line); border-radius:8px; padding:14px 16px; }
.card .n { font-size:30px; font-weight:600; line-height:1.1; }
.card .l { color:var(--muted); font-size:12px; text-transform:uppercase; letter-spacing:.04em; }
.card.warn .n { color:var(--warn); }
.card.bad .n { color:var(--bad); }
.card.ok .n { color:var(--ok); }
.alerts { background:var(--card); border:1px solid var(--line); border-left:4px solid var(--warn); border-radius:8px; padding:4px 18px 12px; }
.alerts ul { margin:0; padding-left:20px; }
.wrap { overflow-x:auto; background:var(--card); border:1px solid var(--line); border-radius:8px; }
table { border-collapse:collapse; width:100%; min-width:980px; }
th { text-align:left; font-size:12px; text-transform:uppercase; letter-spacing:.04em; color:var(--muted); padding:10px 12px; border-bottom:1px solid var(--line); }
td { padding:10px 12px; border-bottom:1px solid var(--line); vertical-align:top; }
tr:last-child td { border-bottom:0; }
tr.attn { background:rgba(180,83,9,.07); }
tr.off { background:rgba(180,35,24,.06); }
.muted { color:var(--muted); font-size:12px; }
.num { text-align:right; font-variant-numeric:tabular-nums; }
.tag { display:inline-block; padding:1px 8px; border-radius:10px; font-size:11px; font-weight:600; margin-top:3px; }
.tag-ok { color:var(--ok); border:1px solid var(--ok); }
.tag-warn { color:var(--warn); border:1px solid var(--warn); }
.tag-off { color:var(--bad); border:1px solid var(--bad); }
.disk { display:block; font-size:12px; }
.disk.low { color:var(--bad); font-weight:600; }
footer { margin-top:24px; color:var(--muted); font-size:12px; }
</style>
</head>
<body>
<main>
<h1>$(& $h $Titulo)</h1>
<div class="sub">Gerado em $geradoEm</div>
<div class="cards">
  <div class="card"><div class="n">$($resumo.Total)</div><div class="l">Máquinas</div></div>
  <div class="card ok"><div class="n">$($resumo.Online)</div><div class="l">Online</div></div>
  <div class="card $(if ($resumo.Offline) { 'bad' })"><div class="n">$($resumo.Offline)</div><div class="l">Offline</div></div>
  <div class="card $(if ($resumo.DiscoBaixo) { 'warn' })"><div class="n">$($resumo.DiscoBaixo)</div><div class="l">Disco &lt; $LimiteDisco% livre</div></div>
  <div class="card $(if ($resumo.SOForaSuporte) { 'warn' })"><div class="n">$($resumo.SOForaSuporte)</div><div class="l">SO fora de suporte</div></div>
</div>
$blocoAlertas
<h2>Máquinas</h2>
<div class="wrap">
<table>
<thead><tr><th>Computador</th><th>Status</th><th>Usuário</th><th>Sistema operacional</th><th>CPU / RAM</th><th>Discos</th><th>Rede</th><th>Último boot</th><th class="num">Software</th></tr></thead>
<tbody>
$($linhas -join "`n")
</tbody>
</table>
</div>
<footer>InventarioTI - relatório estático, sem dependências externas.</footer>
</main>
</body>
</html>
"@
}
