#!/usr/bin/env bash
# Mede o "vagrant resume": quando cada VM volta e quando os NodePorts e o VIP respondem.
# Uso (dentro de tp2/): bash scripts/medir-resume.sh
cd "$(dirname "$0")/.."
vagrant suspend >/dev/null 2>&1; s=$SECONDS
( a=0;b=0;c=0; while [ $((a*b*c)) -eq 0 ] && [ $((SECONDS-s)) -lt 150 ]; do
  [ $b = 0 ] && curl -sf -m 1 http://192.168.56.30:30080/health >/dev/null && { b=1; echo "+$((SECONDS-s))s NodePort k3s-worker OK"; }
  [ $c = 0 ] && curl -sf -m 1 http://192.168.56.254/health >/dev/null && { c=1; echo "+$((SECONDS-s))s VIP OK  <<<"; }
  [ $a = 0 ] && curl -sf -m 1 http://192.168.56.20:30080/health >/dev/null && { a=1; echo "+$((SECONDS-s))s NodePort k3s-server OK"; }
  sleep 0.5; done ) & P=$!
vagrant resume 2>&1 | while IFS= read -r l; do case "$l" in *"Resuming suspended"*|*"booted and ready"*) echo "+$((SECONDS-s))s $l";; esac; done
echo "+$((SECONDS-s))s vagrant resume concluido"
wait $P
