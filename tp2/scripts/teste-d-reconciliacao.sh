#!/usr/bin/env bash
# Teste D: apaga um Pod da API e mostra o Deployment recriando a replica.
cd "$(dirname "$0")/.."
vagrant ssh bastion -c '
  set -e
  echo ">>> antes:"; kubectl get pods -l app=tp2-api -o wide
  alvo=$(kubectl get pods -l app=tp2-api -o name | head -n 1)
  echo ">>> $(date +%T) apagando $alvo"
  kubectl delete "$alvo" --wait=false
  inicio=$(date +%s)
  until [ "$(kubectl get deploy tp2-api -o jsonpath="{.status.readyReplicas}")" = "2" ] &&
        ! kubectl get "$alvo" >/dev/null 2>&1; do sleep 1; done
  echo ">>> 2/2 replicas prontas novamente em $(( $(date +%s) - inicio ))s"
  kubectl get pods -l app=tp2-api -o wide
' 2>/dev/null
