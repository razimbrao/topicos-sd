#!/bin/bash
# Validacao analitica da secao 3 do roteiro: NAT (saida externa) + resolucao de nomes.
# Executar DENTRO de cada VM:  vagrant ssh <vm> -c "bash /scripts/validar-rede.sh"
set -u

echo "=== Validacao de rede em $(hostname) ==="

echo
echo "--- Interfaces (esperado: NAT + host-only) ---"
ip -brief address show

echo
echo "--- Conectividade externa (NAT) ---"
ping -c 3 8.8.8.8 && echo "[OK] saida para a internet" || echo "[FALHA] sem saida NAT"

echo
echo "--- Resolucao de nomes (DNS) ---"
dig +short google.com && echo "[OK] DNS resolvendo" || echo "[FALHA] DNS nao resolve"

echo
echo "--- Conectividade interna host-only ---"
for alvo in 192.168.56.10 192.168.56.11 192.168.56.12 192.168.56.13; do
  if ping -c 1 -W 2 "$alvo" >/dev/null 2>&1; then
    echo "[OK]    $alvo alcancavel"
  else
    echo "[FALHA] $alvo inalcancavel"
  fi
done
