#!/usr/bin/env bash
# Teste A: consultas periodicas ao VIP /info mostram qual Pod/no atendeu.
VIP=${VIP:-192.168.56.254}
N=${1:-10}
for i in $(seq 1 "$N"); do
  resp=$(curl -s -D - --max-time 3 "http://$VIP/info")
  proxy=$(printf '%s' "$resp" | tr -d '\r' | awk -F': ' 'tolower($1)=="x-proxy"{print $2}')
  body=$(printf '%s' "$resp" | tail -n 1)
  echo "$(date +%T) proxy=$proxy $body"
  sleep 0.5
done
