#!/bin/bash
set -u

command -v nmap >/dev/null || { echo "nmap nao encontrado (apt-get install -y nmap)"; exit 1; }

declare -A vms=( [bastion]=192.168.56.10 [web1]=192.168.56.11 [web2]=192.168.56.12 [db]=192.168.56.20 )

for nome in bastion web1 web2 db; do
  ip=${vms[$nome]}
  echo
  echo "=========== $nome ($ip) ==========="

  echo
  echo "--- Teste 1: SSH somente por chave (esperado: Permission denied) ---"
  ssh -o PreferredAuthentications=password -o PubkeyAuthentication=no -o StrictHostKeyChecking=no \
      -o UserKnownHostsFile=/dev/null -o BatchMode=yes -o ConnectTimeout=5 "vagrant@$ip" exit

  echo
  echo "--- Teste 2: login direto de root (esperado: negado) ---"
  ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
      -o BatchMode=yes -o ConnectTimeout=5 "root@$ip" exit

  echo
  echo "--- Teste 3: varredura de portas (esperado: apenas 22, 80, 443) ---"
  nmap -Pn -p 22,80,443,514,3306,8080 "$ip"
done

echo
echo "Colete esta saida para o relatorio em docs/."
