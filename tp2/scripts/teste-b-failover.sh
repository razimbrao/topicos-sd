#!/usr/bin/env bash
# Teste B: derruba o Nginx do bastion (MASTER) e mede quanto tempo a VM 4
# (BACKUP) leva para assumir o VIP, com consultas continuas ao /info.
cd "$(dirname "$0")/.."
VIP=${VIP:-192.168.56.254}
LOG=$(mktemp)

(
  end=$((SECONDS + 25))
  while [ $SECONDS -lt $end ]; do
    out=$(curl -s -o /dev/null -D - --max-time 1 -w 'HTTP=%{http_code}' "http://$VIP/info" | tr -d '\r')
    proxy=$(printf '%s' "$out" | awk -F': ' 'tolower($1)=="x-proxy"{print $2}')
    code=$(printf '%s' "$out" | grep -o 'HTTP=[0-9]*')
    echo "$(date +%T.%3N) $code proxy=${proxy:--}" | tee -a "$LOG"
    sleep 0.3
  done
) &
LOOP=$!

sleep 5
echo ">>> $(date +%T.%3N) parando nginx no bastion"
vagrant ssh bastion -c "sudo systemctl stop nginx" 2>/dev/null
sleep 8
echo ">>> VIP na VM 4:"
vagrant ssh auxiliary -c "ip -4 addr show enp0s8 | grep 192.168.56.254" 2>/dev/null
sleep 4
echo ">>> $(date +%T.%3N) religando nginx no bastion (VIP volta ao MASTER)"
vagrant ssh bastion -c "sudo systemctl start nginx" 2>/dev/null
wait $LOOP

echo
echo "Falhas durante o teste: $(grep -vc 'HTTP=200' "$LOG")"
echo "Respostas por proxy:"; grep -o 'proxy=[a-z-]*' "$LOG" | sort | uniq -c
rm -f "$LOG"
