#!/usr/bin/env bash
# lab-part-06 step 3 (10 pts)
# Generated from the book's lab source. Do not edit here.
set -euo pipefail
# Some commands in this lab may fail on purpose: the failure is the lesson. Fail-fast is
# therefore switched off from here and the script reports through the grader.
set +e

cd ~/ckne-lab/p05
D="$HOME/ckne-lab/p05"
K="kubectl --kubeconfig $D/kubeconfig --context kind-ckne-lab6-torre"
. ./pedido.txt

echo "ANTES: caidas de paquetes por direccion y motivo"
bash pregunta.sh 'sum by (direction, reason) (cilium_drop_count_total)' | tee caidas-antes.txt

# La politica que corta el paso al Pod bodega: ninguna entrada permitida.
cat <<YAML | $K apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: corta-paso, namespace: faena}
spec:
  podSelector: {matchLabels: {app: bodega}}
  policyTypes: [Ingress]
YAML
sleep 5
echo "INTENTOS_BLOQUEADOS=$INTENTOS_BLOQUEADOS intentos directos desde sondeo:"
$K -n externo exec sondeo -- sh -c "for i in \$(seq $INTENTOS_BLOQUEADOS); do curl -s -o /dev/null -m 2 -w '%{http_code} ' http://bodega.faena/get; echo \"exit \$?\"; done"
sleep 30
echo "DESPUES: caidas de paquetes por direccion y motivo"
bash pregunta.sh 'sum by (direction, reason) (cilium_drop_count_total)' | tee caidas-despues.txt

# Se retira la politica y la aplicacion vuelve a contestar.
$K -n faena delete networkpolicy corta-paso
sleep 5
$K -n externo exec sondeo -- curl -s -o /dev/null -m 3 -w "%{http_code}\n" http://bodega.faena/get

# The answer file the lab asks you to type, from the counters read above:
D="$HOME/ckne-lab/p05"
cat > "$D/03-respuesta.txt" <<RESP
CAIDAS_ENTRANTES_NEGADAS=$(bash pregunta.sh 'sum(cilium_drop_count_total{direction="INGRESS",reason="Policy denied"})')
CODIGO_SIN_LA_POLITICA=$($K -n externo exec sondeo -- curl -s -o /dev/null -m 3 -w "%{http_code}" http://bodega.faena/get)
RESP
cat "$D/03-respuesta.txt"
