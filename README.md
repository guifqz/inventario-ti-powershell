# InventarioTI

[![CI](https://github.com/guifqz/inventario-ti-powershell/actions/workflows/ci.yml/badge.svg)](https://github.com/guifqz/inventario-ti-powershell/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
![PowerShell 5.1 | 7](https://img.shields.io/badge/PowerShell-5.1%20%7C%207-5391FE?logo=powershell&logoColor=white)

> **In short:** a PowerShell module that inventories Windows machines over CIM/WMI (hardware, disks, OS, network, installed software), in parallel and without agents.
> It exports CSV, JSON and a self-contained HTML report with alerts for low disk space and end-of-life operating systems.

Módulo PowerShell para inventário de ativos de TI em redes Windows. Coleta hardware, discos, sistema operacional, rede e software instalado via CIM, em paralelo, sem instalar agente nas estações, e gera relatórios em CSV, JSON e HTML.

Nasceu da rotina de quem coordena TI em uma empresa de médio porte: saber, em minutos e sem planilha manual, quais máquinas estão offline, quais discos estão acabando e quais estações ainda rodam Windows sem suporte.

## O que faz

- **`Get-InventarioMaquina`**: coleta uma máquina (local ou remota) e devolve um objeto com hostname, usuário logado, fabricante/modelo, serial, CPU, RAM, discos (tamanho, livre, SSD/HDD), SO (nome, versão, build, data de instalação, último boot), IP/MAC, status de ativação (opcional) e lista de software instalado (chaves Uninstall de 32 e 64 bits). Host offline não gera exceção: volta marcado como `Online = $false` com o motivo.
- **`Invoke-InventarioRede`**: roda a coleta em várias máquinas ao mesmo tempo (RunspacePool, com `-ThrottleLimit`). A lista pode vir de parâmetro, de arquivo `.txt` ou de uma OU do Active Directory.
- **`Export-InventarioRelatorio`**: exporta para CSV, JSON, HTML e, se o módulo `ImportExcel` estiver instalado, Excel.

O relatório HTML é um arquivo único (CSS embutido, sem JavaScript, sem CDN), com cartões-resumo e tabela de máquinas. Veja um exemplo gerado com dados fictícios em [`docs/exemplo-relatorio.html`](docs/exemplo-relatorio.html) (baixe e abra no navegador).

```
Cartões:  Máquinas 11 | Online 9 | Offline 2 | Disco < 15% livre 3 | SO fora de suporte 3

Alertas
  Disco com menos de 15% livre
    PC-FINANCEIRO-02   C:  8,0% livre, restam 38,2 GB
    PC-COMPRAS-01      C:  9,2% livre, restam 21,9 GB
    SRV-ARQUIVOS-01    E:  8,3% livre, restam 310,8 GB
  Sistema operacional fora de suporte
    PC-RH-01           Microsoft Windows 10 Pro
    PC-RECEPCAO-01     Microsoft Windows 7 Professional
    SRV-ARQUIVOS-01    Microsoft Windows Server 2012 R2 Standard
```

Saída de `Invoke-InventarioRede` no console (dados fictícios):

```
ComputerName       Online Usuario               SistemaOperacional                        RAMGB IP
------------       ------ -------               ------------------                        ----- --
PC-FINANCEIRO-01     True EMPRESA\ana.souza     Microsoft Windows 11 Pro                     16 192.0.2.11
PC-FINANCEIRO-02     True EMPRESA\carlos.lima   Microsoft Windows 11 Pro                     16 192.0.2.12
PC-RH-01             True EMPRESA\marta.reis    Microsoft Windows 10 Pro                      8 192.0.2.21
PC-RECEPCAO-01       True                       Microsoft Windows 7 Professional              4 192.0.2.31
SRV-ARQUIVOS-01      True                       Microsoft Windows Server 2012 R2 Standard    32 192.0.2.5
PC-ALMOXARIFADO-01  False
```

## Requisitos

- Windows PowerShell 5.1 ou PowerShell 7+ (a coleta é sempre feita a partir de uma máquina Windows).
- Para coletar máquinas remotas: WinRM habilitado nos alvos (padrão) ou `-Protocolo Dcom`, regra de firewall liberando CIM/WMI e uma conta com permissão administrativa nos alvos.
- Opcional: módulo `ActiveDirectory` (RSAT) para `-OrganizationalUnit` e `ImportExcel` para exportar `.xlsx`.

## Instalação

Ainda não está na PowerShell Gallery. Clone o repositório e importe o módulo:

```powershell
git clone https://github.com/guifqz/inventario-ti-powershell.git
cd inventario-ti-powershell
Import-Module .\InventarioTI\InventarioTI.psd1
```

Para deixar disponível em todas as sessões, copie a pasta `InventarioTI` para `$HOME\Documents\WindowsPowerShell\Modules` (5.1) ou `$HOME\Documents\PowerShell\Modules` (7).

## Uso

Máquina local:

```powershell
Get-InventarioMaquina | Format-List
```

Uma máquina remota, com credencial e status de ativação:

```powershell
$cred = Get-Credential
Get-InventarioMaquina -ComputerName PC-FINANCEIRO-01 -Credential $cred -IncluirAtivacao
```

Várias máquinas em paralelo, a partir de um arquivo (um nome por linha, `#` comenta; veja [`computadores.exemplo.txt`](computadores.exemplo.txt)):

```powershell
$inventario = Invoke-InventarioRede -Path .\computadores.txt -ThrottleLimit 16 -Credential $cred
```

Uma OU do Active Directory (precisa do RSAT):

```powershell
Invoke-InventarioRede -OrganizationalUnit 'OU=Estacoes,DC=empresa,DC=local' -SemSoftware
```

Gerar os relatórios:

```powershell
$inventario | Export-InventarioRelatorio -Path .\saida                          # CSV + JSON + HTML
$inventario | Export-InventarioRelatorio -Path .\saida -Formato HTML -LimiteDisco 20
$inventario | Export-InventarioRelatorio -Path .\saida -Formato Excel           # requer ImportExcel
```

Consultas rápidas sobre o resultado:

```powershell
$inventario | Where-Object Online -eq $false | Select-Object ComputerName, Erro
$inventario.Software | Group-Object Nome | Sort-Object Count -Descending | Select-Object -First 10
```

### Parâmetros úteis

| Parâmetro | Em | Efeito |
|---|---|---|
| `-ThrottleLimit` | `Invoke-InventarioRede` | Máquinas coletadas ao mesmo tempo (padrão 16) |
| `-SemSoftware` | `Get-InventarioMaquina`, `Invoke-InventarioRede` | Pula a leitura do software instalado (bem mais rápido) |
| `-IncluirAtivacao` | `Get-InventarioMaquina`, `Invoke-InventarioRede` | Consulta o status de ativação do Windows |
| `-Protocolo Dcom` | idem | Usa DCOM em vez de WinRM |
| `-LimiteDisco` | `Export-InventarioRelatorio` | % livre abaixo do qual o disco alerta (padrão 15) |
| `-WhatIf` | `Export-InventarioRelatorio` | Mostra o que seria gravado, sem gravar |

Ajuda completa: `Get-Help Get-InventarioMaquina -Full`.

## Como funciona

```
InventarioTI/
  Public/    funções exportadas (Get-InventarioMaquina, Invoke-InventarioRede, Export-InventarioRelatorio)
  Private/
    Logica.ps1             regras puras: % livre, alerta de disco, fim de suporte do SO, escape HTML, resumo
    Cim.ps1                camada fina sobre Get-CimInstance / New-CimSession / StdRegProv (mockável)
    Coleta.ps1             discos e tipo SSD/HDD, ativação
    Relatorio.ps1          registros planos (CSV), JSON e geração do HTML
    ListaComputadores.ps1  arquivo .txt, OU do AD, deduplicação
```

Decisões de projeto:

- **Lógica pura separada do acesso ao sistema.** Regras como "disco abaixo de 15%" e "Windows 10 está fora de suporte?" não tocam CIM nem disco, então são testadas sem mock. A tabela de fim de suporte aceita uma data de referência, o que torna a classificação determinística nos testes.
- **Software via `StdRegProv`, não `Win32_Product`.** `Win32_Product` é lento e dispara reconfiguração de pacotes MSI. Ler as chaves Uninstall pelo provedor de registro funciona pelo mesmo canal CIM, sem exigir PowerShell Remoting.
- **Tipo SSD/HDD** vem de `MSFT_PhysicalDisk` mapeado para a letra via `MSFT_Partition`. Em sistemas sem esse namespace (Windows 7, por exemplo) o tipo aparece como `Desconhecido`.
- **Paralelismo com RunspacePool**, não `ForEach-Object -Parallel`, para funcionar igual no 5.1 e no 7. Cada runspace importa o módulo e executa `Get-InventarioMaquina`.
- **Falha por máquina não derruba o lote.** Ping sem resposta, acesso negado ou timeout viram um registro com `Online = $false` e `Erro` preenchido; o relatório mostra essas máquinas como offline.
- **Fim de suporte do SO** segue as datas publicadas pela Microsoft (Windows 10 em 14/10/2025, Server 2012 R2 em 10/10/2023, etc.). Máquinas com ESU (atualizações estendidas pagas) aparecem como "fora de suporte" mesmo assim; trate no relatório conforme a sua realidade.

## Testes

Os testes usam Pester 5 e simulam o CIM com mocks, então rodam em qualquer máquina, inclusive no CI:

```powershell
Install-Module Pester -RequiredVersion 5.7.1 -Scope CurrentUser -Force -SkipPublisherCheck
Invoke-Pester -Path .\tests
```

Análise estática:

```powershell
Install-Module PSScriptAnalyzer -Scope CurrentUser
Invoke-ScriptAnalyzer -Path . -Recurse -Settings .\PSScriptAnalyzerSettings.psd1
```

Para regenerar o relatório de exemplo: `.\tools\Gerar-Exemplo.ps1`.

> Os arquivos `.ps1`, `.psm1` e `.psd1` são salvos em UTF-8 com BOM (veja `.editorconfig`). O Windows PowerShell 5.1 lê script sem BOM como ANSI e corrompe os acentos.

## Roadmap

- [ ] Publicar na PowerShell Gallery
- [ ] Inventário de impressoras de rede e monitores (EDID)
- [ ] Coleta de status do BitLocker e do antivírus
- [ ] Comparar duas execuções e destacar mudanças (software novo, troca de hardware)
- [ ] Envio do relatório por e-mail e agendamento via Task Scheduler
- [ ] Relatório HTML com busca e ordenação por coluna
- [ ] Exportação para SQLite / SQL Server

Sugestões e pull requests são bem-vindos.

## Licença

[MIT](LICENSE) © 2026 Guilherme
