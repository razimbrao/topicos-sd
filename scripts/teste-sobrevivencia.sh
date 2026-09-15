#!/bin/bash
# Teste de Sobrevivencia (secao 4 do roteiro), versao Linux do teste-sobrevivencia.ps1.
# Destroi a VM db e comprova que os logs anteriores sobreviveram.
#
# Precisa do Vagrant, entao roda no HOST Linux que executa o cluster:
#   bash scripts/teste-sobrevivencia.sh
# A VM de validacao (vagrant-linux) nao consegue destruir o db; nela use apenas
# a conferencia dos logs em /projeto/data/dados_persistentes/logs.
set -euo pipefail

raiz="$(cd "$(dirname "$0")/.." && pwd)"
logs="$raiz/data/dados_persistentes/logs"

contar_linhas() {
  for f in "$logs"/*.log; do
    printf "%-15s %s\n" "$(basename "$f")" "$(wc -l < "$f")"
  done
}

cd "$raiz/vagrant"

echo
echo "[1/4] Estado ANTES da destruicao"
contar_linhas
marcador="$(tail -n 1 "$logs/db.log")"
echo "Ultimo registro antes do destroy: $marcador"

echo
echo "[2/4] Simulacao de desastre: vagrant destroy -f db"
vagrant destroy -f db

echo
echo "[3/4] Recuperacao automatizada: vagrant up db"
vagrant up db
echo "Reaplicando o playbook no no reconstruido..."
vagrant provision bastion

echo
echo "[4/4] Auditoria de integridade"
contar_linhas

if grep -qF -- "$marcador" "$logs/db.log"; then
  echo "[APROVADO] O registro anterior ao destroy continua presente."
  echo "O estado sobreviveu a aniquilacao da logica computacional."
else
  echo "[REPROVADO] Continuidade dos logs perdida - verifique o synced_folder."
  exit 1
fi
