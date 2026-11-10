#!/usr/bin/env bash
# Teste C: grava um registro, pausa o ambiente (suspend ou halt), retoma e
# confere que a API, o VIP e o registro voltaram sem reprovisionar.
#   bash scripts/teste-c-ciclo-de-vida.sh          # suspend/resume
#   bash scripts/teste-c-ciclo-de-vida.sh halt     # halt/up
cd "$(dirname "$0")/.."
VIP=${VIP:-192.168.56.254}
MODO=${1:-suspend}
MSG="registro-teste-c-$(date +%s)"

echo ">>> gravando: $MSG"
curl -s -X POST -H 'Content-Type: application/json' -d "{\"message\":\"$MSG\"}" "http://$VIP/records"; echo

if [ "$MODO" = halt ]; then vagrant halt; else vagrant suspend; fi

# Sonda o VIP em paralelo para medir quando o servico realmente volta,
# independente do tempo que o Vagrant leva esperando o SSH de cada VM.
inicio=$SECONDS
(
  until curl -sf --max-time 1 "http://$VIP/health" >/dev/null; do sleep 0.5; done
  echo ">>> API respondendo pelo VIP $((SECONDS - inicio))s apos o inicio da retomada"
) &
SONDA=$!

if [ "$MODO" = halt ]; then vagrant up; else vagrant resume; fi
echo ">>> comando vagrant concluido em $((SECONDS - inicio))s"
wait $SONDA
curl -s "http://$VIP/info"; echo
if curl -s "http://$VIP/records" | grep -q "$MSG"; then
  echo "OK: registro '$MSG' preservado"
else
  echo "FALHA: registro '$MSG' nao encontrado"; exit 1
fi
