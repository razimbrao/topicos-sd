# TP1 — Infraestrutura de Sistemas Distribuídos e Automação de Segurança

**DCC091A — Tópicos em Redes e Processamento Distribuído I** · 2026.3

Infraestrutura local de 4 VMs provisionada de forma **determinística e reprodutível** via
Vagrant (IaC) e endurecida via Ansible (DevSecOps). Nenhuma configuração é aplicada
manualmente: tudo o que existe no ambiente está descrito neste repositório.

## Topologia

```
                       HOST (Windows) ── VirtualBox
                              │
                    NAT (saída p/ internet em todas as VMs)
                              │
  Cliente ──HTTP:80──► ┌──────────────┐  rede host-only 192.168.56.0/24
                       │   bastion    │  .10  Nginx proxy reverso
                       │ (nó Ansible) │       + nó de controle
                       └──────┬───────┘
                     ┌────────┴────────┐
                     ▼                 ▼
              ┌────────────┐    ┌────────────┐
              │    web1    │    │    web2    │   .11 / .12  Nginx
              └─────┬──────┘    └──────┬─────┘
                    └────── rsyslog ───┘
                              ▼
                       ┌────────────┐
                       │     db     │  .13  rsyslog server
                       └─────┬──────┘
                             ▼
              synced_folder → ./data/dados_persistentes  (host físico)
                        « Fonte da Verdade »
```

| VM | IP host-only | Função | Portas expostas |
|---|---|---|---|
| `bastion` | 192.168.56.10 | Ponto único de entrada, proxy reverso, nó de controle Ansible | 22, 80, 443 |
| `web1` | 192.168.56.11 | Nó de processamento de aplicação | 22, 80, 443 |
| `web2` | 192.168.56.12 | Nó secundário (redundância/balanceamento) | 22, 80, 443 |
| `db` | 192.168.56.20 | Centralizador de logs (rsyslog) e persistência | 22, 80, 443 + 514 restrito à rede interna |

## Pré-requisitos no host

VirtualBox 7.x, Vagrant 2.4.x, Git e Nmap. O Ansible **não** é instalado no host — ele roda
dentro da VM `bastion`, que é o nó de controle. Isso mantém o ambiente reprodutível em
qualquer sistema operacional.

## Implantação

```bash
cd vagrant && vagrant up
```

A ordem de criação é intencional: `web1`, `web2` e `db` sobem primeiro, e o `bastion` por
último — ele precisa das chaves privadas das demais VMs (em `.vagrant/machines`) para
provisioná-las via Ansible.

Reaplicar o playbook a qualquer momento (a idempotência garante que nada quebre):

```bash
cd vagrant && vagrant provision bastion
```

## Estrutura

```
├── ansible/            # Playbooks, roles idempotentes e inventário
│   ├── ansible.cfg
│   ├── inventory.ini
│   ├── site.yml
│   └── roles/          # common, hardening, nginx_proxy, web_node, log_client, log_server
├── vagrant/            # Vagrantfile e bootstrap inicial
├── data/               # Volume persistente montado na VM db (conteúdo não versionado)
├── docs/               # Relatórios de testes e documentação técnica
├── scripts/            # Utilitários de validação
└── README.md
```

## Validação

### 1. Rede (NAT + DNS + host-only)

```bash
cd vagrant && vagrant ssh web1 -c "bash /scripts/validar-rede.sh"
```

### 2. Proxy reverso e balanceamento

```bash
curl -s http://192.168.56.10/ | grep "no:"
```

Requisições repetidas devem alternar entre `web1` e `web2`, sem que o cliente conheça a
topologia interna (transparência de acesso).

### 3. Teste de sobrevivência

```bash
powershell -ExecutionPolicy Bypass -File .\scripts\teste-sobrevivencia.ps1
```

O script registra a última linha de `db.log`, executa `vagrant destroy -f db`, reconstrói a
VM e confirma que o registro anterior continua presente — provando que o estado sobreviveu à
destruição da lógica computacional.

### 4. Auditoria de segurança

```bash
powershell -ExecutionPolicy Bypass -File .\scripts\auditar-seguranca.ps1
```

| Ação de segurança | Procedimento | Resultado esperado |
|---|---|---|
| SSH key-only | `ssh -o PreferredAuthentications=password vagrant@ip` | Permission denied |
| Root restriction | `ssh root@ip` | Conexão negada |
| Firewall UFW | `nmap -p 22,80,443,514,3306 ip` | Apenas 22/80/443 abertas |

### Validação em ambiente Linux

O setup separado em `vagrant-linux/` sobe a VM `linux` (192.168.56.30), uma estação Ubuntu fora
do cluster e do inventário Ansible, com `nmap`, `curl` e `dig`. A raiz do repositório é montada
em `/projeto`.

```bash
cd vagrant-linux && vagrant up
vagrant ssh -c "bash /projeto/scripts/auditar-seguranca.sh"
vagrant ssh -c "bash /projeto/scripts/validar-rede.sh"
vagrant ssh -c "curl -s http://192.168.56.10/ | grep 'no:'"
```

O teste de sobrevivência depende do Vagrant e roda no host Linux que executa o cluster:
`bash scripts/teste-sobrevivencia.sh`.

### 5. Idempotência

```bash
cd vagrant && vagrant provision bastion
```

Na segunda execução consecutiva o resumo do Ansible deve apresentar `changed=0` em todos os
hosts.

## Decisões técnicas

- **`db` expõe 514 apenas para os IPs de `bastion`, `web1` e `web2`.** A política de permissão mínima do roteiro
  trata do acesso *externo*; o canal de logs é interno e ficaria inutilizável
  se bloqueado. A regra é restrita host a host — nem o host físico (192.168.56.1) enxerga
  a porta, então a varredura nmap mostra apenas 22/80/443 em todas as VMs.
- **`dmode=777`/`fmode=666` no synced_folder.** O sistema de arquivos `vboxsf` ignora
  `chown`/`chmod` feitos dentro da VM; sem essas opções de montagem o `rsyslogd` (usuário
  `syslog`) não conseguiria escrever no volume persistente.
- **Encaminhamento de logs via TCP com fila em disco.** Se o `db` estiver fora do ar durante
  o teste de sobrevivência, os clientes retêm os registros e os reenviam na volta — atacando
  diretamente a "Cilada #1: a rede é confiável".
- **Sem timestamps nos templates.** Um valor que muda a cada execução geraria `changed` eterno
  e quebraria a idempotência exigida na avaliação.

## Documentação complementar

Relatórios de execução dos testes em [`docs/`](docs/).
