#!/bin/bash
# Prepara a box do TP2: instala e pre-carrega tudo o que o provisionamento usa,
# para que o `vagrant up` nao dependa de apt, PPA, get.k3s.io, dl.k8s.io,
# Docker Hub nem do proxy de modulos Go.
#
# Roda dentro da VM builder (box/Vagrantfile). As versoes aqui precisam bater
# com ansible/inventory/hosts.yml (k3s_version / kubectl_version) e com as
# imagens usadas em app/Dockerfile e k3s/03-deployment.yaml.
set -euxo pipefail
export DEBIAN_FRONTEND=noninteractive

K3S_VERSION="v1.31.4+k3s1"
KUBECTL_VERSION="v1.31.4"
POSTGRES_IMAGE="docker.io/library/postgres:16-alpine"
GOLANG_IMAGE="docker.io/library/golang:1.22-alpine"
BAKED=/opt/tp2-box

# --- Pacotes do sistema ------------------------------------------------------
systemctl disable --now apt-daily.timer apt-daily-upgrade.timer unattended-upgrades.service || true
apt-get update
apt-get install -y software-properties-common
add-apt-repository --yes --update ppa:ansible/ansible
apt-get install -y \
  ansible curl htop tcpdump dnsutils jq ufw \
  nginx keepalived podman zstd
# Instalados em todas as VMs (box unica), mas so os proxies os usam: o role
# proxy_ha habilita e inicia os dois servicos onde for preciso.
systemctl disable --now nginx keepalived

install -d -m 0755 "$BAKED"

# --- K3s (instalacao airgap) -------------------------------------------------
k3s_url="https://github.com/k3s-io/k3s/releases/download/${K3S_VERSION/+/%2B}"
curl -sfL -o /usr/local/bin/k3s "$k3s_url/k3s"
chmod 0755 /usr/local/bin/k3s
curl -sfL -o "$BAKED/k3s-airgap-images-amd64.tar.zst" "$k3s_url/k3s-airgap-images-amd64.tar.zst"
curl -sfL -o "$BAKED/sha256sum-amd64.txt" "$k3s_url/sha256sum-amd64.txt"
(
  cd "$BAKED"
  cp /usr/local/bin/k3s k3s
  grep -E ' (k3s|k3s-airgap-images-amd64\.tar\.zst)$' sha256sum-amd64.txt | sha256sum -c -
  rm k3s sha256sum-amd64.txt
)
curl -sfL -o "$BAKED/k3s-install.sh" https://get.k3s.io
chmod 0755 "$BAKED/k3s-install.sh"

# --- kubectl (usado pelo bastion) --------------------------------------------
curl -sfL -o "$BAKED/kubectl" "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
echo "$(curl -sfL "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl.sha256")  $BAKED/kubectl" | sha256sum -c -
chmod 0755 "$BAKED/kubectl"

# --- Imagens de container ----------------------------------------------------
# postgres: vai para o containerd dos nos K3s (importado pelos roles k3s_*).
podman pull "$POSTGRES_IMAGE"
podman save --format docker-archive -o "$BAKED/postgres-16-alpine.tar" "$POSTGRES_IMAGE"
podman rmi "$POSTGRES_IMAGE"
# golang: fica no storage do podman (root) para o build multi-stage no bastion.
podman pull "$GOLANG_IMAGE"

echo "K3S_VERSION=$K3S_VERSION" >  /etc/tp2-box-release
echo "KUBECTL_VERSION=$KUBECTL_VERSION" >> /etc/tp2-box-release
echo "BUILT=$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> /etc/tp2-box-release

# --- Limpeza para reduzir a box ----------------------------------------------
apt-get clean
rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*
journalctl --rotate && journalctl --vacuum-time=1s || true
# Cada VM criada a partir da box precisa de um machine-id proprio.
truncate -s 0 /etc/machine-id
rm -f /var/lib/dbus/machine-id
# Zera o espaco livre para o disco comprimir bem no `vagrant package`.
dd if=/dev/zero of=/EMPTY bs=1M status=none || true
rm -f /EMPTY
sync
