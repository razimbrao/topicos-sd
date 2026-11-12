# Box do TP2

As quatro VMs do TP2 (`bastion`, `k3s-server`, `k3s-worker` e `auxiliary`) são criadas a
partir de uma única **box** do Vagrant, gerada por nós e versionada neste repositório. Ela
traz pré-instalado tudo o que o provisionamento precisa. Assim, o `vagrant up` é mais rápido
e **não depende de nenhum serviço externo**: Vagrant Cloud, apt, PPA, GitHub, dl.k8s.io,
Docker Hub ou proxy de módulos Go.

## O que é uma box

Uma box é a imagem de VM que o Vagrant usa como ponto de partida. O arquivo `.box` é um
pacote compactado com:

| Arquivo | Conteúdo |
|---|---|
| `*.vmdk` | Disco virtual com o sistema operacional já instalado |
| `box.ovf` | Descrição do hardware da VM para o VirtualBox |
| `metadata.json` | Provider ao qual a box se destina (`virtualbox`) |
| `Vagrantfile` | Configurações padrão embutidas na box |

Quando o Vagrantfile declara `config.vm.box = "<nome>"`, o Vagrant procura a box no cache
local (`~/.vagrant.d/boxes/`). Se não encontrar, baixa a partir de `config.vm.box_url` ou
do Vagrant Cloud. Depois importa o disco no VirtualBox e cria cada VM a partir dele.

## Antes e depois

**Antes**, as VMs usavam a `ubuntu/jammy64`, baixada do Vagrant Cloud. O Ubuntu vinha sem
nada instalado e o Ansible baixava durante o provisionamento:

- pacotes do apt (nginx, keepalived, podman, ufw, jq...) e o PPA do Ansible;
- o script `get.k3s.io`, o binário do K3s e as imagens de sistema do K3s;
- o `kubectl` de `dl.k8s.io`;
- as imagens `postgres:16-alpine` e `golang:1.22-alpine` do Docker Hub;
- o módulo Go `github.com/lib/pq` de `proxy.golang.org`.

Além disso, o VirtualBox copiava o disco inteiro (~2,5 GB) para cada uma das quatro VMs.

**Agora:**

```
tp2/box/parts/*  ──(Vagrantfile remonta e confere o SHA-256)──►  box registrada no Vagrant
                                                                         │
                                          importada uma única vez no VirtualBox
                      ┌───────────────┬───────────────┬──────────────────┤
                   bastion       k3s-server      k3s-worker          auxiliary
                                  (linked clones: cada VM grava só as diferenças)
                      │
                      └─ Ansible apenas configura; nada é baixado da internet
```

| | Antes | Agora |
|---|---|---|
| Disco das 4 VMs | 4 cópias completas | 1 importação + 4 clones diferenciais |
| Downloads no provisionamento | Centenas de MB, de vários serviços | Nenhum |
| Dependências externas | Vagrant Cloud, apt, PPA, GitHub, dl.k8s.io, Docker Hub, Go proxy | Nenhuma |

## Conteúdo da box

Gerada a partir da `ubuntu/jammy64` (versão `20241002.0.0`) por [`bake.sh`](bake.sh):

| Item | Onde fica | Quem usa |
|---|---|---|
| Ansible (PPA oficial) | pacote do sistema | `bastion` (nó de controle) |
| Nginx e Keepalived | pacotes do sistema, **desabilitados** | papel `proxy_ha`, que liga só nos proxies |
| Podman | pacote do sistema | `bastion` (build da imagem da API) |
| curl, jq, htop, tcpdump, dnsutils, ufw, zstd | pacotes do sistema | papel `common` |
| Binário do K3s `v1.31.4+k3s1` | `/usr/local/bin/k3s` | papéis `k3s_server` e `k3s_agent` |
| `install.sh` do K3s | `/opt/tp2-box/k3s-install.sh` | idem (com `INSTALL_K3S_SKIP_DOWNLOAD=true`) |
| Imagens de sistema do K3s (airgap) | `/opt/tp2-box/k3s-airgap-images-amd64.tar.zst` | copiadas para `/var/lib/rancher/k3s/agent/images` |
| Imagem `postgres:16-alpine` | `/opt/tp2-box/postgres-16-alpine.tar` | idem; o containerd importa na partida |
| `kubectl v1.31.4` | `/opt/tp2-box/kubectl` | `bastion` (papel `app_deploy`) |
| Imagem `golang:1.22-alpine` | storage do Podman (root) | estágio de build do `app/Dockerfile` |
| Marcador da box | `/etc/tp2-box-release` | papel `common` pula o `apt update` quando ele existe |

Os binários do K3s e do kubectl são conferidos por SHA-256 contra os checksums oficiais
durante o build.

Antes do empacotamento, o `bake.sh` também:

- desativa os timers de atualização automática do apt;
- limpa o cache do apt, os logs e os arquivos temporários;
- esvazia o `/etc/machine-id`, para que cada VM gere o seu próprio no primeiro boot;
- preenche o espaço livre com zeros, para o disco comprimir bem.

O Vagrantfile do builder usa `config.ssh.insert_key = false`. Assim a box mantém a chave
SSH padrão do Vagrant, que o `vagrant up` do TP2 usa no primeiro acesso a cada VM. Depois
ele a troca por uma chave própria de cada VM.

A dependência Go da API (`lib/pq`) não faz parte da box. Ela fica vendorizada em
`tp2/app/vendor`, e o `Dockerfile` compila com `-mod=vendor`.

## Por que a box está dividida em partes

O GitHub recusa arquivos acima de **100 MB**, e a box tem perto de 1 GB. Por isso o
`build-box.sh` divide o arquivo em partes de 90 MB:

```
box/parts/
├── tp2-jammy-1.box.000
├── tp2-jammy-1.box.001
├── ...
└── tp2-jammy-1.box.sha256     SHA-256 do arquivo .box completo
```

Alternativas consideradas:

- **Git LFS**: a cota gratuita do GitHub é de 1 GB de armazenamento e **1 GB de download por
  mês**, o que estouraria no primeiro clone.
- **Asset de GitHub Release**: não teria cota de banda, mas a box ficaria fora do
  repositório git.

O custo das partes no git é o tamanho do repositório: cada versão nova da box acrescenta
cerca de 1 GB ao histórico. Por isso a box só deve ser regerada quando o conteúdo realmente
mudar.

O [`.gitattributes`](../../.gitattributes) marca `tp2/box/parts/**` como binário
(`-text -diff`), para que o git nunca converta fins de linha nem tente gerar diff das partes.

## O que acontece no `vagrant up`

O início do [`tp2/Vagrantfile`](../Vagrantfile) faz o seguinte:

1. Lê `box/VERSION` e define o nome da box como `dcc091a-tp2-jammy-<versão>`.
2. Verifica se essa box já está registrada no Vagrant local
   (`~/.vagrant.d/boxes/dcc091a-tp2-jammy-<versão>`). Se estiver, não faz mais nada: as
   execuções seguintes não pagam nenhum custo.
3. Se não estiver, concatena as partes em `tp2/.vagrant/box/tp2-jammy-<versão>.box` e
   confere o SHA-256 contra `parts/*.sha256`. Se as partes faltarem ou o checksum não bater,
   apenas exibe um aviso: comandos como `status`, `halt` e `destroy` continuam funcionando, e
   só o `vagrant up` de uma VM nova falha, por não encontrar a box.
4. Usa o arquivo remontado como `config.vm.box_url` (`file:///...`). O Vagrant registra a
   box localmente e importa o disco no VirtualBox.
5. Cria as quatro VMs como **linked clones** (`v.linked_clone = true`): o VirtualBox guarda
   o disco da box uma vez, como VM mestre, e cada VM aponta para ele gravando só as próprias
   alterações.

`config.vm.box_check_update = false` evita que o Vagrant tente consultar atualizações da box
na internet.

O arquivo remontado em `tp2/.vagrant/box/` pode ser apagado depois do primeiro `vagrant up`,
porque a box já fica registrada no Vagrant. Ele está fora do git, porque `.vagrant/` é
ignorado.

## Gerando uma nova versão da box

Só é preciso regerar a box quando o conteúdo do `bake.sh` mudar: versão do K3s ou do
kubectl, um pacote novo, uma imagem de container nova, etc.

1. Altere o [`bake.sh`](bake.sh). Se mudar a versão do K3s ou do kubectl, altere também
   `k3s_version` e `kubectl_version` em
   [`ansible/inventory/hosts.yml`](../ansible/inventory/hosts.yml).
2. Incremente o número em [`VERSION`](VERSION). O nome da box inclui a versão, então o
   Vagrant a trata como uma box nova em vez de reaproveitar a antiga do cache.
3. Gere a box. Este é o **único passo que precisa de internet**, e precisa ser feito com as
   VMs do TP2 desligadas para não faltar memória:

   ```bash
   cd tp2/box
   bash build-box.sh
   ```

   O script:
   - sobe a VM temporária `dcc091a-tp2-box-builder` a partir da `ubuntu/jammy64`;
   - roda o `bake.sh`;
   - desliga a VM e gera o `.box` com `vagrant package`;
   - destrói a VM temporária;
   - recria `parts/` com as partes novas e o `.sha256`.
4. Faça commit de `box/VERSION` e `box/parts/`.
5. Para usar a box nova, as VMs existentes precisam ser recriadas:

   ```bash
   cd tp2
   vagrant destroy -f
   vagrant up
   ```

As boxes antigas continuam no cache do Vagrant. Para liberar espaço:

```bash
vagrant box list
vagrant box remove dcc091a-tp2-jammy-<versão-antiga>
```

## Arquivos desta pasta

| Arquivo | Função |
|---|---|
| `Vagrantfile` | Define a VM temporária usada só para gerar a box |
| `bake.sh` | Instala e pré-carrega tudo dentro da VM temporária |
| `build-box.sh` | Orquestra o build: sobe, prepara, empacota, divide e limpa |
| `VERSION` | Versão atual da box (faz parte do nome registrado no Vagrant) |
| `parts/` | A box dividida em partes de 90 MB + o SHA-256 do arquivo completo |

## Solução de problemas

| Sintoma | Causa provável | O que fazer |
|---|---|---|
| `AVISO: partes da box nao encontradas` (e o `vagrant up` não acha a box) | Clone sem `box/parts/` ou box nunca gerada | Conferir o clone; se preciso, rodar `build-box.sh` |
| `AVISO: checksum da box nao confere` | Parte corrompida ou incompleta (por exemplo, conversão de fim de linha) | Verificar se o `.gitattributes` está presente e refazer o checkout de `box/parts/` |
| VM nova ainda roda `apt update` | VM criada de outra box (sem `/etc/tp2-box-release`) | Recriar as VMs com `vagrant destroy -f && vagrant up` |
| Pod do postgres em `ErrImagePull` | Imagem não importada no containerd | Verificar se `/var/lib/rancher/k3s/agent/images/postgres-16-alpine.tar` existe no nó |
| Mudou o `bake.sh` mas nada mudou nas VMs | `VERSION` não foi incrementado, ou as VMs não foram recriadas | Incrementar `VERSION`, regerar, `vagrant destroy -f && vagrant up` |
