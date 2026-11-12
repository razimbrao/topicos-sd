# TP2 — Orquestração K3s, Proxy HA e Persistência Não Destrutiva

**DCC091A — Tópicos em Redes e Processamento Distribuído I** · 2026.3

Evolução do TP1: a aplicação passa a rodar em um cluster **K3s** de dois nós, atrás de dois
proxies **Nginx** coordenados pelo **Keepalived** com um **VIP flutuante** (192.168.56.254).
Todo o ambiente é criado por `vagrant up` e pode ser pausado (`suspend`/`halt`) e retomado
sem reprovisionar.

## Topologia

```
                          Cliente (host 192.168.56.1)
                                   │  http://192.168.56.254  (VIP / VRRP)
                 ┌─────────────────┴─────────────────┐
                 ▼                                   ▼
        ┌─────────────────┐   VRRP unicast   ┌─────────────────┐
        │ VM1 bastion .10 │ ◄──────────────► │ VM4 auxiliary .40│
        │ Nginx + KA MASTER│                 │ Nginx + KA BACKUP│
        │ prio 101        │                  │ prio 100         │
        │ Ansible/kubectl │                  │ backup → ./data_backup
        └────────┬────────┘                  └────────┬────────┘
                 └──── upstream least_conn :30080 ────┘
                 ┌─────────────────┴─────────────────┐
                 ▼                                   ▼
        ┌──────────────────┐   flannel VXLAN  ┌──────────────────┐
        │ VM2 k3s-server .20│ ◄─────────────► │ VM3 k3s-worker .30│
        │ control plane    │                  │ agent            │
        │ tp2-api (pod)    │                  │ tp2-api (pod)    │
        │ postgres + PVC   │  (local-path; o nó do banco é escolhido pelo scheduler)
        └──────────────────┘                  └──────────────────┘
```

| VM | IP | vCPU / RAM | Papel |
|---|---|---|---|
| `bastion` (dcc091a-vm1) | 192.168.56.10 | 1 / 1024 MB | Nó de controle Ansible, kubectl, build da imagem, Nginx + Keepalived MASTER (101) |
| `k3s-server` (dcc091a-vm2) | 192.168.56.20 | 2 / 2048 MB | K3s server (control plane, datastore, CoreDNS, local-path) |
| `k3s-worker` (dcc091a-vm3) | 192.168.56.30 | 2 / 2048 MB | K3s agent |
| `auxiliary` (dcc091a-vm4) | 192.168.56.40 | 1 / 1024 MB | Nginx + Keepalived BACKUP (100), backup em `./data_backup` |

## Pré-requisitos

VirtualBox 7.x, Vagrant 2.4.x e acesso à internet (pacotes, K3s, imagens base). O Ansible
**não** roda no host: ele é instalado no `bastion`, que provisiona as demais VMs.

> As VMs do TP1 usam os mesmos IPs (.10/.20/.30). Elas precisam estar desligadas.

## Execução

```bash
cd tp2
vagrant up                      # cria as 4 VMs; o bastion sobe por último e roda o site.yml
curl http://192.168.56.254/info
```

O `bastion` é definido por último no `Vagrantfile` porque precisa das chaves privadas das
outras VMs (em `.vagrant/machines`, montado em `/home/vagrant/machines`). As demais seguem a
ordem `k3s-worker`, `auxiliary`, `k3s-server` (ver "Retomada rápida" abaixo).

Reaplicar o playbook (idempotente — a segunda execução termina com `changed=0`):

```bash
vagrant provision bastion
```

Usar o kubectl do bastion (kubeconfig exportado pelo papel `k3s_server`):

```bash
vagrant ssh bastion -c "kubectl get nodes,pods -o wide"
```

## Estrutura

```
tp2/
├── Vagrantfile
├── ansible/
│   ├── ansible.cfg
│   ├── inventory/hosts.yml
│   ├── site.yml
│   └── roles/
│       ├── common/       pacotes, fuso, /etc/hosts, ip_forward, UFW
│       ├── proxy_ha/     Nginx (upstream :30080) + Keepalived (VIP) + check_nginx.sh
│       ├── k3s_server/   instala o server, extrai o token, exporta o kubeconfig p/ o bastion
│       ├── k3s_agent/    instala o agent e junta ao server com o token
│       ├── app_deploy/   build multi-stage (podman), distribui a imagem, kubectl apply
│       └── backup_sync/  timer na VM 4 que salva /records em ./data_backup
├── app/                  API em Go (main.go, go.mod, Dockerfile multi-stage)
├── k3s/
│   ├── 01-configmap-secret.yaml
│   ├── 02-pvc.yaml
│   ├── 03-deployment.yaml   (postgres + tp2-api)
│   └── 04-service.yaml      (postgres ClusterIP + tp2-api NodePort 30080)
├── scripts/              testes A–D da apresentação + medir-resume.sh
├── data_backup/          synced_folder da VM 4 (conteúdo não versionado)
└── docs/
    ├── relatorio_tecnico.pdf
    └── logs-testes/       saída de todas as execuções de teste (índice em README.md)
```

## Aplicação

API em Go (`app/main.go`), imagem final `FROM scratch` com binário estático (multi-stage).

| Rota | Função |
|---|---|
| `GET /info` | Pod e nó que atenderam, status do banco e total de registros |
| `GET /health` | 200 se o banco responde, 503 caso contrário (liveness/readiness) |
| `GET /records` | Lista os registros |
| `POST /records` | Grava `{"message": "..."}` no PostgreSQL |

O PostgreSQL roda em um Deployment de 1 réplica (`Recreate`) com o PVC `postgres-data`
(1 Gi, `local-path`). A senha fica só no Secret `db-credentials`; o resto, no ConfigMap
`app-config`. A imagem é gerada no bastion e importada no containerd de cada nó
(`imagePullPolicy: Never`), então não há registry.

## Roteiro de testes

Executar a partir de `tp2/` no host (Linux ou Git Bash no Windows).

| Teste | Comando | Esperado |
|---|---|---|
| A — balanceamento via VIP | `bash scripts/teste-a-balanceamento.sh 10` | `pod` alterna entre as duas réplicas (uma em cada nó) |
| B — failover do proxy | `bash scripts/teste-b-failover.sh` | VIP migra para a VM 4 em < 3 s; nenhuma requisição falha; volta ao bastion quando o Nginx retorna |
| C — suspend/resume | `bash scripts/teste-c-ciclo-de-vida.sh` | API de volta em < 60 s e o registro gravado antes continua no banco |
| C' — halt/up | `bash scripts/teste-c-ciclo-de-vida.sh halt` | Pods e VIP restabelecidos sem reprovisionar |
| D — reconciliação | `bash scripts/teste-d-reconciliacao.sh` | O Deployment recria o Pod apagado e volta a 2/2 |

Resultados medidos em um ambiente recriado do zero (detalhes em
[`docs/relatorio_tecnico.pdf`](docs/relatorio_tecnico.pdf)):

| Teste | Resultado |
|---|---|
| `vagrant up` do zero | 11 min 46 s, `failed=0` |
| Idempotência | 2ª execução com `changed=0` nas 4 VMs |
| A | 10 consultas: 6 no pod do k3s-worker, 4 no do k3s-server |
| B | VIP na VM 4 em 1,09 s; 1 de 48 requisições perdida (a que estava em curso) |
| C suspend/resume | API pelo VIP em 51 s (o comando `vagrant resume` termina em ~80 s); registro preservado |
| C halt/up | API em 108 s; pods, VIP e registros restabelecidos |
| D | Pod recriado, 2/2 prontos em 4 s |

Comandos manuais úteis:

```bash
vagrant ssh bastion   -c "ip -4 addr show enp0s8"         # quem está com o VIP
vagrant ssh bastion   -c "sudo systemctl stop nginx"       # provoca o failover
vagrant ssh auxiliary -c "cat /var/lib/app_data/backup.log"
curl -s -X POST -H 'Content-Type: application/json' -d '{"message":"oi"}' http://192.168.56.254/records
```

## Decisões técnicas

- **Interface `enp0s8`, não `eth1`.** A box `ubuntu/jammy64` usa nomes previsíveis; a rede
  host-only é a `enp0s8`. Keepalived e `--flannel-iface` apontam para ela; com `eth1` o VIP
  não sobe e o flannel usa a NAT (onde todas as VMs têm o mesmo IP 10.0.2.15).
- **VRRP unicast.** Os dois proxies anunciam diretamente um ao outro (`unicast_peer`), sem
  depender de multicast na rede host-only do VirtualBox.
- **Health check sem `weight` (estado FAULT).** O `check_nginx.sh` roda a cada 1 s
  (`fall 1`, `timeout 3`). Se o Nginx do bastion falha, a instância entra em FAULT, solta o VIP e anuncia
  prioridade 0, e a VM 4 vira MASTER na hora: 0,6–1,4 s medidos entre o `systemctl stop nginx`
  e o VIP na VM 4. O `timeout 3` existe porque o padrão (igual ao `interval`, 1 s) estourava
  com o bastion ocupado rodando o Ansible e causava failover falso; um Nginx parado faz o
  script falhar na hora, então isso não atrasa o failover real. A primeira versão usava `weight -20` (101 → 81), mas o BACKUP descarta
  anúncios de prioridade menor e só assume após o `master_down_interval`: ~4 s, acima dos
  3 s do roteiro. Quando o Nginx volta, o bastion retoma o VIP (preempção padrão).
- **Banco separado da API.** Com `local-path` o volume pertence a um único nó, então o
  PVC fica só no PostgreSQL (1 réplica). As 2 réplicas da API são *stateless* e se
  espalham pelos dois nós via `topologySpreadConstraints` com `DoNotSchedule` (com
  `ScheduleAnyway` o scheduler chegou a colocar as duas no mesmo nó após um rollout).
- **Service do banco com IP fixo (10.43.0.100).** A API conecta no banco por esse IP em vez
  do nome `postgres`. O nome dependia do CoreDNS, que roda no k3s-server: com o server ainda
  pausado, a API no worker falhava com `lookup postgres: i/o timeout`.
- **Retomada rápida (ordem das VMs).** O `vagrant resume` retoma uma VM por vez, esperando o
  SSH de cada uma (12–33 s por VM neste host). Com a ordem `k3s-worker` → `auxiliary` →
  `k3s-server` → `bastion`, o serviço volta assim que as duas primeiras retomam: o worker
  tem o banco e uma réplica da API, e a auxiliary assume o VIP enquanto o bastion não volta.
  Com a ordem anterior (server primeiro) a API levou 61–80 s em 12/11; com a nova, 38–52 s.
  `scripts/medir-resume.sh` mostra quando cada VM e o VIP voltam.
- **Atualizações automáticas do Ubuntu desativadas.** `apt-daily`, `apt-daily-upgrade` e
  `unattended-upgrades` disparavam logo após um resume/up depois de uma pausa longa e
  saturavam as VMs de 1 vCPU (carga > 4 na auxiliary, SSH estourando o tempo). As
  atualizações são feitas pelo Ansible.
- **Firewall.** O UFW nega entrada por padrão; libera 22 em todos, 80 e VRRP nos proxies,
  6443 do bastion para o server, 30080 dos proxies para os nós K3s e tráfego entre os nós e
  as redes de pods/serviços (10.42/16, 10.43/16). Limitação conhecida: o kube-proxy insere
  suas regras de NodePort (DNAT) antes das do UFW, então a 30080 dos nós K3s continua
  acessível de toda a rede 192.168.56.0/24, não só dos proxies. O ponto de entrada
  documentado e usado nos testes é só o VIP.
- **Traefik e ServiceLB desativados.** O K3s instala os dois por padrão, e eles abririam
  80/443 nos nós do cluster. A borda é o Nginx dos proxies, então ficam em `disable` no
  `/etc/rancher/k3s/config.yaml`, que o Ansible gerencia (mudar a configuração reinicia o
  serviço por handler).
- **Ativação do UFW sem derrubar o Ansible.** Na primeira ativação, o conntrack passa a valer
  e a conexão SSH já aberta pelo Ansible nos nós K3s era descartada, travando o playbook. A
  tarefa roda em `async`, seguida de `meta: reset_connection` e `async_status`.
- **Secret com `data` (base64).** Com `stringData` o `kubectl apply` sempre responde
  `configured`, o que quebra o `changed=0`.
- **Idempotência.** O K3s só é instalado se a unit não existir; a atualização do cache do
  apt não conta como mudança (`changed_when: false`); a imagem só é recompilada
  quando o hash de `main.go`/`go.mod`/`Dockerfile` muda; o `kubectl apply` só reporta
  `changed` quando algum objeto não está `unchanged`.
- **Retomada sem reprovisionamento.** `k3s`, `k3s-agent`, `nginx`, `keepalived` e o timer de
  backup ficam `enabled`; o estado do cluster e o volume do banco ficam no disco das VMs, e
  o `vagrant up` após `halt` não reexecuta os provisionadores.
