# Logs das execuções de teste

Saída bruta de cada execução, organizada por dia. As pastas guardam também as
tentativas que falharam, porque foram elas que motivaram as correções.

Status: ✅ passou · ❌ falhou · ⚠️ passou com ressalva.

## 2026-11-10-primeira-validacao

Primeiro dia, com o ambiente sendo corrigido entre uma execução e outra.

| Arquivo | O que é | Status |
|---|---|---|
| `01-vagrant-up-travou-no-ufw.log` | Primeiro `vagrant up`: o Ansible travou ao ativar o UFW nos nós K3s (conexão SSH descartada pelo conntrack). Interrompido. | ❌ |
| `02-provisionamento.log` | Reprovisionamento depois da correção do UFW (`async` + `reset_connection`) | ✅ `failed=0` |
| `03-idempotencia.log` | Idempotência depois de trocar o Secret de `stringData` para `data` (a execução anterior, com `changed=1` no bastion, foi sobrescrita) | ✅ `changed=0` |
| `04-provisionamento-keepalived-fault.log` | Aplicação da troca de `weight -20` para estado FAULT no Keepalived | ✅ |
| `teste-A.txt` | Balanceamento: pods alternando entre os dois nós | ✅ |
| `teste-B.txt` | Failover depois da troca para FAULT: 1 requisição perdida (a primeira tentativa, com `weight`, levou ~5 s e não foi salva) | ✅ |
| `teste-C.txt` | Suspend/resume: API em 57 s, registro preservado | ✅ |
| `teste-C-HALT.txt` | Halt/up: API em 108 s, registro preservado | ✅ |
| `teste-D.txt` | Reconciliação: 2/2 em 4 s | ✅ |

## 2026-11-10-ambiente-do-zero

Resultados de referência do dia 10: `vagrant destroy -f && vagrant up` com todas as
correções daquele dia e a bateria completa em seguida.

| Arquivo | O que é | Status |
|---|---|---|
| `01-destroy-e-up-do-zero.log` | Criação do zero em 11 min 46 s | ✅ `failed=0` |
| `02-idempotencia.log` | Segunda execução | ✅ `changed=0` |
| `teste-A.txt` | 6 respostas do k3s-worker, 4 do k3s-server | ✅ |
| `teste-B.txt` | VIP na VM 4 em 1,09 s (logs do Keepalived no fim do arquivo) | ✅ |
| `teste-C-suspend.txt` | API em 51 s, registro preservado | ✅ |
| `teste-C-halt.txt` | API em 108 s, pods e VIP restabelecidos | ✅ |
| `teste-D.txt` | 2/2 em 4 s | ✅ |

## 2026-11-12-reexecucao

Reexecução dois dias depois, com as VMs desligadas desde o dia 10. Revelou problemas
que não apareciam com o ambiente recém-criado.

| Arquivo | O que é | Status |
|---|---|---|
| `01-vagrant-up-vms-desligadas.log` | `vagrant up` com as VMs desligadas: API em 112 s, sem reprovisionar | ✅ |
| `02-idempotencia-changed1-cache-apt.log` | `changed=1` em todas as VMs (cache do apt expirado) e failover falso: health check estourou o timeout de 1 s com o bastion ocupado | ❌ |
| `03-provisionamento-correcoes.log` | Aplicação de `changed_when: false` no cache do apt e `timeout 3` no health check | ✅ |
| `teste-A.txt`, `teste-B.txt`, `teste-D.txt` | Bateria antes das mudanças de ordem/IP: B em 0,84 s, D em 3 s | ✅ |
| `teste-C-suspend-80s.txt` | Suspend/resume: API em 80 s | ❌ > 60 s |
| `teste-C-halt-vm4-travou-no-boot.txt` | Halt/up: kernel da VM 4 travou no boot (VirtualBox) e o Vagrant desistiu após 15 min | ❌ |
| `teste-C-halt-recuperacao.log` | VM 4 desligada à força e religada: API em 40 s, registros preservados | ✅ |
| `teste-C-suspend-61s-com-horarios.txt` | Suspend/resume com horário por linha: a API só voltava com o bastion | ❌ 61 s |
| `resume-ordem-nova-1.txt`, `resume-ordem-nova-2.txt` | Nova ordem de retomada no Vagrantfile: 37 s e 71 s (instável) | ⚠️ |
| `teste-C-suspend-ordem-nova-65s.txt` | Script do Teste C com a nova ordem: 65 s | ❌ |
| `04-provisionamento-ip-fixo-postgres.log` | Service do Postgres com IP fixo (a API não depende mais do DNS do k3s-server) | ✅ |
| `05-provisionamento-spread-auxiliary-unreachable.log` | Distribuição de réplicas obrigatória; VM 4 inacessível por carga das atualizações automáticas do Ubuntu | ⚠️ |
| `06-provisionamento-timers-apt.log` | Desativação dos timers de atualização automática | ✅ |
| `07-idempotencia-final.log` | Segunda execução com tudo aplicado | ✅ `changed=0` |
| `resume-final-1.txt`, `resume-final-2.txt` | Retomada com todas as correções: VIP em 52 s e 38 s | ✅ |

## 2026-11-12-final

Bateria completa com a configuração final. Tempos de cada script em `00-tempos.txt`.

| Arquivo | Resultado | Status |
|---|---|---|
| `teste-A.txt` | 6 respostas do k3s-server, 4 do k3s-worker | ✅ |
| `teste-D.txt` | 2/2 em 3 s | ✅ |
| `teste-B.txt` | VIP na VM 4 em 0,57 s; 1 requisição perdida | ✅ |
| `teste-C-suspend.txt` | API em 51 s, registro preservado | ✅ |
| `teste-C-halt.txt` | API em 127 s após o `vagrant up`; registro preservado; 3 pods `Running` (uma réplica da API em cada nó) e VIP de volta ao bastion | ✅ |
