# Preparar as estações para o inventário (WinRM, WMI e coletor local)

O módulo precisa de uma destas portas abertas nas estações para coletar remotamente:

| Caminho | Porta | Quando usar |
|---|---|---|
| WinRM (preferido) | TCP 5985 | Funciona em Windows 7/8/10/11 e Server, com um único serviço e uma regra de firewall |
| DCOM/WMI (alternativa, `-Protocolo Auto` cai para ele sozinho) | TCP 135 + portas RPC dinâmicas (49152-65535) | Quando não dá para habilitar WinRM |
| Coletor local (sem acesso remoto) | nenhuma entrada; a estação grava um JSON num compartilhamento | Quando nenhum dos dois pode ser aberto |

Sem nenhuma GPO, a estação responde `SemWinRMeDcom` no relatório. Os passos abaixo valem para um controlador de domínio Windows Server 2012 (não R2); os caminhos do Gerenciamento de Política de Grupo são os mesmos nas versões mais novas.

> Substitua `contoso.local`, `192.0.2.0/24` e `SRV-ARQUIVOS-01` pelos valores do seu ambiente.

## 1. Habilitar WinRM por GPO

No servidor, abra **Gerenciamento de Política de Grupo** (`gpmc.msc`), crie uma GPO (ex.: `Inventario - WinRM`) e vincule à OU que contém as **contas de computador** das estações.

### 1.1 Serviço WinRM em início automático

`Configuração do Computador > Preferências > Configurações do Painel de Controle > Serviços > Novo > Serviço`

- Nome do serviço: `WinRM`
- Inicialização: **Automático** (ou Automático - atraso)
- Ação do serviço: **Iniciar serviço**

### 1.2 Listener HTTP (porta 5985)

`Configuração do Computador > Políticas > Modelos Administrativos > Componentes do Windows > Gerenciamento Remoto do Windows (WinRM) > Serviço WinRM`

- **Permitir o gerenciamento remoto de servidor por meio do WinRM**: *Habilitada*
- Filtro IPv4: `*` (ou a sub-rede da LAN, `192.0.2.0/24`)
- Filtro IPv6: vazio

Esta política cria o listener e a regra de escuta. Em estações Windows 10/11 o serviço sobe com o ajuste 1.1.

### 1.3 Firewall: 5985 restrita à rede local

`Configuração do Computador > Políticas > Configurações do Windows > Configurações de Segurança > Windows Defender Firewall com Segurança Avançada > Regras de Entrada > Nova Regra > Personalizada`

- Programa: todos; Protocolo: **TCP**, porta local **5985**
- Escopo > endereços IP remotos: **`192.0.2.0/24`** (a sub-rede de quem inventaria; não deixe "qualquer endereço")
- Ação: permitir a conexão; perfis: **Domínio** (e Privado, se for o caso)
- Nome: `WinRM-In inventario (LAN)`

Se preferir, restrinja também ao IP do PC de inventário (`192.0.2.50`).

### 1.4 Permissões

O usuário que roda o inventário precisa ser administrador local das estações. Em domínio, o grupo **Admins do Domínio** já entra no grupo local *Administradores*; confirme se nenhuma GPO de "Grupos restritos" o remove.

### 1.5 Aplicar e conferir

Nas estações: `gpupdate /force` (ou reiniciar). No PC de inventário:

```powershell
Test-NetConnection PC-FINANCEIRO-01 -Port 5985      # TcpTestSucceeded : True
Test-WSMan PC-FINANCEIRO-01                          # devolve a versão do protocolo
```

## 2. Alternativa: liberar DCOM/WMI no firewall

Se o WinRM não puder ser habilitado, crie outra GPO (`Inventario - WMI`) e habilite a regra interna:

`Configuração do Computador > Políticas > Configurações do Windows > Configurações de Segurança > Windows Defender Firewall com Segurança Avançada > Regras de Entrada > Nova Regra > Predefinida > Instrumentação de Gerenciamento do Windows (WMI)`

Marque **Instrumentação de Gerenciamento do Windows (WMI-In)** (nome em inglês: *Windows Management Instrumentation (WMI-In)*) e restrinja o escopo ao IP/sub-rede do PC de inventário, como em 1.3.

Alternativa por política de computador: `Modelos Administrativos > Rede > Conexões de Rede > Firewall do Windows > Perfil de Domínio > Firewall do Windows: Permitir exceção de administração remota de entrada` (habilita RPC 135/445 para administradores).

Conferência:

```powershell
Test-NetConnection PC-FINANCEIRO-01 -Port 135
Get-CimInstance Win32_OperatingSystem -ComputerName PC-FINANCEIRO-01   # usa DCOM, sem WinRM
```

Com as duas GPOs, `-Protocolo Auto` (padrão) usa WinRM e só recorre ao DCOM quando a porta 5985 não responde.

## 3. Coletor local por GPO de inicialização

Cada estação roda `Coletar-Local.ps1` ao ligar e grava `<NOME-DO-PC>.json` num compartilhamento. Não exige nenhuma porta de entrada na estação, e o inventário passa a incluir máquinas que o PC de inventário não alcança (notebooks fora da rede, outras sub-redes).

### 3.1 Compartilhamento

No servidor de arquivos, crie a pasta `D:\Ativos` e compartilhe como `Ativos`:

| Onde | Quem | Permissão |
|---|---|---|
| Compartilhamento | `Computadores do Domínio` | **Alterar** (ou Controle Total) |
| NTFS (pasta `Ativos`) | `Computadores do Domínio` | **Modificar** (somente esta pasta e arquivos) |
| NTFS | `Admins do Domínio` | Controle Total |
| Compartilhamento e NTFS (subpasta `Coletor`) | `Computadores do Domínio` | **Leitura e execução** |

A conta SYSTEM acessa a rede como a conta do computador (`PC-XXX$`), que pertence ao grupo *Computadores do Domínio*. Se as estações ficarem em outro domínio ou floresta, use o grupo equivalente de lá.

Prefira uma pasta dedicada: o JSON contém lista de software, usuário logado e dados de rede. Tire a permissão de leitura de `Ativos` de usuários comuns.

### 3.2 Publicar o coletor

```text
\\SRV-ARQUIVOS-01\Ativos\Coletor\Coletar-Local.ps1
\\SRV-ARQUIVOS-01\Ativos\Coletor\InventarioTI\    (a pasta do módulo, com InventarioTI.psd1)
```

Copie `tools\Coletar-Local.ps1` e a pasta `InventarioTI` do repositório. Para atualizar o módulo, basta sobrescrever a pasta.

### 3.3 GPO de script de inicialização

`Configuração do Computador > Políticas > Configurações do Windows > Scripts (Inicialização/Desligamento) > Inicialização > aba Scripts do PowerShell > Adicionar`

- Nome do script: `\\SRV-ARQUIVOS-01\Ativos\Coletor\Coletar-Local.ps1`
- Parâmetros: `-PastaDestino \\SRV-ARQUIVOS-01\Ativos`

Na mesma GPO, em `Modelos Administrativos > Sistema > Scripts`:

- **Executar scripts de inicialização de forma assíncrona**: *Habilitada* (não atrasa o boot)
- **Especificar tempo de espera máximo para scripts de política de grupo**: 600 segundos

Se a política de execução bloquear o script, use a aba **Scripts** (não a do PowerShell) com `powershell.exe` e os parâmetros `-NoProfile -ExecutionPolicy Bypass -File \\SRV-ARQUIVOS-01\Ativos\Coletor\Coletar-Local.ps1 -PastaDestino \\SRV-ARQUIVOS-01\Ativos`.

O coletor pula a coleta se o JSON da máquina tem menos de 12 horas (`-IntervaloHoras`; use `-Forcar` para ignorar). Para renovar durante o dia sem reiniciar, agende o mesmo comando como tarefa agendada de computador (conta SYSTEM) via GPO em `Preferências > Configurações do Painel de Controle > Tarefas Agendadas`.

### 3.4 Teste manual numa estação

Em um PowerShell elevado:

```powershell
.\Coletar-Local.ps1 -PastaDestino \\SRV-ARQUIVOS-01\Ativos -CaminhoModulo \\SRV-ARQUIVOS-01\Ativos\Coletor\InventarioTI -Forcar -Verbose
```

Para testar como o SYSTEM (que é o que a GPO usa), rode o mesmo comando com `psexec -s -i powershell.exe`.

### 3.5 Usar no inventário

```powershell
.\Inventariar-Rede.ps1 -Saida C:\Inventario -PastaColetaLocal \\SRV-ARQUIVOS-01\Ativos
```

Para cada máquina vale a coleta com dados mais recentes (remota ou local). No relatório, a coluna *Coleta* mostra a origem e o drawer de detalhes mostra a idade dos dados.

## Problemas comuns

| Sintoma no relatório | Causa provável | Ação |
|---|---|---|
| `Offline` | Desligada, em outra rede, ou conta antiga no AD | Confira o ping; se for conta obsoleta, desative no AD. O módulo testa também as portas 135/445/5985, então bloqueio de ICMP não gera falso offline |
| `Acesso negado` | Usuário não é administrador local da estação | Rode com conta de Admins do Domínio ou `-Credential` |
| `Sem WinRM/DCOM` | Nenhuma das duas portas abertas | Aplique a GPO 1 ou 2, ou o coletor local (3) |
| `Erro` com tempo esgotado | Firewall descartando pacotes (em vez de recusar) ou máquina lenta | Revise o escopo da regra; aumente `-TimeoutSegundos` |
| Nunca inventariado e "Possivelmente inativo" | Conta sem logon há mais de 90 dias | Confirme se a máquina ainda existe; senão, remova do AD |
