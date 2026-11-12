#!/bin/bash
# Gera a box do TP2 e a guarda no repositorio em partes de 90 MB
# (o GitHub recusa arquivos acima de 100 MB).
#
# Uso (no host, dentro de tp2/box):  bash build-box.sh
#
# So e preciso rodar de novo quando bake.sh mudar (versao do K3s, pacotes,
# imagens). Lembre de incrementar VERSION para que o `vagrant up` registre a
# box nova em vez de reutilizar a antiga ja instalada.
set -euo pipefail
cd "$(dirname "$0")"

version="$(tr -d '[:space:]' < VERSION)"
box="tp2-jammy-${version}.box"

vagrant destroy -f
vagrant up --provision
vagrant halt
rm -f "$box"
vagrant package --output "$box"
vagrant destroy -f

rm -rf parts
mkdir parts
split -b 90m -d -a 3 "$box" "parts/${box}."
sha256sum "$box" | awk '{print $1}' > "parts/${box}.sha256"
rm -f "$box"

ls -lh parts
echo "Box ${box} gerada em box/parts/. Faca commit da pasta parts/ e de VERSION."
