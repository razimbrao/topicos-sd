# Relatório de Testes — TP1

Ambiente validado em 12/09/2026, host Windows 11 + VirtualBox 7.2.16 + Vagrant 2.4.9.

## 0. Pré-condição do host

O VirtualBox exige acesso direto ao AMD-V. Com o hypervisor da Microsoft ativo
(Hyper-V / VBS), as VMs travavam no boot do kernel aos ~3.9s de forma intermitente.
Configuração final do host:

| Item | Valor exigido |
|---|---|
| `SVM Mode` (BIOS) | Enabled |
| `bcdedit hypervisorlaunchtype` | Off |
| Recurso `VirtualMachinePlatform` | Desabilitado |
| `HypervisorPresent` | False |
| VBS status | 0 (desligado) |

## 1. Provisionamento e rede

`vagrant up --provision` cria as 4 VMs, cada uma com NAT (adapter 1) e host-only
(adapter 2). Saída externa e DNS validados via `scripts/validar-rede.sh`.

```
PLAY RECAP
192.168.56.10 (bastion) : ok=18  changed=0   unreachable=0  failed=0
192.168.56.11 (web1)    : ok=20  changed=13  unreachable=0  failed=0
192.168.56.12 (web2)    : ok=20  changed=13  unreachable=0  failed=0
192.168.56.13 (db)      : ok=22  changed=14  unreachable=0  failed=0
```

## 2. Proxy reverso e balanceamento

Seis requisições consecutivas a `http://192.168.56.10/`, o único endereço conhecido
pelo cliente:

```
resposta de: web1
resposta de: web2
resposta de: web1
resposta de: web2
resposta de: web1
resposta de: web2
```

Alternância round-robin confirmada. A topologia interna permanece opaca ao cliente
(transparência de acesso).

## 3. Teste de sobrevivência

| Momento | Linhas em `db.log` | Último registro |
|---|---|---|
| Antes do `destroy` | 245 | `Sep 12 17:07:36 db tp1-estado: registro persistente gerado em 2026-09-12T17:07:36+00:00` |
| Depois do `up` | 332 | continuidade preservada |

```
[APROVADO] O registro anterior ao destroy continua presente.
O estado sobreviveu a aniquilacao da logica computacional.
```

O arquivo não foi recriado: cresceu a partir do conteúdo anterior. O `PLAY RECAP`
da recuperação reforça a separação entre estado e lógica — apenas o nó reconstruído
sofreu alterações:

```
192.168.56.13 (db)  : changed=13   <- VM recriada do zero
demais hosts        : changed=0    <- intocados
```

## 4. Auditoria de segurança

| Ação de segurança | Resultado observado | Veredito |
|---|---|---|
| SSH key-only | `Permission denied (publickey)` nas 4 VMs | ✅ |
| Root restriction | `Permission denied (publickey)` nas 4 VMs | ✅ |
| Firewall UFW | apenas 22/80/443 acessíveis; 3306 e 8080 filtradas | ✅ |

Varredura final no `db`, o nó mais sensível por hospedar o rsyslog:

```
22/tcp   open     ssh
80/tcp   closed   http
443/tcp  closed   https
514/tcp  filtered shell
3306/tcp filtered mysql
```

A porta 514 aparece como `filtered` mesmo a partir do host físico: a liberação é
feita host a host (apenas `bastion`, `web1` e `web2`), não por sub-rede. A
centralização de logs segue operante — os quatro nós gravaram com timestamps
correntes após a restrição.

Observação: 80 e 443 aparecem `closed` no `db` porque a política do UFW as permite,
mas nenhum serviço escuta nelas naquele nó. Nas VMs web e no bastion, a 80 aparece
`open`.

## 5. Idempotência

Segunda execução consecutiva de `vagrant provision bastion`, sem nenhuma alteração
de código entre as rodadas:

```
192.168.56.10 : ok=18  changed=0  unreachable=0  failed=0
192.168.56.11 : ok=17  changed=0  unreachable=0  failed=0
192.168.56.12 : ok=17  changed=0  unreachable=0  failed=0
192.168.56.13 : ok=19  changed=0  unreachable=0  failed=0
```

`changed=0` em todos os hosts — o playbook descreve estado final, não passos.
